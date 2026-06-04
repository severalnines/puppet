# == Class: clustercontrol::configure_mysql
#
# Configures MySQL/MariaDB, sets root password, creates cmon user with proper
# grants.
#
# Initialisation flow (matters for first-install on RHEL family):
#   1. Service[mariadb] ensures the daemon is enabled and running.
#   2. Exec[wait-for-mariadb-ready] polls mysqladmin ping for up to 60s,
#      guaranteeing the daemon has finished its first-time initialisation
#      (mariadb-prepare-db-dir on EL takes ~10-15s) before any work runs.
#      Without this gate, writing /etc/my.cnf and notifying Service[mariadb]
#      mid-init races with systemd and leaves an orphaned mariadbd.
#   3. /etc/my.cnf is written; the file does NOT notify Service[mariadb].
#      Triggering a restart from inside the catalog hits the same race in
#      some package timing scenarios. The tunables in our template are not
#      required for ClusterControl to function; they are applied on the
#      next natural mariadb restart (admin action, upgrade, or reboot).
#   4. Root password is set (only if not already set).
#   5. /root/.my.cnf gets written so subsequent mysql commands authenticate.
#   6. cmon user is created on localhost, 127.0.0.1, and the controller IP.
#
class clustercontrol::configure_mysql {

  $mysql_daemon       = $clustercontrol::params::mysql_daemon
  $mysql_config_file  = $clustercontrol::params::mysql_config_file
  $mysql_socket       = $clustercontrol::params::mysql_socket
  $mysql_root_pass    = $clustercontrol::mysql_root_password
  $cmon_user          = $clustercontrol::cmon_mysql_user
  $cmon_pass          = $clustercontrol::cmon_mysql_password
  $controller_ip      = $clustercontrol::controller_ip

  # ----------------------------------------------------------------------------
  # Ensure MariaDB is running and enabled at boot
  # ----------------------------------------------------------------------------
  service { $mysql_daemon:
    ensure => running,
    enable => true,
  }

  # ----------------------------------------------------------------------------
  # Wait for MariaDB to be fully ready (mariadb-prepare-db-dir can take 10-15s
  # on first install). This gate prevents subsequent steps from racing the
  # post-install init window that causes the well-known systemd error:
  #   "mariadb.service: Will not start ... while processes exist"
  #   "Failed to run 'start-pre' task: Device or resource busy"
  # ----------------------------------------------------------------------------
  exec { 'wait-for-mariadb-ready':
    command  => 'for i in $(seq 1 60); do mysqladmin ping >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1',
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    provider => shell,
    unless   => '[ ! -x /usr/bin/mysqladmin ] || mysqladmin ping >/dev/null 2>&1',
    require  => Service[$mysql_daemon],
  }

  # ----------------------------------------------------------------------------
  # /etc/my.cnf  (or /etc/mysql/my.cnf on Debian)
  #
  # No `notify => Service[mariadb]` on purpose - see class header.
  # ----------------------------------------------------------------------------
  file { $mysql_config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('clustercontrol/my.cnf.erb'),
    require => Exec['wait-for-mariadb-ready'],
  }

  # ----------------------------------------------------------------------------
  # Bootstrap root password (only if root can login without password)
  # Uses ALTER USER which works on both MySQL and MariaDB.
  # The onlyif first checks mysql command exists (safe in noop before packages
  # are installed), then checks if root can login without a password.
  # ----------------------------------------------------------------------------
  exec { 'set-mysql-root-password':
    command  => "mysql -u root -NBe \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_pass}';\"",
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe 'SELECT 1;' >/dev/null 2>&1",
    provider => shell,
    require  => [
      Service[$mysql_daemon],
      Exec['wait-for-mariadb-ready'],
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
  # Create cmon user for each required host (localhost, 127.0.0.1, controller IP)
  # Uses single SQL statement per host
  # ----------------------------------------------------------------------------
  $cmon_hosts = ['localhost', '127.0.0.1', $controller_ip]

  $cmon_hosts.each |$host| {
    exec { "create-cmon-user-${host}":
      command  => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"CREATE USER IF NOT EXISTS '${cmon_user}'@'${host}' IDENTIFIED BY '${cmon_pass}'; ALTER USER '${cmon_user}'@'${host}' IDENTIFIED BY '${cmon_pass}'; GRANT ALL PRIVILEGES ON *.* TO '${cmon_user}'@'${host}' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      path     => ['/bin', '/usr/bin', '/usr/local/bin'],
      provider => shell,
      unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM mysql.user WHERE User='${cmon_user}' AND Host='${host}';\" 2>/dev/null | grep -q 1",
      require  => [
        Service[$mysql_daemon],
        File['/root/.my.cnf'],
      ],
    }
  }
}
