# == Class: clustercontrol::configure_mysql
#
# Configures MySQL Community Server 8.4, sets root password, creates cmon user
# with proper grants using mysql_native_password authentication.
#
# Why MySQL 8.4 (not MariaDB)?
#   This module uses MySQL Community 8.4 LTS to match Severalnines' cc-ansible
#   reference implementation. The previous MariaDB-based approach hit a known
#   EL9 systemd cgroup tracking issue producing:
#     "mariadb.service: Will not start ... while processes exist"
#     "Failed to run 'start-pre' task: Device or resource busy"
#   MySQL Community uses Type=notify with proper systemd integration.
#
# Initialization flow:
#   1. install/redhat.pp or install/debian.pp installs MySQL community packages
#      and runs mysqld --initialize-insecure (RHEL) on first install,
#      leaving root with no password.
#   2. Service[mysqld] ensures the daemon is enabled and running.
#   3. Exec[wait-for-mysql-ready] polls mysqladmin ping for up to 60s.
#   4. /etc/my.cnf is written with mysql_native_password=ON (required for
#      MySQL 8 to enable legacy auth plugin used by ClusterControl).
#   5. Root password is set via ALTER USER ... IDENTIFIED WITH mysql_native_password.
#   6. /root/.my.cnf gets written so subsequent mysql commands authenticate.
#   7. cmon user is created with mysql_native_password on localhost, 127.0.0.1,
#      and the controller IP.
#
class clustercontrol::configure_mysql {

  $mysql_daemon       = $clustercontrol::params::mysql_daemon
  $mysql_config_file  = $clustercontrol::params::mysql_config_file
  $mysql_socket       = $clustercontrol::params::mysql_socket
  $mysql_pid_file     = $clustercontrol::params::mysql_pid_file
  $mysql_root_pass    = $clustercontrol::mysql_root_password
  $cmon_user          = $clustercontrol::cmon_mysql_user
  $cmon_pass          = $clustercontrol::cmon_mysql_password
  $controller_ip      = $clustercontrol::controller_ip

  # ----------------------------------------------------------------------------
  # Ensure MySQL is running and enabled at boot
  # ----------------------------------------------------------------------------
  service { $mysql_daemon:
    ensure => running,
    enable => true,
  }

  # ----------------------------------------------------------------------------
  # Wait for MySQL to be fully ready
  # ----------------------------------------------------------------------------
  exec { 'wait-for-mysql-ready':
    command  => 'for i in $(seq 1 60); do mysqladmin ping >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1',
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    provider => shell,
    unless   => '[ ! -x /usr/bin/mysqladmin ] || mysqladmin ping >/dev/null 2>&1',
    require  => Service[$mysql_daemon],
  }

  # ----------------------------------------------------------------------------
  # /etc/my.cnf (RHEL) or /etc/mysql/my.cnf (Debian)
  #
  # No `notify => Service[mysqld]` - settings take effect on next natural restart.
  # mysql_native_password=ON is critical for MySQL 8 ClusterControl compatibility.
  # ----------------------------------------------------------------------------
  file { $mysql_config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('clustercontrol/my.cnf.erb'),
    require => Exec['wait-for-mysql-ready'],
  }

  # ----------------------------------------------------------------------------
  # Bootstrap root password
  #
  # MySQL 8 init-insecure creates a passwordless root@localhost. Set the real
  # password using IDENTIFIED WITH mysql_native_password for ClusterControl
  # compatibility. The unless check tries logging in with the target password;
  # if that succeeds, root password is already set.
  # ----------------------------------------------------------------------------
  exec { 'set-mysql-root-password':
    command  => "mysql --no-defaults -u root -NBe \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${mysql_root_pass}';\"",
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe 'SELECT 1;' >/dev/null 2>&1",
    provider => shell,
    require  => [
      Service[$mysql_daemon],
      Exec['wait-for-mysql-ready'],
    ],
  }

  # ----------------------------------------------------------------------------
  # Write /root/.my.cnf so subsequent mysql commands authenticate automatically
  # ----------------------------------------------------------------------------
  file { '/root/.my.cnf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => "[client]\nuser=root\npassword=${mysql_root_pass}\n",
    require => Exec['set-mysql-root-password'],
  }

  # ----------------------------------------------------------------------------
  # Create cmon user with mysql_native_password authentication on each host
  # ----------------------------------------------------------------------------
  $cmon_hosts = ['localhost', '127.0.0.1', $controller_ip]

  $cmon_hosts.each |$host| {
    exec { "create-cmon-user-${host}":
      command  => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"CREATE USER IF NOT EXISTS '${cmon_user}'@'${host}' IDENTIFIED WITH mysql_native_password BY '${cmon_pass}'; ALTER USER '${cmon_user}'@'${host}' IDENTIFIED WITH mysql_native_password BY '${cmon_pass}'; GRANT ALL PRIVILEGES ON *.* TO '${cmon_user}'@'${host}' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      path     => ['/bin', '/usr/bin', '/usr/local/bin'],
      provider => shell,
      unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM mysql.user WHERE User='${cmon_user}' AND Host='${host}' AND plugin='mysql_native_password';\" 2>/dev/null | grep -q 1",
      require  => [
        Service[$mysql_daemon],
        File['/root/.my.cnf'],
      ],
    }
  }
}
