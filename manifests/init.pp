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
  #$modulepath               = '/etc/puppet/modules/clustercontrol',
  $modulepath               = '/etc/puppetlabs/code/environments/production/modules/clustercontrol/',
  $datadir                  = '/var/lib/mysql',
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
	    $ssh_identity     = "$ssh_key"
	    $ssh_identity_pub = "$ssh_key.pub"
	}

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
			subscribe  => File[$clustercontrol::params::mysql_cnf],
			notify     => Exec['create-root-password']
		}
		

		package { $clustercontrol::params::mysql_packages :
			ensure  => installed,
			subscribe  => Exec['disable-extra-security']
		}
		
		exec { 'disable-extra-security' :
			path        => ['/usr/sbin', '/usr/bin'],
			onlyif      => 'which apparmor_status',
			command     => '/etc/init.d/apparmor stop; /etc/init.d/apparmor teardown; update-rc.d -f apparmor remove',
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
		
		
		
		


		exec { 'apt-update-severalnines' :
			path        => ['/bin','/usr/bin'],
			command     => 'apt-get update',
			require     => File[["$clustercontrol::params::repo_source"],["$clustercontrol::params::repo_tools_src"]],
			refreshonly => true
		}

		exec { 'import-severalnines-key' :
			path        => ['/bin','/usr/bin'],
			command     => "wget http://$clustercontrol::params::repo_host/severalnines-repos.asc -O- | apt-key add -"
		}

		exec { 'import-severalnines-tools-key' :
			path        => ['/bin','/usr/bin'],
			command     => "wget http://$clustercontrol::params::repo_host/s9s-tools/$clustercontrol::params::lsbdistcodename/Release.key -O- | apt-key add -"
		}

		file { "$clustercontrol::params::repo_source":
			content     => template('clustercontrol/s9s-repo.list.erb'),
			require     => Exec['import-severalnines-key'],
			notify      => Exec['apt-update-severalnines']
		}

		file { "clustercontrol::params::repo_tools_src":
			content     => template('clustercontrol/s9s-tools.list.erb'),
			require     => Exec['import-severalnines-tools-key'],
			notify      => Exec['apt-update-severalnines']
		}

		$severalnines_repo = Exec['apt-update-severalnines']



		
		
		
		
		
		

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
