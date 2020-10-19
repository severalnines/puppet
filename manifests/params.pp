class clustercontrol::params {
	$repo_host = 'repo.severalnines.com'
	$cc_controller = 'clustercontrol-controller'
	$cc_ui = 'clustercontrol'
	$cc_cloud = 'clustercontrol-cloud'
	$cc_clud = 'clustercontrol-clud'
	$cc_ssh = 'clustercontrol-ssh'
	$cc_notif = 'clustercontrol-notifications'
	$cmon_conf = '/etc/cmon.cnf'
	$cmon_sql_path  = '/usr/share/cmon'
	$apache_httpd_extra_options = 'Require all granted'

	$lsbmajdistrelease = 0 + $operatingsystemmajrelease
	$typevar = type($lsbmajdistrelease)
	$lower_operatingsystem = downcase($operatingsystem)
	
	case $osfamily {
		'Redhat': {
			$os_majrelease = Integer($operatingsystemmajrelease);
			$s9s_tools_repo_osname = "${operatingsystem}_${operatingsystemmajrelease}";
			notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>s9s tool reponame: ${$s9s_tools_repo_osname}, \
				os_majrelease: ${$os_majrelease}, ${ipaddress_lo}, codename: ${lsbdistcodename} , \
				lsbmajdistrelease: ${lsbmajdistrelease} and data-type is: ${typevar})": 
			}
			$cc_dependencies  = [
			'httpd', 'wget', 'mailx', 'curl', 'cronie', 'bind-utils', 'php', 'php-gd', 'php-ldap', 'mod_ssl', 'openssl', 'clustercontrol-notifications', 'clustercontrol-ssh', 'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools'
			]
				
			if ($lsbmajdistrelease > 6) {
				$mysql_packages   = ['mariadb','mariadb-server']
				$mysql_service    = 'mariadb'
				$cc_dependencies += ['nmap-ncat', 'php-mysql']
			} elsif ($lsbmajdistrelease > 7) {
				$mysql_packages   = ['mariadb','mariadb-server']
				$mysql_service    = 'mariadb'
				$cc_dependencies += [ 'nmap-ncat', 'php-mysqlnd']
			} else {
				$mysql_packages   = ['mysql','mysql-server']
				$mysql_service    = 'mysqld'
				$cc_dependencies  += ['nc', 'php-mysql'];
				
				/*$cc_dependencies  = ['httpd', 'wget', 'mailx', 'curl', 'cronie', 'nc', 'bind-utils', 'php', 'php-mysql', 'php-gd', 'php-ldap', 'mod_ssl', 'openssl', 'clustercontrol-notifications', 'clustercontrol-ssh', 'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools'
				]*/
			}
			
			$apache_conf_file = '/etc/httpd/conf/httpd.conf'
			$apache_ssl_conf_file = '/etc/httpd/conf.d/ssl.conf'
			$cert_file        = '/etc/pki/tls/certs/s9server.crt'
			$key_file         = '/etc/pki/tls/private/s9server.key'
			$apache_user      = 'apache'
			$apache_service   = 'httpd'
			$wwwroot          = '/var/www/html'
			$mysql_cnf        = '/etc/my.cnf'

			yumrepo {
				"s9s-repo":
				descr     => "Severalnines Repository",
				baseurl   => "http://$repo_host/rpm/os/x86_64",
				enabled   => 1,
				gpgkey    => "http://$repo_host/severalnines-repos.asc",
				gpgcheck  => 1
			}
			
			yumrepo {
				"s9s-tools-repo":
				descr     => "s9s-tools $s9s_tools_repo_osname",
				baseurl   => "http://$repo_host/s9s-tools/$s9s_tools_repo_osname",
				enabled   => 1,
				gpgkey    => "http://$repo_host/s9s-tools/$s9s_tools_repo_osname/repodata/repomd.xml.key",
				gpgcheck  => 1
			}
			
			$severalnines_repo = Yumrepo[["s9s-repo","s9s-tools-repo"]]

			/*
			file { $apache_conf_file :
				ensure  => present,
				mode    => '0644',
				owner   => root, group => root,
				require => Package[$cc_dependencies],
				notify  => Service[$apache_service]
			}

			file { $apache_ssl_conf_file :
				ensure  => present,
				content => template('clustercontrol/ssl.conf.erb'),
				notify  => Service[$apache_service]
			}
			*/
			
		}
		'Debian': {
			
			if ($operatingsystem == 'Ubuntu' and $lsbmajdistrelease > 12) or ($operatingsystem == 'Debian' and $lsbmajdistrelease > 7) {
				
				
				/*notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>The value is: ${lower_operatingsystem}  and ${ipaddress_lo} and ${lsbdistcodename} and ${lsbmajdistrelease} and data-type is: ${typevar})": }*/
				
				$wwwroot          = '/var/www/html'
				$apache_conf_file = '/etc/apache2/sites-available/s9s.conf'
				$apache_target_file = '/etc/apache2/sites-enabled/001-s9s.conf'
				$apache_ssl_conf_file = '/etc/apache2/sites-available/s9s-ssl.conf'
				$apache_ssl_target_file = '/etc/apache2/sites-enabled/001-s9s-ssl.conf'

				/* Remove unwanted config files, retain only s9s config files */
				file {
					[
						'/etc/apache2/sites-enabled/000-default.conf',
						'/etc/apache2/sites-enabled/default-ssl.conf',
						'/etc/apache2/sites-enabled/001-default-ssl.conf'
					] :
					ensure  => absent
				}
			} else {
				$wwwroot          = '/var/www'
				$apache_conf_file = '/etc/apache2/sites-available/000-default.conf'
				$apache_target_file = '/etc/apache2/sites-enabled/000-default.conf'
				$apache_ssl_conf_file = '/etc/apache2/sites-available/default-ssl.conf'
				$apache_ssl_target_file = '/etc/apache2/sites-enabled/default-ssl.conf'
				$apache_httpd_extra_options  = ''
			}

			$cert_file        = '/etc/ssl/certs/s9server.crt'
			$key_file         = '/etc/ssl/private/s9server.key'
			$apache_user      = 'www-data'
			$apache_service   = 'apache2'
			$mysql_service    = 'mysql'
			$mysql_cnf        = '/etc/mysql/my.cnf'
			$repo_source      = '/etc/apt/sources.list.d/s9s-repo.list'
			$repo_tools_src   = '/etc/apt/sources.list.d/s9s-tools.list'
			
			
			$mysql_packages   = ['mysql-client','mysql-server']
			$cc_dependencies  = [
				'apache2', 'wget', 'mailutils', 'curl', 'dnsutils', 'php-common', 'php-mysql', 'php-gd', 'php-ldap', 'php-curl', 'libapache2-mod-php', 'php-json', 'clustercontrol-notifications', 'clustercontrol-ssh', 'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools'
			]
			

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
				command     => "wget http://$clustercontrol::params::repo_host/s9s-tools/$lsbdistcodename/Release.key -O- | apt-key add -"
			}

			file { "$repo_source":
				content     => template('clustercontrol/s9s-repo.list.erb'),
				require     => Exec['import-severalnines-key'],
				notify      => Exec['apt-update-severalnines']
			}

			file { "$repo_tools_src":
				content     => template('clustercontrol/s9s-tools.list.erb'),
				require     => Exec['import-severalnines-tools-key'],
				notify      => Exec['apt-update-severalnines']
			}

			$severalnines_repo = Exec['apt-update-severalnines']
		
		}
		default: {
		}
	}
}
