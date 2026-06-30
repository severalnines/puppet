# == Class: clustercontrol::configure_mysql
#
# Configures MySQL Community Server 8.4, sets root password, creates cmon user
# with proper grants using mysql_native_password authentication.
#
# Critical for MySQL 8.4:
#   In MySQL 8.4 LTS, mysql_native_password is DEPRECATED and DISABLED BY
#   DEFAULT. It must be explicitly enabled in my.cnf BEFORE mysqld loads,
#   otherwise ALTER USER ... IDENTIFIED WITH mysql_native_password fails:
#     ERROR 1524 (HY000): Plugin 'mysql_native_password' is not loaded
#
# Order of operations:
#   1. Write /etc/my.cnf with `mysql_native_password = ON`
#   2. Start mysqld (Service requires File[my.cnf] so config is in place)
#   3. One-shot restart on first install to guarantee plugin is loaded
#      (covers the case where mysqld was already started by the package
#      before our my.cnf was written). Guarded by a marker file so this
#      only runs once.
#   4. Wait for mysqld to be ready
#   5. Set root password (now possible because plugin is loaded)
#   6. Create cmon user with mysql_native_password auth
#
class clustercontrol::configure_mysql {

  $mysql_daemon       = $clustercontrol::params::mysql_daemon
  $mysql_config_file  = $clustercontrol::params::mysql_config_file
  $mysql_socket       = $clustercontrol::params::mysql_socket
  $mysql_pid_file     = $clustercontrol::params::mysql_pid_file
  $mysql_init_marker  = $clustercontrol::params::mysql_init_marker
  $cmon_state_dir     = $clustercontrol::params::cmon_state_dir
  $mysql_root_pass    = $clustercontrol::mysql_root_password
  $cmon_user          = $clustercontrol::cmon_mysql_user
  $cmon_pass          = $clustercontrol::cmon_mysql_password
  $controller_ip      = $clustercontrol::controller_ip

  # ----------------------------------------------------------------------------
  # Step 1: Write /etc/my.cnf
  #
  # Notifies a restart so a config change picked up at any point reloads the
  # daemon and updates the plugin set.
  # ----------------------------------------------------------------------------
  file { $mysql_config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('clustercontrol/my.cnf.erb'),
    notify  => Exec['restart-mysqld-after-mycnf-change'],
  }

  # ----------------------------------------------------------------------------
  # Step 2: Ensure mysqld is running and enabled at boot
  # ----------------------------------------------------------------------------
  service { $mysql_daemon:
    ensure  => running,
    enable  => true,
    require => File[$mysql_config_file],
  }

  # ----------------------------------------------------------------------------
  # Step 3a: Restart mysqld when my.cnf is changed at any time
  # (refreshonly - only runs when notified)
  # ----------------------------------------------------------------------------
  exec { 'restart-mysqld-after-mycnf-change':
    command     => "systemctl restart ${mysql_daemon} && sleep 3",
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider    => shell,
    refreshonly => true,
    require     => Service[$mysql_daemon],
  }

  # ----------------------------------------------------------------------------
  # Step 3b: Ensure cmon_state_dir exists so we can write marker files
  # ----------------------------------------------------------------------------
  file { $cmon_state_dir:
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
  }

  # ----------------------------------------------------------------------------
  # Step 3c: First-run-only restart to guarantee my.cnf is loaded
  #
  # The package may have started mysqld with stock config before our my.cnf
  # was written. This restart guarantees the plugin is loaded on first run.
  # Idempotent via $mysql_init_marker - runs exactly once.
  # ----------------------------------------------------------------------------
  exec { 'first-run-restart-mysqld':
    command  => "systemctl restart ${mysql_daemon} && sleep 3 && touch ${mysql_init_marker}",
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    creates  => $mysql_init_marker,
    require  => [
      Service[$mysql_daemon],
      File[$cmon_state_dir],
    ],
  }

  # ----------------------------------------------------------------------------
  # Step 4: Wait for MySQL to be fully ready
  # ----------------------------------------------------------------------------
  exec { 'wait-for-mysql-ready':
  command  => "for i in $(seq 1 60); do (mysqladmin ping >/dev/null 2>&1 || mysqladmin -u root -p\"${mysql_root_pass}\" ping >/dev/null 2>&1) && exit 0; sleep 1; done; exit 1",
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    provider => shell,
    unless   => "[ ! -x /usr/bin/mysqladmin ] || mysqladmin ping >/dev/null 2>&1 || mysqladmin -u root -p\"${mysql_root_pass}\" ping >/dev/null 2>&1",
    require  => Exec['first-run-restart-mysqld'],
  }

  # ----------------------------------------------------------------------------
  # Step 5: Bootstrap root password
  #
  # MySQL 8 init-insecure creates a passwordless root@localhost. Set the real
  # password using IDENTIFIED WITH mysql_native_password.
  # The unless check first tries logging in with the target password; if that
  # succeeds, root password is already set.
  # ----------------------------------------------------------------------------
  exec { 'set-mysql-root-password':
    command  => "mysql --no-defaults -u root -NBe \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${mysql_root_pass}';\"",
    path     => ['/bin', '/usr/bin', '/usr/local/bin'],
    unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe 'SELECT 1;' >/dev/null 2>&1",
    provider => shell,
    require  => Exec['wait-for-mysql-ready'],
  }

  # ----------------------------------------------------------------------------
  # Step 6: Write /root/.my.cnf so subsequent mysql commands authenticate
  # ----------------------------------------------------------------------------
  file { '/root/.my.cnf':
     ensure    => file,
     owner     => 'root',
     group     => 'root',
     mode      => '0600',
     show_diff => false,
     content   => "[client]\nuser=root\npassword=${mysql_root_pass}\n",
     require   => Exec['set-mysql-root-password'],
  }

  # ----------------------------------------------------------------------------
  # Step 7: Create cmon user with mysql_native_password on each host
  # ----------------------------------------------------------------------------
  $cmon_hosts = ['localhost', '127.0.0.1', $controller_ip]

  $cmon_hosts.each |$host| {
    exec { "create-cmon-user-${host}":
      command  => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"CREATE USER IF NOT EXISTS '${cmon_user}'@'${host}' IDENTIFIED WITH mysql_native_password BY '${cmon_pass}'; ALTER USER '${cmon_user}'@'${host}' IDENTIFIED WITH mysql_native_password BY '${cmon_pass}'; GRANT ALL PRIVILEGES ON *.* TO '${cmon_user}'@'${host}' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      path     => ['/bin', '/usr/bin', '/usr/local/bin'],
      provider => shell,
      unless   => "[ ! -x /usr/bin/mysql ] || mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM mysql.user WHERE User='${cmon_user}' AND Host='${host}' AND plugin='mysql_native_password';\" 2>/dev/null | grep -q 1",
      require  => File['/root/.my.cnf'],
    }
  }
}
