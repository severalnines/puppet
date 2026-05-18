# == Class: clustercontrol::configure_mysql
#
# Configures MySQL, sets root password, creates cmon user with proper grants.
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
  # /etc/my.cnf  (or /etc/mysql/my.cnf on Debian)
  # ----------------------------------------------------------------------------
  file { $mysql_config_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('clustercontrol/my.cnf.erb'),
    notify  => Service[$mysql_daemon],
  }

  # ----------------------------------------------------------------------------
  # Ensure MySQL is running
  # ----------------------------------------------------------------------------
  service { $mysql_daemon:
    ensure => running,
    enable => true,
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
    require  => Service[$mysql_daemon],
  }

  # ----------------------------------------------------------------------------
  # Write /root/.my.cnf so subsequent mysql commands authenticate automatically
  # 
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
      unless   => "mysql -u ${cmon_user} -p\"${cmon_pass}\" -h${host} -NBe 'SELECT 1;' >/dev/null 2>&1",
      require  => [
        Service[$mysql_daemon],
        File['/root/.my.cnf'],
      ],
    }
  }
}
