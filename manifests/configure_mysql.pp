# == Class: clustercontrol::configure_mysql
#
# Configures MySQL/MariaDB, sets root password, creates cmon user with proper grants.
#
# First-install race-condition note (fixed):
#   When the mariadb-server package is first installed, the package's
#   post-install hook runs mariadb-prepare-db-dir which initialises
#   /var/lib/mysql/ and starts the daemon. That process can take 10-15
#   seconds. If File[/etc/my.cnf] notifies Service[mariadb] during this
#   window, systemd tries to restart the service while it is still busy.
#   On RHEL-family systems this triggers:
#     "mariadb.service: Will not start ... while processes exist"
#     "Failed to run 'start-pre' task: Device or resource busy"
#   leaving mariadbd orphaned and systemd marking the unit failed.
#
#   Fix:
#     1. Wait for mariadbd to be ready (mysqladmin ping) BEFORE doing
#        any work that would trigger a restart.
#     2. Decouple my.cnf write from the immediate Service notify.
#     3. Use a marker-guarded refresh exec so config-change restarts
#        happen ONCE and only after mariadbd has confirmed ready.
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
  # Ensure MariaDB is running (do this FIRST, before touching my.cnf)
  # ----------------------------------------------------------------------------
  service { $mysql_daemon:
    ensure => running,
    enable => true,
  }

  # ----------------------------------------------------------------------------
  # Wait for MariaDB to be fully ready (mariadb-prepare-db-dir can take ~10-15s
  # on first install). This avoids the systemd race where a config-change
  # restart hits a still-initialising daemon.
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
  # NOTE: No "notify => Service[mariadb]" here on purpose. Triggering an
  # immediate restart during first-install package post-install causes the
  # systemd race condition documented at the top of this file. Instead, the
  # restart is handled by the marker-guarded refresh exec below, which only
  # runs AFTER wait-for-mariadb-ready confirms the daemon is healthy.
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
  # Marker-guarded restart of MariaDB after first config write.
  # Only refreshes once per host lifetime (marker file). Safe on re-runs.
  # ----------------------------------------------------------------------------
  exec { 'restart-mariadb-after-config':
    command     => "systemctl restart ${mysql_daemon} && for i in \$(seq 1 60); do mysqladmin ping >/dev/null 2>&1 && exit 0; sleep 1; done; exit 1",
    path        => ['/bin', '/usr/bin', '/usr/local/bin'],
    provider    => shell,
    refreshonly => true,
    subscribe   => File[$mysql_config_file],
    creates     => '/var/lib/mysql/.puppet-config-applied',
  }

  exec { 'mark-mariadb-config-applied':
    command  => 'touch /var/lib/mysql/.puppet-config-applied',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    creates  => '/var/lib/mysql/.puppet-config-applied',
    require  => [
      Exec['wait-for-mariadb-ready'],
      File[$mysql_config_file],
    ],
  }

  # ----------------------------------------------------------------------------
  # Bootstrap root password (only if root can login without password)
  # Uses ALTER USER which works on both MySQL and MariaDB.
  # ----------------------------------------------------------------------------
  exec { 'set-mysql-root-password':
    command  => "mysql -u root -NBe \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_pass}';\"",
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe 'SELECT 1;' >/dev/null 2>&1",
    provider => shell,
    require  => [
      Service[$mysql_daemon],
      Exec['wait-for-mariadb-ready'],
      Exec['mark-mariadb-config-applied'],
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
      unless   => "[ ! -x /usr/bin/mysql ] || mysql -u ${cmon_user} -p\"${cmon_pass}\" -h${host} -NBe 'SELECT 1;' >/dev/null 2>&1",
      require  => [
        Service[$mysql_daemon],
        File['/root/.my.cnf'],
      ],
    }
  }
}
