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
  $cc_hostname              = $cc_hostname,
  $api_token                = '',
  $ssh_user                 = 'root',
  $ssh_user_group            = 'root',
  $ssh_port                 = '22',
  $ssh_key_type             = 'ssh-rsa',
  $ssh_key                  = '',
  $ssh_opts                 = undef,
  $sudo_password            = undef,
  $mysql_server_addresses   = '',
  $mysql_root_password      = 'R00tP@55',
  $mysql_cmon_password      = 'userP@55',
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
		's9s-tools' => '',
		'clustercontrol2' => ''
  },
  $enabled                  = true,

  ## your desired admin email for your clustercontrol setup. Email field will use this as auto-fill value during registration form
  $ccsetup_email = "admin@clustercontrol.com",
	
  ## only_cc_v2 {true = if only ccv2, false = if ccv1 and ccv2 combination (the installation setup in 1.9.6 below when ccv2 had been suppported)}
  $only_cc_v2 = true
  
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
		Exec { path => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin']}
	} else {
		Exec { path => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin', "$mysql_basedir/bin"]}
	}
	
	if ($only_cc_v2) {
		$cc_frontend_ssl_port = 443
	} else {
		$cc_frontend_ssl_port = 9443
	}

	if $is_controller {
		
		class { 'clustercontrol::params': 
			online_install => $is_online_install,
			only_cc_v2 => $only_cc_v2
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
			exec { 'check-iptables-presence' :
				path        => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command     => 'iptables -L',
				onlyif	    => 'which iptables'
			}
			
			exec { 'disable-iptables-firewall' :
				path        => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command     => 'iptables -F',
				onlyif	    => 'which iptables',
				require     => Exec["check-iptables-presence"]
			}
			
		    service { "iptables":
		    	enable  => false,
		        ensure  => stopped,
				require => Exec['check-iptables-presence']
		    }	
		}		
		
		if ($l_osfamily == 'redhat' or $l_osfamily == 'suse') {
			## RHEL/CentOS or SLES/OpenSUSE 15 >=
			
			
			if ($disable_os_sec_module) {
				#exec { "check-selinux-config":
				#  command => "ls -alth /etc/selinux/config",
				#  path    =>  ["/usr/bin","/usr/sbin", "/bin"],
				#  onlyif  => 'test -f /etc/selinux/config'
				#}
				
				## Only create the file if the /etc/selinux/config exists
			    file {"/etc/selinux/config":
					ensure  => file,
					content => template('clustercontrol/selinux-config.erb'),
					owner  => 'root',
					group  => 'root',
					mode   => '0644',
					validate_cmd => 'test -f /etc/selinux/config'
					#subscribe => Exec["check-selinux-config"],
					#refreshonly => true
			    }
			
				exec { 'disable-os-security-module' :
					path        => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
					onlyif      => 'which getenforce && /usr/sbin/getenforce | grep -i enforcing',
					command     => 'setenforce 0',
					require =>  File["/etc/selinux/config"]
				}
			}
			
			if ($disable_firewall) {
				exec { 'check-firewalld-presence' :
					path        => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
					onlyif      => 'which firewall-cmd',
					command     => 'firewall-cmd --stat',
				}
				
			    service { 'firewalld':
			        ensure     => stopped,
			        enable     => false,
					require    => Exec["check-firewalld-presence"]
			    }
			}
		} elsif ($l_osfamily == 'debian') {
			## Debian/Ubuntu
			if ($disable_os_sec_module) {
				exec { 'disable-os-security-module' :
					path        => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
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
		
		if ($l_osfamily == "suse") {
			
			package { $clustercontrol::params::mysql_packages :
				ensure  => installed,
				require => [
					Zypprepo["s9s-repo"],
					Zypprepo["s9s-tools-repo"],
					Exec["refresh-zypper-auto-import-refresh"]
				]
			}
			
			exec { 'refresh-zypper-auto-import-refresh' :
				path        =>['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command     => 'zypper -n --gpg-auto-import-keys refresh 2>/dev/null',
			}
		} else {
			package { $clustercontrol::params::mysql_packages :
				ensure  => installed
			}
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
			mode     => '0644',
			require => Package[$clustercontrol::params::mysql_packages],
			notify  => Service[$clustercontrol::params::mysql_service]
		}

		exec { 'create-root-password' :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			onlyif  => "mysqladmin -u root status",
			command => "mysqladmin -u root password \"${mysql_root_password}\""
		}

		exec { "grant-cmon-localhost" :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -hlocalhost status && mysql -u root -p\"${mysql_root_password}\" -e 'SHOW GRANTS FOR cmon@localhost'",
			command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE USER cmon@localhost IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@localhost WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-127.0.0.1" :
			path   => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h127.0.0.1 status && mysql -u root -p\"${mysql_root_password}\" -e 'SHOW GRANTS FOR cmon@\"127.0.0.1\"'",
			command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE USER cmon@\"127.0.0.1\" IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@\"127.0.0.1\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-ip-address" :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h\"${cc_hostname}\" status && mysql -u root -p\"${mysql_root_password}\" -e 'SHOW GRANTS FOR cmon@\"${cc_hostname}\"'",
			command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE USER cmon@\"${cc_hostname}\" IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@\"${cc_hostname}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}

		exec { "grant-cmon-fqdn" :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			unless  => "mysqladmin -u cmon -p\"$mysql_cmon_password\" -h\"$fqdn\" status && mysql -u root -p\"${mysql_root_password}\" -e 'SHOW GRANTS FOR cmon@\"${fqdn}\"'",
			command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE USER cmon@\"$fqdn\" IDENTIFIED BY  \"$mysql_cmon_password\"; GRANT ALL PRIVILEGES ON *.* TO cmon@\"$fqdn\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
		}
		
		/* Populate the CMONDB with data */
		/* The statements shall be run only when cc packages are setup properly */
		exec { "create-cmon-db" :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE SCHEMA IF NOT EXISTS cmon;'",
			notify  => Exec['import-cmon-db']
		}

		if (! $only_cc_v2) {
			## dcps schema is only used by CC v1
			exec { "create-dcps-db" :
				path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "mysql -u root -p\"${mysql_root_password}\" -e 'CREATE SCHEMA IF NOT EXISTS dcps;'",
				notify  => Exec['import-dcps-db']
			}
		}

		exec { "import-cmon-db" :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			onlyif  => [
			  "test -f $clustercontrol::params::cmon_sql_path/cmon_db.sql",
			  "test -f $clustercontrol::params::cmon_sql_path/cmon_data.sql"
			],
			command => "mysql -f -u root -p\"${mysql_root_password}\" cmon < $clustercontrol::params::cmon_sql_path/cmon_db.sql && \
			mysql -f -u root -p\"${mysql_root_password}\" cmon < $clustercontrol::params::cmon_sql_path/cmon_data.sql",
			notify => Exec['configure-cmon-db'],
			require => Package[$clustercontrol::params::cc_controller]
		}

		exec { 'configure-cmon-db' :
			path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			onlyif  => [
			  "test -f $clustercontrol::params::cmon_sql_path/cmon_db.sql",
			  "test -f $clustercontrol::params::cmon_sql_path/cmon_data.sql"
			],
			command => "mysql -f -u root -p\"${mysql_root_password}\" cmon < /tmp/configure_cmon_db.sql",
			require => File["/tmp/configure_cmon_db.sql"]
		}

		file { '/tmp/configure_cmon_db.sql' :
			ensure  => present,
			content => template('clustercontrol/configure_cmon_db.sql.erb'),
			require => Package[$clustercontrol::params::cc_controller]
		}

		if ($only_cc_v2 == false) {
			## applies only when CC v1 is present.
			exec { "import-dcps-db" :
				path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				onlyif  => "test -f $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
				command => "mysql -f -u root -p\"${mysql_root_password}\" dcps < $clustercontrol::params::wwwroot/clustercontrol/sql/dc-schema.sql",
				notify => Exec['create-dcps-api'],
				require => Package[$clustercontrol::params::cc_controller]
			}

			exec { "create-dcps-api" :
				path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				onlyif => "mysql -u root -p\"${mysql_root_password}\" -e 'SHOW SCHEMAS LIKE \"dcps\";' 2>/dev/null",
				command => "mysql -u root -p\"${mysql_root_password}\" -e 'REPLACE INTO dcps.apis(id, company_id, user_id, url, token) VALUES (1, 1, 1, \"http://127.0.0.1/cmonapi\", \"$api_token\");'",
				require => Package[$clustercontrol::params::cc_controller]
			}   
		}

		
		if ($l_osfamily == 'suse') {
			## Importing gpg keys for CC repo and s9s-tools for SUSE-variant only
			exec { "import-gpg-keys-for-cc-repo" :
				path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "rpm --import \"http://${clustercontrol::params::repo_host}/severalnines-repos.asc\"",
				require => [Zypprepo["s9s-repo"],Zypprepo["s9s-tools-repo"]]
			}   

			exec { "import-gpg-keys-for-s9s_tools-repo" :
				path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "rpm --import \"http://${clustercontrol::params::repo_host}/s9s-tools/${clustercontrol::params::s9s_tools_repo_osname}/repodata/repomd.xml.key\"",
				require => [Zypprepo["s9s-repo"],Zypprepo["s9s-tools-repo"]]
			}   
		}

		## install cc dependencies first
		# $clustercontrol::params::cc_dependencies.each |String $pkg| {
		# 	package { $pkg :
		# 		ensure  => installed
		# 	}
		# }

		package { $clustercontrol::params::cc_dependencies :
			ensure  => installed
		}
	
		if ($is_online_install) {
		
			if ($only_cc_v2 == false){
				package { $clustercontrol::params::cc_ui : 
					ensure  => installed, 
					require => Package[[$clustercontrol::params::cc_controller]],
					notify  => Exec['create-dcps-db']
				}
			}

			package { $clustercontrol::params::cc_ui2 : 
				ensure  => installed, 
				require => Package[[$clustercontrol::params::cc_controller]]
			}

		}
		
		class { 'clustercontrol::create_cert': 
			cert_file => $clustercontrol::params::cert_file,
			key_file => $clustercontrol::params::key_file
		}

		if ($is_online_install) {
		
			/* setup the Apache server required for frontend HTTP/HTTPS */
			if ($l_osfamily == "suse") {
				
				package { $clustercontrol::params::cc_controller :
					ensure => installed,
					require => [
						Zypprepo["s9s-repo"],
						Zypprepo["s9s-tools-repo"],
						Package[$clustercontrol::params::cc_dependencies]
					]
				}
				
			} else {
				package { $clustercontrol::params::cc_controller :
					ensure => installed,
					require => [
							$clustercontrol::params::severalnines_repo, 
							Package[$clustercontrol::params::cc_dependencies]
					]
				}
			}

		} else {
			if ($l_osfamily == 'redhat' or $l_osfamily == 'suse') {
				## RHEL type distros/SUSE shares same file package manger
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
			} elsif ($l_osfamily == 'suse') {
				package { 
				 	$clustercontrol::params::s9stools :
					ensure => "installed",
					provider => $l_provider,
					source => $cc_packages_path[$clustercontrol::params::s9stools],
					require => Package[$clustercontrol::params::cc_notif],
				}
			} 

			if ($only_cc_v2 == false) {				
				package { 
				 	$clustercontrol::params::cc_ui :
					ensure => "installed",
					provider => $l_provider,
					source => $cc_packages_path[$clustercontrol::params::cc_ui],
					require => Package[$clustercontrol::params::s9stools],
				}
			}

			package { 
			 	$clustercontrol::params::cc_ui2 :
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_ui2],
				require => Package[$clustercontrol::params::s9stools],
			}

			package { 
			 	$clustercontrol::params::cc_controller:
				ensure => "installed",
				provider => $l_provider,
				source => $cc_packages_path[$clustercontrol::params::cc_controller],
				require => Package[$clustercontrol::params::cc_ui2]
			}
			
		}
		
		$wwwroot = $clustercontrol::params::wwwroot
		$apache_httpd_extra_options = $clustercontrol::params::apache_httpd_extra_options
		$cert_file = $clustercontrol::params::cert_file
		$key_file = $clustercontrol::params::key_file
		
		if $l_osfamily == 'redhat' {
			## RedHat/CentOS
			if ($only_cc_v2 == false) {
				file { $clustercontrol::params::apache_s9s_conf_file :
					ensure  => present,
					mode    => '0644',
					owner   => root, 
					group => root,
					content => template('clustercontrol/s9s.conf.erb'),
					require => Package[$clustercontrol::params::cc_dependencies],
					# notify  => Service[$clustercontrol::params::apache_service]
				}

				file { $clustercontrol::params::apache_s9s_ssl_conf_file :
					ensure  => present,
					mode    => '0644',
					owner   => root, 
					group => root,
					content => template('clustercontrol/s9s-ssl.conf.erb'),
					require => Package[$clustercontrol::params::cc_dependencies],
					# notify  => Service[$clustercontrol::params::apache_service]
				}
			}
			
			## For CCv2
			file { "$clustercontrol::params::apache_s9s_cc_frontend_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-frontend.conf.erb'),
				mode    => '0644',
				owner   => root, 
				group => root,
				require => Package[$clustercontrol::params::cc_ui2],
				notify   => File[$clustercontrol::params::apache_s9s_cc_proxy_conf_file]
			}

			file { "$clustercontrol::params::apache_s9s_cc_proxy_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-proxy.conf.erb'),
				mode    => '0644',
				owner   => root, 
				group => root,
				require => Package[$clustercontrol::params::cc_ui2]
			}
			

	    # enable sameorigin header
			if (! $only_cc_v2) {
				$require_s9s_sec_conf_file = Exec["enable-ssl-servername-localhost"]
			} else {
				$require_s9s_sec_conf_file = []
			}
			
			file { $clustercontrol::params::apache_security_conf_file :
				ensure  => present,
				owner   => root, group => root,
				content => template('clustercontrol/s9s-security.conf.erb'),
				require => $require_s9s_sec_conf_file
			}
		
			## Add lines Listen and ServerName directive to httpd.conf to enable SSL/TLS
			if (! $only_cc_v2) {
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
			}
		
		} elsif $l_osfamily == 'debian' {
			## Debian/Ubuntu
			if ($only_cc_v2 == false) {
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
			}
			
			## For CCv2
			file { "$clustercontrol::params::apache_s9s_cc_frontend_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-frontend.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui2],
				notify   => File[$clustercontrol::params::apache_s9s_cc_frontend_target_file]
			}

			file { "$clustercontrol::params::apache_s9s_cc_frontend_target_file" :
				ensure => 'link',
				target => "$clustercontrol::params::apache_s9s_cc_frontend_conf_file",
				subscribe => File["$clustercontrol::params::apache_s9s_cc_frontend_conf_file"]
			}

			file { "$clustercontrol::params::apache_s9s_cc_proxy_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-proxy.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui2],
				notify   => File[$clustercontrol::params::apache_s9s_cc_proxy_target_file]
			}

			file { "$clustercontrol::params::apache_s9s_cc_proxy_target_file" :
				ensure => 'link',
				target => "$clustercontrol::params::apache_s9s_cc_proxy_conf_file",
				subscribe => File["$clustercontrol::params::apache_s9s_cc_proxy_conf_file"]
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
			
			## Set servername for the frontend CC v2 apache config file
			exec { "set-servername-ccv2-frontend" :
				unless  => "grep 'cc2.severalnines.local' $clustercontrol::params::apache_s9s_cc_frontend_conf_file",
				command => "sed -i \"s|https://cc2.severalnines.local:9443.*|https://${cc_hostname}\/|g\" $clustercontrol::params::apache_s9s_cc_frontend_conf_file",
				require => [
					Package[$clustercontrol::params::cc_dependencies],
					Package[$clustercontrol::params::cc_ui2]
				]
			}
			
			exec { 'enable-apache-modules': 
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "a2enmod ssl rewrite proxy proxy_http proxy_wstunnel",
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
				/* ,
				subscribe => Exec[["enable-ssl-port", "enable-ssl-servername-localhost"]]*/
			}
		} elsif $l_osfamily == 'suse' {
			## SUSE (SLES/OpenSUSE 15>=)
			if ($only_cc_v2 == false) {
				## ccv1 and ccv2
				file { "$clustercontrol::params::apache_s9s_ssl_conf_file" :
					ensure  => present,
					content => template('clustercontrol/s9s-ssl.conf.erb'),
					mode    => '0644',
					owner   => root, group => root,
					require => Package[$clustercontrol::params::cc_ui],
					notify   => File[$clustercontrol::params::apache_s9s_conf_file]
				}

				file { "$clustercontrol::params::apache_s9s_conf_file" :
					ensure  => present,
					content => template('clustercontrol/s9s.conf.erb'),
					mode    => '0644',
					owner   => root, group => root,
					require => Package[$clustercontrol::params::cc_ui],
					notify   => File[$clustercontrol::params::apache_s9s_cc_frontend_conf_file]
				}
			}
			
			## For CCv2
			file { "$clustercontrol::params::apache_s9s_cc_frontend_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-frontend.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui2],
				notify   => File[$clustercontrol::params::apache_s9s_cc_proxy_conf_file]
			}

			file { "$clustercontrol::params::apache_s9s_cc_proxy_conf_file" :
				ensure  => present,
				content => template('clustercontrol/cc-proxy.conf.erb'),
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$clustercontrol::params::cc_ui2]
			}
			
			exec { 'enable-apache-modules': 
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "a2enmod ssl && a2enmod rewrite && a2enmod headers && a2enmod proxy && a2enmod proxy_http && a2enmod proxy_wstunnel",
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
				/* ,
				subscribe => Exec[["enable-ssl-port", "enable-ssl-servername-localhost"]]*/
			}
			
			file_line { 'enable-apache-php':
			  	path => '/etc/apache2/mod_mime-defaults.conf',
			  	line => 'AddType application/x-httpd-php .php',
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
			}

			
			file_line { 'enable-apache-proxy_module':
			  	path => '/etc/apache2/loadmodule.conf',
			  	line => 'LoadModule proxy_module modules/mod_proxy.so',
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
			}

			
			file_line { 'enable-apache-proxy_http_module':
			  	path => '/etc/apache2/loadmodule.conf',
			  	line => 'LoadModule proxy_http_module modules/mod_proxy_http.so',
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
			}

			
			file_line { 'enable-apache-proxy_wstunnel_module':
			  	path => '/etc/apache2/loadmodule.conf',
			  	line => 'LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so',
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
			}

			
			file_line { 'enable-SSL-flag-for-apache2':
			  	path => '/etc/sysconfig/apache2',
			  	line => 'APACHE_SERVER_FLAGS="SSL"',
				loglevel => info,
				require => Package[$clustercontrol::params::cc_dependencies] 
			}
			
			## Set servername for the frontend CC v2 apache config file
			exec { "set-servername-ccv2-frontend" :
				unless  => "grep 'cc2.severalnines.local' $clustercontrol::params::apache_s9s_cc_frontend_conf_file",
				command => "sed -i \"s|https://cc2.severalnines.local:9443.*|https://${cc_hostname}\/|g\" $clustercontrol::params::apache_s9s_cc_frontend_conf_file",
				require => Package[$clustercontrol::params::cc_ui2] 
			}
		}

		if (! $only_cc_v2) {
			exec { "allow-override-all" :
				unless  => "grep 'AllowOverride All' $clustercontrol::params::apache_s9s_conf_file",
				command => "sed -i 's|AllowOverride None|AllowOverride All|g' $clustercontrol::params::apache_s9s_conf_file",
				require => File[$clustercontrol::params::apache_s9s_conf_file]
			}
		}
		

		exec { "set-cmon-api-url" :
			unless  => "grep 'CMON_API_URL' $clustercontrol::params::cc_v2_config_ui_file",
			command => "sed -i \"s|^[ \t]*CMON_API_URL.*|  CMON_API_URL: 'https://${cc_hostname}}:19501/v2',|g\" $clustercontrol::params::cc_v2_config_ui_file",
			require => Package[$clustercontrol::params::cc_ui2]
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
			group  => $ssh_user_group,
			mode   => '0600',
			source => 'puppet:///modules/clustercontrol/id_rsa_s9s'
		}

		file { "$ssh_identity_pub" :
			ensure  => present,
			owner   => $ssh_user,
			group   => $ssh_user_group,
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
		if ($only_cc_v2) {
			exec { "restart-db-${clustercontrol::params::mysql_service}-before-cmon-start":
				command => "systemctl restart ${clustercontrol::params::mysql_service}",
				require => Package[
					$clustercontrol::params::cc_controller,
					$clustercontrol::params::cc_ui2,
					$clustercontrol::params::cc_cloud,
					$clustercontrol::params::cc_clud,
					$clustercontrol::params::cc_notif,
					$clustercontrol::params::cc_ssh
				]
			}

		} else {
			exec { "restart-db-${clustercontrol::params::mysql_service}-before-cmon-start":
				command => "systemctl restart ${clustercontrol::params::mysql_service}",
				require => Package[
					$clustercontrol::params::cc_controller,
					$clustercontrol::params::cc_ui,
					$clustercontrol::params::cc_cloud,
					$clustercontrol::params::cc_clud,
					$clustercontrol::params::cc_notif,
					$clustercontrol::params::cc_ssh
				]
			}

		}
		
		service { 'cmon' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Exec["restart-db-${clustercontrol::params::mysql_service}-before-cmon-start"],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}

		exec { "create-cmon-upload-schema-directory" :
			path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			command => "mkdir -p ${clustercontrol::params::wwwroot}/cmon/upload/schema",
			require => [Package[$clustercontrol::params::apache_service],File["$ssh_identity", "$ssh_identity_pub"]]
		}

		if ($only_cc_v2) {
			## ccv2 only
			exec { "change-owner-to-apache-user" :
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "chown -R ${clustercontrol::params::apache_user}:${clustercontrol::params::apache_user} \
							${clustercontrol::params::wwwroot}/cmon/ \
							${clustercontrol::params::wwwroot}/clustercontrol2 \
				",
				require => [Package[$clustercontrol::params::cc_ui2],File["$ssh_identity", "$ssh_identity_pub"]],
				notify  => Service['cmon']
			}

		} else {
			## ccv1 and ccv2
			exec { "add-option-indexes-to-cmon-dir" :
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "cat > ${clustercontrol::params::wwwroot}/cmon/.htaccess << EOF
			Options -Indexes
			EOF
				",
				require => [Package[$clustercontrol::params::cc_ui],File["$ssh_identity", "$ssh_identity_pub"]],
			}

			exec { "change-mod-to-rwrw---" :
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "chmod -R 770 ${clustercontrol::params::wwwroot}/clustercontrol/app/tmp/ \
							${clustercontrol::params::wwwroot}/clustercontrol/app/upload  \
							${clustercontrol::params::wwwroot}/cmon \
				",
				require => [Package[$clustercontrol::params::cc_ui],File["$ssh_identity", "$ssh_identity_pub"]]
			}

			exec { "change-owner-to-apache-user" :
				path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
				command => "chown -R ${clustercontrol::params::apache_user}:${clustercontrol::params::apache_user} \
							${clustercontrol::params::wwwroot}/clustercontrol/app/tmp/ \
							${clustercontrol::params::wwwroot}/clustercontrol/app/upload  \
							${clustercontrol::params::wwwroot}/cmon \
							${clustercontrol::params::wwwroot}/clustercontrol \
							${clustercontrol::params::wwwroot}/clustercontrol2 \
				",
				require => [Package[$clustercontrol::params::cc_ui],File["$ssh_identity", "$ssh_identity_pub"]],
				notify  => Service['cmon']
			}

		}

		if ($only_cc_v2 == false) {
			exec { "configure-cc-bootstrap" :
				command => "sed -i 's|DBPASS|$mysql_cmon_password|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php && \
				sed -i 's|DBPORT|$mysql_cmon_port|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php",
				require => Package[$clustercontrol::params::cc_controller]
			}
			exec { "configure-cmonapi-bootstrap" :
				command => "sed -i 's|RPCTOKEN|$api_token|g' $clustercontrol::params::wwwroot/clustercontrol/bootstrap.php",
				require => Package[$clustercontrol::params::cc_controller]
			}
			file { "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php" :
				ensure  => present,
				replace => no,
				source  => "$clustercontrol::params::wwwroot/clustercontrol/bootstrap.php.default",
				require => Package["$clustercontrol::params::cc_ui"],
				notify  => Exec[['configure-cmonapi-bootstrap','configure-cc-bootstrap']],
			}
		}
		  
		service { 'cmon-cloud' :
			ensure  => $service_status,
			enable  => $enabled,
			require => Package[
				$clustercontrol::params::cc_controller,
				$clustercontrol::params::cc_ui2,
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
				$clustercontrol::params::cc_ui2,
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
				$clustercontrol::params::cc_ui2,
				$clustercontrol::params::cc_cloud,
				$clustercontrol::params::cc_clud,
				$clustercontrol::params::cc_notif,
				$clustercontrol::params::cc_ssh
			],
			subscribe    => File[$clustercontrol::params::cmon_conf],
			hasrestart   => true,
			hasstatus    => true
		}
	
		$username = "root"
		$home = "home_$username"
		$home_path = inline_template("<%= scope.lookupvar('::$home') %>")
		$user_path = "${home_path}/.s9s/ccrpc.conf"
		
		/*
		notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>s9s tool 
			home_path: ${home_path}, \
			user_path: ${user_path}, \
			home: ${home}": 
		}*/
		
		

		file { "${home_path}/.s9s/":
			ensure  => directory,
			owner   => "root",
			group   => "root",
			mode    => "0700",
			require => Service['cmon']
		}

		if (! $only_cc_v2) {
			$ccv1_file_array = 
				File[
					$clustercontrol::params::apache_s9s_conf_file,
					$clustercontrol::params::apache_s9s_ssl_conf_file,
					$clustercontrol::params::apache_s9s_cc_frontend_conf_file,
					$clustercontrol::params::apache_s9s_cc_proxy_conf_file,
				]
		} else {
			$ccv1_file_array = 
				File[
					$clustercontrol::params::apache_s9s_cc_frontend_conf_file,
					$clustercontrol::params::apache_s9s_cc_proxy_conf_file,

				]
		}

		exec { "pause-5s-to-propagate-cmon-library" :
			path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			command => "sleep 10",
			subscribe => [
				Service['cmon']
			]
		}	

    file {"/var/lib/cmon/ca/cmon/rpc_tls.crt":
			ensure  => file,
			validate_cmd => 'test -f /var/lib/cmon/ca/cmon/rpc_tls.crt',
			require => Exec["pause-5s-to-propagate-cmon-library"]
    }
		
		service { $clustercontrol::params::apache_service :
			ensure  => $service_status,
			enable  => $enabled,
			hasrestart  => true,
			hasstatus   => true,
			# subscribe  => [
			# 	File[
			# 		$clustercontrol::params::apache_s9s_conf_file,
			# 		$clustercontrol::params::apache_s9s_ssl_conf_file
			# 	],
			# 	Package[$clustercontrol::params::cc_controller]
			# ]
			# require => File["/var/lib/cmon/ca/cmon/rpc_tls.crt"],
			subscribe => [
				$ccv1_file_array
			]
		}

		exec { "create_ccrpc_user":
			path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			command => "sudo S9S_USER_CONFIG=${user_path} s9s user --create --new-password=$api_token --generate-key --private-key-file=~/.s9s/ccrpc.key --group=admins --controller=https://127.0.0.1:9501 ccrpc",
			# require =>  [Service['cmon'],File["${home_path}/.s9s/"]]
			require =>  File["${home_path}/.s9s/"]
		}


		exec { "create_ccrpc_set_firstname":
			path  => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
			user => "root",
			command => "sudo S9S_USER_CONFIG=${user_path} s9s user --set --first-name=RPC --last-name=API",
			# require =>  [File["${home_path}/.s9s/"],Service['cmon']]
			require => Exec["create_ccrpc_user"]
		}

		exec { "ccsetup_unlink":
			user => "root",
			command => "sudo rm -f /tmp/ccsetup.conf",
			require =>  [
				Exec['create_ccrpc_set_firstname'],
				Exec['create_ccrpc_user']
			]
		}

		exec { "create_ccsetup_user":			
			command => "sudo S9S_USER_CONFIG=/tmp/ccsetup.conf s9s user --create --new-password=admin --group=admins --email-address='${ccsetup_email}' --controller='https://127.0.0.1:9501' ccsetup",
			require =>  [Service['cmon'],File["${home_path}/.s9s/"]]
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
