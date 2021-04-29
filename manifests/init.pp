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
  $ip_address               = $ipaddress,
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
  $mysql_basedir		    = '',
  $modulepath               = '/etc/puppetlabs/code/environments/production/modules/clustercontrol/',
  $datadir                  = '/var/lib/mysql',
  $use_repo                 = true,
  $disable_firewall			= true,		# flushes the iptables then disable iptables/firewalld/ufw
  $disable_os_sec_module	= true,		# disable by default for SELinux/AppArmor
  $controller_id		    = '',
  $is_online_install		= true,
  
  # path of your CC packages. Set this only when you are using offline installation i.e. $is_online_install == false
  $cc_packages_path				= {
  	'clustercontrol-controller' => '',
	'clustercontrol' => '',
	'clustercontrol-cloud' => '',
	'clustercontrol-clud' => '',
	'clustercontrol-ssh' => '',
	'clustercontrol-notifications' => '',
	'libs9s' => '',
	's9s-tools' => ''
  },
  $enabled                  = true
  
) {
	
	#fail( "controller_id is ${::controller_id}") 
	
	
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
		if ($sudo_password  != undef) { 
			$real_sudo_password = "echo $sudo_password | sudo -S" 
		} else { 
			$real_sudo_password = 'sudo' 
		}
	}
	
	if ($ssh_key == '') {
	    $ssh_identity     = "$user_home/.ssh/id_rsa_s9s"
	    $ssh_identity_pub = "$user_home/.ssh/id_rsa_s9s.pub"
	} else {
	    $ssh_identity     = "$user_home/.ssh/id_rsa"
	    $ssh_identity_pub = "$user_home/.ssh/id_rsa.pub"
	}

	$backup_dir       = "$user_home/backups"
	$staging_dir      = "$user_home/s9s_tmp"
	
	if (empty($controller_id)) {
		$l_controller_id	  = $::controller_id
	} else {
		$l_controller_id	  = $controller_id
	}
	
	
	$l_osfamily = downcase($osfamily);

	if empty($mysql_basedir) {
		Exec { path => ['/usr/bin','/bin']}
	} else {
		Exec { path => ['/usr/bin','/bin',"$mysql_basedir/bin"]}
	}
	

	if $is_controller {
		
		class { 'clustercontrol::params': 
			online_install => $is_online_install 
		}
		
		/* setup MySQL first needed as the CMONDB */
		service { $clustercontrol::params::mysql_service :
			ensure       => running,
			enable       => true,
			hasrestart   => true,
			hasstatus    => true,
			require      => [
			  Package[$clustercontrol::params::mysql_packages],
			  File[$datadir],
			  ],
			subscribe  => File[$clustercontrol::params::mysql_cnf],
			notify     => Exec['create-root-password']
		}


		
	    #if $::iptables == "true" {
	  #  }
		
		if ($disable_firewall) {
			exec { 'disable-firewall' :
				path        => ['/usr/sbin','/sbin'],
				command     => 'iptables -F'
			}
			
		    service { "iptables":
		    	enable  => false,
		        ensure  => stopped,
		    }	
		}		
		
		if ($l_osfamily == 'redhat') {
			## RHEL/CentOS
			
			if ($disable_os_sec_module) {
				file { '/etc/selinux/config':
					ensure  => present,
					content => template('clustercontrol/selinux-config.erb'),
				}
			
				exec { 'disable-os-security-module' :
					path        => ['/usr/sbin','/bin'],
					onlyif      => '/usr/sbin/getenforce | grep -i enforcing',
					command     => 'setenforce 0',
					require     => File['/etc/selinux/config']
				}
			}
			
			if ($disable_firewall) {
			    service { 'firewalld':
			        ensure     => stopped,
			        enable     => false
			    }
			}
			
		} elsif ($l_osfamily == 'debian') {
			## Debian/Ubuntu
			if ($disable_os_sec_module) {
				exec { 'disable-os-security-module' :
					path        => ['/usr/sbin', '/usr/bin'],
					onlyif      => 'which apparmor_status',
					command     => '/etc/init.d/apparmor stop; /etc/init.d/apparmor teardown; update-rc.d -f apparmor remove',
				}
			}
			
			if ($disable_firewall) {
			    service { 'ufw':
			        ensure     => stopped,
			        enable     => false
			    }
			}
		}

		package { $clustercontrol::params::mysql_packages :
			ensure  => installed
		}
		

		file { $datadir :
			ensure  => directory,
			owner   => mysql, group => mysql,
			require => Package[$clustercontrol::params::mysql_packages],
			notify  => Service[$clustercontrol::params::mysql_service]
		}

		file { $clustercontrol::params::mysql_cnf :
			ensure   => file,
			force => true,
			content  => template('clustercontrol/my.cnf.erb'),
			owner    => root, 
			group => root,
			mode     => '0644'
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
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -hlocalhost status",
			command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE USER cmon@localhost IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@localhost WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-127.0.0.1" :
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h127.0.0.1 status",
			command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE USER cmon@127.0.0.1 IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@127.0.0.1 WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-ip-address" :
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h\"$ip_address\" status",
			command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE USER cmon@\"$ip_address\" IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@\"$ip_address\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-fqdn" :
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h\"$fqdn\" status",
			command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'CREATE USER cmon@\"$fqdn\" IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@\"$fqdn\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}
		
		/* Populate the CMONDB with data */
		/* The statements shall be run only when cc packages are setup properly */
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
			notify => Exec['configure-cmon-db'],
			require => Package[$clustercontrol::params::cc_controller]
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
			content => template('clustercontrol/configure_cmon_db.sql.erb'),
			require => Package[$clustercontrol::params::cc_controller]
		}


		exec { "import-dcps-db" :
			onlyif  => "test -f $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
			command => "mysql -f -u root -p\"$mysql_cmon_root_password\" dcps < $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
			notify => Exec['create-dcps-api'],
			require => Package[$clustercontrol::params::cc_controller]
		}

   	    exec { "create-dcps-api" :
			onlyif => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'SHOW SCHEMAS LIKE \"dcps\";' 2>/dev/null",
            command => "mysql -u root -p\"$mysql_cmon_root_password\" -e 'REPLACE INTO dcps.apis(id, company_id, user_id, url, token) VALUES (1, 1, 1, \"http://127.0.0.1/cmonapi\", \"$api_token\");'",
			require => Package[$clustercontrol::params::cc_controller]
        }   

		
		/* Required dependencies must be present */

		package { $clustercontrol::params::cc_dependencies :
			ensure  => installed,
			notify  => [Exec['allow-override-all'], File[
				$clustercontrol::params::cert_file, 
				$clustercontrol::params::key_file, 
				$clustercontrol::params::apache_s9s_ssl_conf_file,
				$clustercontrol::params::apache_s9s_conf_file
			]]
		}
		
		if ($is_online_install) {
		
			/* setup the Apache server required for frontend HTTP/HTTPS */
			package { $clustercontrol::params::cc_controller :
				ensure => installed,
				require => [
						$clustercontrol::params::severalnines_repo, 
						Package[$clustercontrol::params::cc_dependencies]
				]
			}
		
			package { $clustercontrol::params::cc_ui : 
				ensure  => installed, 
				require => Package[[$clustercontrol::params::cc_controller]],
				notify  => Exec['create-dcps-db']
			}
		} else {

			if ($l_osfamily == 'redhat') {
				$l_provider = "rpm"
				$l_provider_pkg = "rpm"
			} elsif ($l_osfamily == 'debian') {
				$l_provider = "apt"
				$l_provider_pkg = "dpkg"
			} else {
				fail("Offline installation for this Puppet Module ClusterControl only supports RHEL/CentOS >= 7, Ubuntu >= 16, Debian >= 9 versions. Obsolete or versions that passed EOL is no longer supported. Please contact Severalnines (support@severalnines.com) if you see unusual behavior.")
			}
			
			
			package { 
			 	$clustercontrol::params::cc_cloud :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_cloud],
				require => Package[$clustercontrol::params::cc_dependencies],
			}

			package { 
			 	$clustercontrol::params::cc_clud :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_clud],
				require => Package[$clustercontrol::params::cc_cloud],
			}

			package { 
			 	$clustercontrol::params::cc_ssh :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_ssh],
				require => Package[$clustercontrol::params::cc_clud],
			}

			package { 
			 	$clustercontrol::params::cc_notif :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_notif],
				require => Package[$clustercontrol::params::cc_ssh],
			}

			if ($l_osfamily == 'redhat') {
				package { 
				 	$clustercontrol::params::s9stools :
					ensure => "installed",
					provider => $l_provider,
					source => $cc_packages_path[$clustercontrol::params::s9stools],
					require => Package[$clustercontrol::params::cc_notif],
				}
			} elsif ($l_osfamily == 'debian') {
				package { 
				 	$clustercontrol::params::libs9s :
					ensure => "installed",
					provider => $l_provider_pkg, # for some reasons, using apt doesn't work. Better use dpkg
					source => $cc_packages_path[$clustercontrol::params::libs9s],
					require => Package[$clustercontrol::params::cc_notif],
				}

				package { 
				 	$clustercontrol::params::s9stools :
					ensure => "installed",
					provider => $l_provider,
					source => $cc_packages_path[$clustercontrol::params::s9stools],
					require => Package[$clustercontrol::params::libs9s],
				}
			}

			package { 
			 	$clustercontrol::params::cc_ui :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_ui],
				require => Package[$clustercontrol::params::s9stools],
			}

			package { 
			 	$clustercontrol::params::cc_controller:
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_controller],
				require => Package[$clustercontrol::params::cc_ui]
			}
			
		}

		file { $clustercontrol::params::cert_file :
			ensure  => present,
			source  => "$clustercontrol::params::wwwroot/clustercontrol/ssl/server.crt",
			require => Package["$clustercontrol::params::cc_ui"]
		}

		file { $clustercontrol::params::key_file :
			ensure  => present,
			source  => "$clustercontrol::params::wwwroot/clustercontrol/ssl/server.key",
			require => Package["$clustercontrol::params::cc_ui"]
		}

		
		$wwwroot = $clustercontrol::params::wwwroot
		$apache_httpd_extra_options = $clustercontrol::params::apache_httpd_extra_options
		$cert_file = $clustercontrol::params::cert_file
		$key_file = $clustercontrol::params::key_file
		
		if $l_osfamily == 'redhat' {
			## RedHat/CentOS
			file { $clustercontrol::params::apache_s9s_conf_file :
				ensure  => present,
				mode    => '0644',
				owner   => root, group => root,
				content => template('clustercontrol/s9s.conf.erb'),
				require => Package[$clustercontrol::params::cc_dependencies],
				notify  => Service[$clustercontrol::params::apache_service]
			}

			file { $clustercontrol::params::apache_s9s_ssl_conf_file :
				ensure  => present,
				owner   => root, group => root,
				content => template('clustercontrol/s9s-ssl.conf.erb'),
				require => Package[$clustercontrol::params::cc_dependencies],
				notify  => Service[$clustercontrol::params::apache_service]
			}

	        # enable sameorigin header
			file { $clustercontrol::params::apache_security_conf_file :
				ensure  => present,
				owner   => root, group => root,
				content => template('clustercontrol/s9s-security.conf.erb'),
				require => Exec["enable-ssl-servername-localhost"]
			}
		
			## Add lines Listen and ServerName directive to httpd.conf to enable SSL/TLS
			exec { "enable-ssl-port" :
				unless => "grep -q 'Listen 443' $clustercontrol::params::apache_conf_file",
				command => "sed -i '1s|^|Listen 443\\n|' $clustercontrol::params::apache_conf_file",
				require => File[$clustercontrol::params::apache_s9s_conf_file]
			}
		
			exec { "enable-ssl-servername-localhost" :
				unless => "grep -q 'ServerName 127.0.0.1' $clustercontrol::params::apache_conf_file",
				command => "sed -i '1s|^|ServerName 127.0.0.1\\n|' $clustercontrol::params::apache_conf_file",
				require => File[$clustercontrol::params::apache_s9s_conf_file]
			}
		
		} elsif $l_osfamily == 'debian' {
			## Debian/Ubuntu
			file { "$clustercontrol::params::apache_s9s_ssl_conf_file" :
				ensure  => present,
				content => template('clustercontrol/s9s-ssl.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui],
				notify   => File[$clustercontrol::params::apache_s9s_ssl_target_file]
			}

			file { "$clustercontrol::params::apache_s9s_ssl_target_file" :
				ensure => 'link',
				target => "$clustercontrol::params::apache_s9s_ssl_conf_file",
				subscribe => File["$clustercontrol::params::apache_s9s_ssl_conf_file"]
			}

			file { "$clustercontrol::params::apache_s9s_conf_file" :
				ensure  => present,
				content => template('clustercontrol/s9s.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui],
				notify   => File[$clustercontrol::params::apache_s9s_target_file]
			}

			file { "$clustercontrol::params::apache_s9s_target_file" :
				ensure => 'link',
				target => "$clustercontrol::params::apache_s9s_conf_file",
				subscribe => File["$clustercontrol::params::apache_s9s_conf_file"]
			}

	        ## Enable sameorigin header
			# enable module header file first (applicable to Debian/Ubuntu only)
			file { "$clustercontrol::params::apache_mods_header_target_file" :
				ensure => 'link',
				target => "$clustercontrol::params::apache_mods_header_file",
				require => Package[$clustercontrol::params::cc_dependencies],
			}
			
			exec { "enable-securityconf-sameorigin" :
				unless => "grep -q '^Header set X-Frame-Options: \"sameorigin\"' $clustercontrol::params::apache_security_conf_file",
				command => "sed -i 's|\\#Header set X-Frame-Options: \"sameorigin\"|Header set X-Frame-Options: \"sameorigin\"|' $clustercontrol::params::apache_security_conf_file",
				subscribe => File["$clustercontrol::params::apache_mods_header_target_file"]
			}
			
			exec { 'enable-apache-modules': 
				path  => ['/usr/sbin','/sbin', '/usr/bin'],
				command => "a2enmod ssl && a2enmod rewrite",
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
				/* ,
				subscribe => Exec[["enable-ssl-port", "enable-ssl-servername-localhost"]]*/
			}
		}

		exec { "allow-override-all" :
			unless  => "grep 'AllowOverride All' $clustercontrol::params::apache_s9s_conf_file",
			command => "sed -i 's|AllowOverride None|AllowOverride All|g' $clustercontrol::params::apache_s9s_conf_file",
			require => File[$clustercontrol::params::apache_s9s_conf_file]
		}
		
		/* Now configure/setup the ClusterControl - installing packages, setting up required configurations, etc. */
		service { $clustercontrol::params::apache_service :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[$clustercontrol::params::cc_dependencies],
			hasrestart  => true,
			hasstatus   => true,
			subscribe  => File[$clustercontrol::params::apache_s9s_conf_file,
				 $clustercontrol::params::apache_s9s_ssl_conf_file
			]
		}

		/* Section to setup ssh user */
		# Allow or authorized a key based on the given public key from files/id_rsa_s9s.pub. See files/s9s_helper.sh
		# ssh_authorized_key { "$ssh_user" :
		# 	ensure => present,
		# 	key    => generate('/bin/bash', "$modulepath/files/s9s_helper.sh", '--read-key', "$modulepath"),
		# 	name   => "$ssh_user@clustercontrol",
		# 	user   => "$ssh_user",
		# 	type   => 'ssh-rsa',
		# }

		# create the ssh user's key and pub file based on the given files/id_rsa_s9s* files
		file { "$ssh_identity" :
			ensure => present,
			owner  => $ssh_user,
			group  => $ssh_user,
			mode   => '0600',
			source => 'puppet:///modules/clustercontrol/id_rsa_s9s'
		}

		file { "$ssh_identity_pub" :
			ensure  => present,
			owner   => $ssh_user,
			group   => $ssh_user,
			mode    => '0644',
			source  => 'puppet:///modules/clustercontrol/id_rsa_s9s.pub'
		}
		
		file { $clustercontrol::params::cmon_conf :
			content => template('clustercontrol/cmon.cnf.erb'),
			owner   => root, group => root,
			mode    => '0600',
			require => Package[$clustercontrol::params::cc_controller],
			notify  => [Exec['create-cmon-db'], Service['cmon']]
		}

		/* Manage all CMON related packages, events, etc. */
		service { 'cmon' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[
				$clustercontrol::params::cc_controller,
				$clustercontrol::params::cc_ui,
				$clustercontrol::params::cc_cloud,
				$clustercontrol::params::cc_clud,
				$clustercontrol::params::cc_notif,
				$clustercontrol::params::cc_ssh
			],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}

		file { [
				"$clustercontrol::params::wwwroot/cmon/",
				"$clustercontrol::params::wwwroot/cmon/upload",
				"$clustercontrol::params::wwwroot/cmon/upload/schema"
			] :
			ensure  => directory,
			recurse => true,
			owner   => $clustercontrol::params::apache_user,
			group   => $clustercontrol::params::apache_user,
			require => [Package[$clustercontrol::params::cc_ui],File["$ssh_identity", "$ssh_identity_pub"]],
			notify  => Service['cmon']
		}


		exec { "configure-cc-bootstrap" :
			command => "sed -i 's|DBPASS|$mysql_cmon_password|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php && \
			sed -i 's|DBPORT|$mysql_cmon_port|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php",
			notify => Service[$clustercontrol::params::apache_service]
		}

		
		exec { "configure-cmonapi-bootstrap" :
			command => "sed -i 's|RPCTOKEN|$api_token|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php",
			notify => Service[$clustercontrol::params::apache_service]
		}

		file { "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php" :
			ensure  => present,
			replace => no,
			source  => "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php.default",
			require => Package["$clustercontrol::params::cc_ui"],
			notify  => Exec[['configure-cmonapi-bootstrap','configure-cc-bootstrap']],
		}

		  
		service { 'cmon-cloud' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[
				$clustercontrol::params::cc_controller,
				$clustercontrol::params::cc_ui,
				$clustercontrol::params::cc_cloud,
				$clustercontrol::params::cc_clud,
				$clustercontrol::params::cc_notif,
				$clustercontrol::params::cc_ssh
			],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}


		service { 'cmon-events' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[
				$clustercontrol::params::cc_controller,
				$clustercontrol::params::cc_ui,
				$clustercontrol::params::cc_cloud,
				$clustercontrol::params::cc_clud,
				$clustercontrol::params::cc_notif,
				$clustercontrol::params::cc_ssh
			],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}

		service { 'cmon-ssh' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[
				$clustercontrol::params::cc_controller,
				$clustercontrol::params::cc_ui,
				$clustercontrol::params::cc_cloud,
				$clustercontrol::params::cc_clud,
				$clustercontrol::params::cc_notif,
				$clustercontrol::params::cc_ssh
			],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}
	


/*
    export S9S_USER_CONFIG=$HOME/.s9s/ccrpc.conf
    s9s user --create --generate-key --group=admins --controller=https://localhost:9501 ccrpc
    [[ $? -ne 0 ]] && log_msg "Unable to create the 'ccrpc' user! Please check your s9s installation." && exit 1
    s9s user --whoami --cmon-user=ccrpc --private-key-file=$HOME/.s9s/ccrpc.key &>/dev/null
    [[ $? -ne 0 ]] && log_msg "Unable to verify s9s ccrpc private key" && exit 1

    s9s user --set --first-name=RPC --last-name=API &>/dev/null
    s9s user --change-password --new-password=${rpc_key} ccrpc &>/dev/null
    [[ $? -ne 0 ]] && log_msg "Unable to change s9s ccrpc password" && exit 1

    unset S9S_USER_CONFIG

*/
		$username = "root"
		$home = "home_$username"
		$home_path = inline_template("<%= scope.lookupvar('::$home') %>")
		$user_path = "${home_path}/.s9s/ccrpc.conf"
		
		
		notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>s9s tool 
			home_path: ${home_path}, \
			user_path: ${user_path}, \
			home: ${home}": 
		}
		
		

		file { "${home_path}/.s9s/":
			ensure  => directory,
			owner   => "root",
			group   => "root",
			mode    => "0700",
			require => Service['cmon']
		}

		/*
		exec { "declare_ccrpc_config_var":
			environment => ["S9S_USER_CONFIG=${user_path}"],
			user => "root",
			require =>  File["$home_path/.s9s/"]
		}*/

		exec { "create_ccrpc_user":
			command => "sudo S9S_USER_CONFIG=${user_path} s9s user --create --new-password=$api_token --generate-key --private-key-file=~/.s9s/ccrpc.key --group=admins --controller=https://localhost:9501 ccrpc",
			require =>  [Service['cmon'],File["${home_path}/.s9s/"]]
		}
		/*
		exec { "create_ccrpc_set_private_key":
			command => "s9s user --whoami --cmon-user=ccrpc --private-key-file=~/.s9s/ccrpc.key",
			user => "root",
			provider => "shell",
			require =>  File["${home_path}/.s9s/"]
		} */


		exec { "create_ccrpc_set_firstname":
			user => "root",
			command => "sudo S9S_USER_CONFIG=${user_path} s9s user --set --first-name=RPC --last-name=API",
			require =>  [File["${home_path}/.s9s/"],Service['cmon']]
		}

	
/*			
		exec { "delete-s9sconf":
			command => "rm -rf /etc/s9s* /root/.s9s/*",
			#require => Exec["apt-update-severalnines"],
			require => Service['cmon-ssh']
		}



		exec { "create-newadmin":
			'user' => 'root',
			command => "s9s user --create --generate-key --group=admins --controller=\"https://localhost:9501\" newadmin",
			#require => Exec["apt-update-severalnines"],
			#require => Service['cmon-ssh']
			require => Exec['delete-s9sconf']
		}

	
		exec { "create-crpcuser":
			command => "s9s user --create --new-password=$api_token --group=admins --controller=\"https://localhost:9501\" ccrpc",
			#require => Exec["apt-update-severalnines"],
			require => Exec['create-newadmin']
		}

		exec { "execute_crpcuser":
			command => "/bin/bash /root/ccrpcuser.sh",
			#require => Exec["apt-update-severalnines"],
			require => Service['cmon','cmon-ssh']
		}
*/
		
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
