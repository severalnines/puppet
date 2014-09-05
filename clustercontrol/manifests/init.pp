# Class: clustercontrol
#
# This module manages clustercontrol
#
# Parameters: none
#
# Actions:
#
# Requires: see Modulefile
#
# Sample Usage:
#

class clustercontrol (
  $is_controller            = true,
  $clustercontrol_host      = '', 
  $cluster_id               = '1',
  $cluster_name             = 'default_cluster_1',
  $cluster_type             = 'galera',
  $ip_address               = $ipaddress,
  $email_address            = 'admin@domain.com',
  $api_token                = '',
  $ssh_user                 = 'root',
  $ssh_port                 = '22',
  $ssh_key_type             = 'ssh-rsa',
  $ssh_key                  = '',
  $ssh_opts                 = undef,
  $sudo_password            = undef,
  $mysql_server_addresses   = '',
  $mysql_root_password      = 'password',
  $mysql_cmon_root_password = 'password',
  $mysql_cmon_password      = 'cmon',
  $mysql_cmon_port          = '3306',
  $skip_name_resolve        = '1',
  $galera_port              = '4567',
  $vendor                   = 'percona',
  $datanode_addresses       = undef,
  $mgmnode_addresses        = undef,
  $ndb_connectstring        = undef,
  $ndb_binary               = 'ndbd',
  $mysql_basedir            = '/usr',
  $datadir                  = '/var/lib/mysql',
  $mongodb_server_addresses       = '',
  $mongoarbiter_server_addresses  = undef,
  $mongocfg_server_addresses      = undef,
  $mongos_server_addresses  = undef,
  $mongodb_basedir          = '/usr',
  $modulepath               = '/etc/puppet/modules/clustercontrol',
  $use_repo                 = true,
  $enabled                  = true,
) {
  if $enabled {
    $service_status = 'running'
  } else {
    $service_status = 'stopped'
  }
  
  if ($ssh_user == 'root') { 
    $user_home            = '/root'
    $real_sudo_password   = undef
  } else { 
    $user_home            = "/home/$ssh_user"
    $rssh_opts             = '-nqtt'
    if ($sudo_password  != undef) { $real_sudo_password = "echo $sudo_password | sudo -S" } else { $real_sudo_password = 'sudo' }
  }
    
  $ssh_identity     = "$user_home/.ssh/id_rsa_s9s"
  $ssh_identity_pub = "$user_home/.ssh/id_rsa_s9s.pub"
  $backup_dir       = "$user_home/backups"
  $staging_dir      = "$user_home/s9s_tmp"
  
  Exec { path => ['/usr/bin','/bin',"$mysql_basedir/bin"]}
  
  if $is_controller {
    
    include clustercontrol::params
	  
	  service { $clustercontrol::params::mysql_service :
	    ensure       => running,
	    enable       => true,
	    hasrestart   => true,
	    hasstatus    => true,
	    require      => [
	      Package[$clustercontrol::params::mysql_packages],
	      File[$datadir],
	      ],
	    notify     => Exec['create-root-password'],
	    subscribe  => File[$clustercontrol::params::mysql_cnf]
	  }
	  
	  file { $clustercontrol::params::mysql_cnf :
	    ensure   => present,
	    content  => template('clustercontrol/my.cnf.erb'),
	    owner    => root, group => root,
	    mode     => 644
	    }
	  
	  package { $clustercontrol::params::mysql_packages :
	    ensure  => installed,
	    notify  => Exec['disable-extra-security']
	  }
	  
	  exec { 'create-root-password' :
	    onlyif  => "mysqladmin -u root status",
	    command => "mysqladmin -u root password \"$mysql_cmon_root_password\"",
	    notify  => Exec[
	      'grant-cmon-localhost', 
	      'grant-cmon-127.0.0.1', 
	      'grant-cmon-ip-address',
	      'grant-cmon-fqdn'
	      ]
	  }
	  
	  exec { "grant-cmon-localhost" :
	    unless  => "mysqladmin -u cmon -p \"$mysql_cmon_password\" -hlocalhost status",
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@localhost IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
	  }
	  
	  exec { "grant-cmon-127.0.0.1" :
	    unless  => "mysqladmin -u cmon -p \"$mysql_cmon_password\" -h127.0.0.1 status",
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@127.0.0.1 IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
	  }
	  
	  exec { "grant-cmon-ip-address" :
	    unless  => "mysqladmin -u cmon -p \"$mysql_cmon_password\" -h\"$ip_address\" status",
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"$ip_address\" IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
	  }
	  
	  exec { "grant-cmon-fqdn" :
	    unless  => "mysqladmin -u cmon -p \"$mysql_cmon_password\" -h\"$fqdn\" status",
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"$fqdn\" IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
	  }
	  
	  exec { "create-cmon-db" :
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE SCHEMA IF NOT EXISTS cmon;'",
	    notify  => Exec['import-cmon-db']
	  }
	
	  exec { "create-dcps-db" :
	    command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE SCHEMA IF NOT EXISTS dcps;'",
	    notify  => Exec['import-dcps-db']
	  }
	  
	  exec { "import-cmon-db" :
	    onlyif  => [
	      "test -f $clustercontrol::params::cmon_sql_path/cmon_db.sql",
	      "test -f $clustercontrol::params::cmon_sql_path/cmon_data.sql"
	    ],
	    command => "mysql -f -u root -p\"$mysql_cmon_root_password\" cmon < $clustercontrol::params::cmon_sql_path/cmon_db.sql && \
	    mysql -f -u root -p\"$mysql_cmon_root_password\" cmon < $clustercontrol::params::cmon_sql_path/cmon_data.sql",
	    notify => Exec['configure-cmon-db']
	  }
	  
	  exec { 'configure-cmon-db' :
	    onlyif  => [
        "test -f $clustercontrol::params::cmon_sql_path/cmon_db.sql",
        "test -f $clustercontrol::params::cmon_sql_path/cmon_data.sql"
      ],
      command => "mysql -f -u root -p\"$mysql_cmon_root_password\" cmon < /tmp/configure_cmon_db.sql",
      require => File["/tmp/configure_cmon_db.sql"]
	  }
	  
	  file { '/tmp/configure_cmon_db.sql' :
	     ensure  => present,
	     content => template('clustercontrol/configure_cmon_db.sql.erb')
	  }
	  
	  exec { "import-dcps-db" :
	    onlyif  => "test -f $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
	    command => "mysql -f -u root -p\"$mysql_cmon_root_password\" dcps < $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
	  }
	  
	  file { $datadir :
	    ensure  => directory,
	    owner   => mysql, group => mysql,
	    require => Package[$clustercontrol::params::mysql_packages],
	    notify  => Service[$clustercontrol::params::mysql_service]
	  }
	  
	  file { $clustercontrol::params::cmon_conf :
      content => template('clustercontrol/cmon.cnf.erb'),
      owner   => root, group => root,
      mode    => 600,
      require => Package[$clustercontrol::params::cc_controller],
      notify  => [Exec['create-cmon-db'],Service['cmon']]
    }
	  
	  package { $clustercontrol::params::cc_controller :
	    ensure => installed,
	    require => [$clustercontrol::params::severalnines_repo,Package[$clustercontrol::params::cc_dependencies]]
	  }
	
	  package { $clustercontrol::params::cc_dependencies :
	    ensure  => installed,
	    notify  => [
	      Exec ['allow-override-all'],
	      File [$clustercontrol::params::cert_file, $clustercontrol::params::key_file, $clustercontrol::params::apache_ssl_conf_file]
	    ]
	  }
	  
	  package { $clustercontrol::params::cc_ui : 
	    ensure  => present, 
	    require => Package[$clustercontrol::params::cc_controller],
	    notify  => Exec['create-dcps-db']
	  }
	  
	  package { $clustercontrol::params::cc_cmonapi : ensure => present, require => Package[$clustercontrol::params::cc_controller] }
	  
	  service { $clustercontrol::params::apache_service :
	    ensure  => $service_status,
	    enable  => $enabled,
	    require => Package[$clustercontrol::params::cc_dependencies],
	    hasrestart  => true,
	    hasstatus   => true,
	    subscribe  => File[$clustercontrol::params::apache_conf_file,$clustercontrol::params::apache_ssl_conf_file]
	  }
	  
	  ssh_authorized_key { "$ssh_user" :
      ensure => present,
      key    => generate('/bin/bash', "$modulepath/files/s9s_helper.sh", '--read-key', "$modulepath"),
      name   => "$ssh_user@clustercontrol",
      user   => "$ssh_user",
      type   => 'ssh-rsa',
    }
	  
	  service { 'cmon' :
	    ensure  => $service_status,
	    enable  => $enabled,
	    require => Package[
	          $clustercontrol::params::cc_controller,
	          $clustercontrol::params::cc_ui,
	          $clustercontrol::params::cc_cmonapi
	        ],
	    subscribe    => File[$clustercontrol::params::cmon_conf],
	    hasrestart   => true,
	    hasstatus    => false
	  }
	  
	  file { [
	    "$clustercontrol::params::wwwroot/cmon/",
	    "$clustercontrol::params::wwwroot/cmon/upload",
	    "$clustercontrol::params::wwwroot/cmon/upload/schema",
	    "$clustercontrol::params::wwwroot/clustercontrol/",
	    "$clustercontrol::params::wwwroot/cmonapi/"
	  ] :
	    ensure  => directory,
	    recurse => true,
	    owner   => $clustercontrol::params::apache_user,
	    group   => $clustercontrol::params::apache_user,
	    require => [Package[$clustercontrol::params::cc_ui],File["$ssh_identity", "$ssh_identity_pub"]],
	    notify  => Service['cmon']
	  }
	  
	  file { "$ssh_identity" :
	    ensure => present,
	    owner  => $ssh_user,
	    group  => $ssh_user,
	    mode   => 600,
	    source => 'puppet:///modules/clustercontrol/id_rsa_s9s'
	  }
	  
	  file { "$ssh_identity_pub" :
	    ensure  => present,
	    owner   => $ssh_user,
	    group   => $ssh_user,
	    mode    => 644,
	    source  => 'puppet:///modules/clustercontrol/id_rsa_s9s.pub'
	  }
	  
	  file { "$clustercontrol::params::wwwroot/cmonapi/config/bootstrap.php" :
	    ensure  => present,
	    replace => no,
	    source  => "$clustercontrol::params::wwwroot/cmonapi/config/bootstrap.php.default",
	    require => Package["$clustercontrol::params::cc_cmonapi"],
	    notify  => Exec['configure-cmonapi-bootstrap']
	  }
	
	  file { "$clustercontrol::params::wwwroot/cmonapi/config/database.php" :
	    ensure  => present,
	    content  => template('clustercontrol/database.php.erb'),
	    require => Package["$clustercontrol::params::cc_cmonapi"]
	  }
	  
	  file { "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php" :
	    ensure  => present,
	    replace => no,
	    source  => "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php.default",
	    notify  => Exec['configure-cc-bootstrap']
	  }
	  
	  file { $clustercontrol::params::cert_file :
	    ensure  => present,
	    source  => "$clustercontrol::params::wwwroot/cmonapi/ssl/server.crt",
	    require => Package["$clustercontrol::params::cc_cmonapi"]
	  }
	  
	  file { $clustercontrol::params::key_file :
	    ensure  => present,
	    source  => "$clustercontrol::params::wwwroot/cmonapi/ssl/server.key",
	    require => Package["$clustercontrol::params::cc_cmonapi"]
	  }
	  
	  exec { "configure-cc-bootstrap" :
	    command => "sed -i 's|DBPASS|$mysql_cmon_password|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php && \
	    sed -i 's|DBPORT|$mysql_cmon_port|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php",
	    notify => Service[$clustercontrol::params::apache_service]
	  }
	
	  exec { "configure-cmonapi-bootstrap" :
	    command => "sed -i 's|GENERATED_CMON_TOKEN|$api_token|g' $clustercontrol::params::wwwroot/cmonapi/config/bootstrap.php && \
	    sed -i 's|clustercontrol.severalnines.com|$ip_address\/clustercontrol|g' $clustercontrol::params::wwwroot/cmonapi/config/bootstrap.php"
	  }
	  
	  exec { "allow-override-all" :
	    unless  => "grep 'AllowOverride All' $clustercontrol::params::apache_conf_file",
	    command => "sed -i 's|AllowOverride None|AllowOverride All|g' $clustercontrol::params::apache_conf_file"
	  }
    
	} else {
	  	  
	  ssh_authorized_key { '$ssh_user' :
	    ensure => present,
	    key    => generate('/bin/bash', "$modulepath/files/s9s_helper.sh", '--read-key', "$modulepath"),
	    name   => "$ssh_user@$clustercontrol_host",
	    user   => "$ssh_user",
	    type   => 'ssh-rsa',
	    notify => Exec['grant-cmon-controller','grant-cmon-localhost','grant-cmon-127.0.0.1']
	    }
	  
		exec { 'grant-cmon-controller' :
		  onlyif  => 'which mysql',
		  command => "mysql -u root -p\"$mysql_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"$clustercontrol_host\" IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		  }
		
		exec { "grant-cmon-localhost" :
		  onlyif  => 'which mysql',
		  command => "mysql -u root -p\"$mysql_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@localhost IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		  }
    
    exec { "grant-cmon-127.0.0.1" :
      onlyif => 'which mysql',
      command => "mysql -u root -p\"$mysql_root_password\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@127.0.0.1 IDENTIFIED BY \"$mysql_cmon_password\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
      }
	}
}