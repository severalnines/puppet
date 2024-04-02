class clustercontrol::params ($online_install = true, $only_cc_v2 = true) {
	$repo_host = 'repo.severalnines.com'
	$cc_controller = 'clustercontrol-controller'
	$cc_ui = 'clustercontrol'
	$cc_ui2 = 'clustercontrol2'
	$cc_cloud = 'clustercontrol-cloud'
	$cc_clud = 'clustercontrol-clud'
	$cc_ssh = 'clustercontrol-ssh'
	$cc_notif = 'clustercontrol-notifications'
	$libs9s = 'libs9s'
	$s9stools = 's9s-tools'
	$cmon_conf = '/etc/cmon.cnf'
	$cmon_sql_path  = '/usr/share/cmon'
	$apache_httpd_extra_options = 'Require all granted'
	
	$format = "%i"
	$a_version_no = scanf($operatingsystemmajrelease, $format)
	$os_majrelease = $a_version_no[0]
	/*notice(">>>>>> CC Debugger >>>>>> value is: $os_majrelease + ${operatingsystemmajrelease}")*/

	$typevar = type($os_majrelease)
	$lower_operatingsystem = downcase($operatingsystem)
	
	$cc_v2_config_ui_file = "/var/www/html/clustercontrol2/config.js"

	notice(">>>>>> CC Debugger >>>>>> value is: $osfamily + ${operatingsystemmajrelease}")
	case $osfamily {
		'Redhat': {
			if ($operatingsystem == 'RedHat') {
				$s9s_tools_repo_osname = "RHEL_${operatingsystemmajrelease}"
			} else {
				$s9s_tools_repo_osname = "${operatingsystem}_${operatingsystemmajrelease}"
			}
			
			if ($os_majrelease >= 10) {
				fail("ClusterControl has no support for RHEL versions >= 10.")
			}

			
            if ($os_majrelease >= 9) {
				# RHEL/CentOS v 9.x and up
                $mailer = 's-nail'
				## fail for now since we don't support PHP 8.x which is the default shipped package for
				## RHEL/CentOS/Rocky/AlmaLinux/Oracle 9.x

				if (! $only_cc_v2) {
					notice(
						"This Puppet Module ClusterControl only supports RHEL/CentOS/Rocky/AlmaLinux/Oracle >= 7 to 8.x versions only. 
						Enterprise Linux version 9.x has PHP 8.x versions which we don't support as of this time. 
						ClusterControl UI version 1 does not support PHP 8.x, so if it don't work, 
						you need to downgrade your PHP 8.x to PHP 7.x version"
					)
				
	                notify {"Setting up PHP 7 ...": }

					exec { 'yum-install-remi-release-9' :
						path        => ['/bin','/usr/bin'],
						command     => 'dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm',
						unless      => 'rpm -qa|egrep -i remi'
					}

					package { 'php:module':
					    ensure   => disabled,
					    name     => 'php',
					    provider => dnfmodule,      # Configs module, not package
					}
				
					package { 'php:remi-7.4':          # Use resource title to choose stream
					    ensure      => present,
					    provider    => dnfmodule,
					    enable_only => true,        # Don't install whole module
					}
				  

				    # yum install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm
				    # yum module reset php
				    # yum module enable php:remi-7.4 -y

					notify {"Using PHP 7 repository ...": }
				}
				
			} else {
				$mailer = 'mailx'
			}
			
			$php_packages_inc = ['php', 'php-gd', 'php-fpm', 'php-xml', 'php-json', 'php-ldap']

			$cc_packages = [
				'clustercontrol-notifications', 'clustercontrol-ssh', 'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools'
			]
			
			if ($online_install) {	
				$loc_dependencies  = ['httpd', 'wget', $mailer, 'curl', 'cronie', 'bind-utils', 'mod_ssl', 'openssl', 'nmap-ncat']
			} else {
				$loc_dependencies  = [
					'httpd', 'wget', 'curl', 'cronie', 'bind-utils', 'mod_ssl', 'openssl', 
					'nmap-ncat', 'gnuplot', 'expect','perl-XML-XPath', $mailer, 'psmisc'
				]
			}
			
			$apache_conf_file = "/etc/httpd/conf/httpd.conf"
			$apache_security_conf_file = "/etc/httpd/conf.d/security.conf"
			$apache_log_dir = "/var/log/httpd/"
			$apache_s9s_conf_file = '/etc/httpd/conf.d/s9s.conf'
			$apache_s9s_ssl_conf_file = '/etc/httpd/conf.d/ssl.conf'
			$apache_s9s_cc_frontend_conf_file = '/etc/httpd/conf.d/cc-frontend.conf'
			$apache_s9s_cc_proxy_conf_file = '/etc/httpd/conf.d/cc-proxy.conf'
			$cert_file        = '/etc/pki/tls/certs/s9server.crt'
			$key_file         = '/etc/pki/tls/private/s9server.key'
			$apache_user      = 'apache'
			$apache_service   = 'httpd'
			$wwwroot          = '/var/www/html'
			$mysql_cnf        = '/etc/my.cnf'

			$mysql_service    = 'mariadb'
			$mysql_packages   = ['mariadb','mariadb-server']
				
			if ($os_majrelease == 7) {
				$php_packages = $php_packages_inc + ['php-mysql']			
			} elsif ($os_majrelease > 7) {
				# RHEL/CentOS v 8.0 and up
				$php_packages = $php_packages_inc + ['php-mysqlnd']
			} else {
				fail("This Puppet Module ClusterControl only supports RHEL/CentOS >= 7 versions. Obsolete or versions that passed EOL is no longer supported. Please contact Severalnines (support@severalnines.com) if you see unusual behavior.")
			}

			if ($only_cc_v2) {
				$cc_dependencies = $loc_dependencies + $cc_packages	
			} else {
				$cc_dependencies = $loc_dependencies + $php_packages + $cc_packages			
			}

			
			/*notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>s9s tool reponame: ${$s9s_tools_repo_osname}, \
				os_majrelease: ${$os_majrelease}, ${cc_hostname_lo}, codename: ${lsbdistcodename} , \
				os_majrelease: ${os_majrelease} and data-type is: ${typevar}), \
				cc_dependencies: ${cc_dependencies}": 
			}*/
			
			if ($online_install) {
				## Execute repo fetch and updates for s9s only when has internet connection or access to s9s site.
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
			}
			
		}
		'Debian': {
			
			if ($operatingsystem == 'Ubuntu' and $os_majrelease >= 18) or ($operatingsystem == 'Debian' and $os_majrelease > 7) {
				
				/*notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>The value is: ${lower_operatingsystem}  and ${cc_hostname_lo} and ${lsbdistcodename} and ${os_majrelease} and data-type is: ${typevar})": }*/

				# notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>The value is: ${lower_operatingsystem}  and ${cc_hostname_lo} and ${lsbdistcodename} and ${os_majrelease} and data-type is: ${typevar})": }
				
				/*notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>The value is: ${lower_operatingsystem}  and ${cc_hostname_lo} and ${lsbdistcodename} and ${os_majrelease} and data-type is: ${typevar})": }*/

				if (($operatingsystem == 'Ubuntu' and $os_majrelease >= 23) or (operatingsystem == 'Debian' and $os_majrelease >= 11)) {
					fail("ClusterControl has no support yet to Ubuntu versions >= 23 or Debian >= 11.")
				}
				
				if ($only_cc_v2 == false and $operatingsystem == 'Ubuntu' and $os_majrelease >= 22) {
					## only CC v1 requires PHP
					# Jhammy and up
					## fail for now since we don't support PHP 8.x which is the default shipped package for
					# Ubuntu Jhammy and up
					notify {"ClusterControl UI version 1 does not support PHP 8.x version.": }
      			  	notify {"Instead, ClusterControl will downgrade and setup PHP 7 for you...": }
                    notify {"Setting up PHP 7 ...": }

					exec { 'apt-update-for-php7-prep' :
						path        => ['/bin','/usr/bin'],
						command     => 'apt-get update'
					}

					package { 'software-properties-common':
					  ensure => installed
					}

					package { 'apt-transport-https':
					  ensure => installed
					}

					exec { 'add-apt-php7-repo' :
						path        => ['/bin','/usr/bin'],
						command     => 'add-apt-repository -y ppa:ondrej/php'
					}

					notify {"Using PHP 7 repository ...": }

				}
							
				$apache_log_dir = "/var/log/apache2/"
				$wwwroot          = '/var/www/html'
				$apache_conf_file = "/etc/apache2/apache2.conf"
				$apache_s9s_conf_file = '/etc/apache2/sites-available/s9s.conf'
				$apache_s9s_target_file = '/etc/apache2/sites-enabled/001-s9s.conf'
				$apache_s9s_ssl_conf_file = '/etc/apache2/sites-available/s9s-ssl.conf'
				$apache_s9s_ssl_target_file = '/etc/apache2/sites-enabled/001-s9s-ssl.conf'

				$apache_s9s_cc_frontend_conf_file = '/etc/apache2/sites-available/cc-frontend.conf'
				$apache_s9s_cc_frontend_target_file = '/etc/apache2/sites-enabled/cc-frontend.conf'
				$apache_s9s_cc_proxy_conf_file = '/etc/apache2/sites-available/cc-proxy.conf'
				$apache_s9s_cc_proxy_target_file = '/etc/apache2/sites-enabled/cc-proxy.conf'
				
				$apache_security_conf_file = "//etc/apache2/conf-available/security.conf"
				$apache_security_target_conf_file = "/etc/apache2/conf-enabled/security.conf"
				$apache_mods_header_file = '/etc/apache2/mods-available/headers.load'
				$apache_mods_header_target_file = '/etc/apache2/mods-enabled/headers.load'
				

				$cert_file        = '/etc/ssl/certs/s9server.crt'
				$key_file         = '/etc/ssl/private/s9server.key'
				$apache_user      = 'www-data'
				$apache_service   = 'apache2'
				$mysql_service    = 'mysql'
				$mysql_cnf        = '/etc/mysql/my.cnf'
				$repo_source      = '/etc/apt/sources.list.d/s9s-repo.list'
				$repo_tools_src   = '/etc/apt/sources.list.d/s9s-tools.list'
			
				if ($operatingsystem == 'Debian') {
					$mysql_packages   = ['mariadb-client','mariadb-server']
				} else {
					$mysql_packages   = ['mysql-client','mysql-server']
				}
				

				if ($only_cc_v2) {
					## php is not needed for ccv2
					$php_packages = []
				} else {						
					if ($operatingsystem == 'Ubuntu' and $os_majrelease >= 22) {
						## jammy
						$php_packages = [ 
							'php7.4-mysql', 'php7.4-gd', 'libapache2-mod-php7.4', 'php7.4-curl', 
							'php7.4-ldap', 'php7.4-xml', 'php7.4-json'#, 'php7.4-fpm',
						]
					} else {
						$php_packages = [ 
							'php-mysql', 'php-gd', 'libapache2-mod-php', 'php-curl', 
							'php-ldap', 'php-xml', 'php-json'#, 'php-fpm',
						]
					}
				}
				

				if ($online_install) {
					$cc_packges = [
						'clustercontrol-notifications', 'clustercontrol-ssh', 
						'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools'
					]
					
					$cc_dependencies = ['apache2', 'wget', 'mailutils', 'curl', 'dnsutils'] + $php_packages + $cc_packges
				} else {
					$cc_dependencies = ['apache2', 'wget', 'mailutils', 'curl', 'dnsutils'] + $php_packages
				}
				

				/* Remove unwanted config files, retain only s9s config files */
				file {
					[
						'/etc/apache2/sites-enabled/000-default.conf',
						'/etc/apache2/sites-enabled/default-ssl.conf',
						'/etc/apache2/sites-enabled/001-default-ssl.conf'
					] :
					ensure  => absent,
					require => Package[$cc_dependencies]
				}
			} else {
				fail("This Puppet Module ClusterControl only supports Ubuntu >= 16 versions and Debian >=9 versions. 
				Obsolete or versions that passed EOL is no longer supported. Please contact Severalnines (support@severalnines.com) 
				if you see unusual behavior.")
				/*
				$wwwroot          = '/var/www'
				$apache_s9s_conf_file = '/etc/apache2/sites-available/000-default.conf'
				$apache_s9s_target_file = '/etc/apache2/sites-enabled/000-default.conf'
				$apache_s9s_ssl_conf_file = '/etc/apache2/sites-available/default-ssl.conf'
				$apache_s9s_ssl_target_file = '/etc/apache2/sites-enabled/default-ssl.conf'
				$apache_httpd_extra_options  = ''
				*/
			}
			
			if ($online_install) {
				## Execute repo fetch and updates for s9s only when has internet connection or access to s9s site.
				exec { 'apt-update-severalnines' :
					path        => ['/bin','/usr/bin'],
					command     => 'apt-get update',
					require     => File[
							["$clustercontrol::params::repo_source"],
							["$clustercontrol::params::repo_tools_src"]
					],
					refreshonly => true
				}
				
				## gpg ensures in Debian Bullseye not to fail (ensuring gpg is installed)
				package { 'gpg' :
					ensure => "installed",
				}

				exec { 'import-severalnines-key' :
					path        => ['/bin','/usr/bin'],
					command     => "wget -qO - http://$clustercontrol::params::repo_host/severalnines-repos.asc | apt-key add -",
					require     => Package["gpg"]
				}

				exec { 'import-severalnines-tools-key' :
					path        => ['/bin','/usr/bin'],
					command     => "wget -qO - http://$clustercontrol::params::repo_host/s9s-tools/$lsbdistcodename/Release.key | apt-key add -",
					require     => Package["gpg"]
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
		
		}
		'Suse': {
			
			if (Integer($operatingsystemmajrelease) >= 15) {
				if ($operatingsystemmajrelease == '15') {
					$s9s_tools_repo_osname = "${operatingsystemrelease}"
				} else {
					$s9s_tools_repo_osname = "${operatingsystem}_${operatingsystemrelease}"
				}
			

				if ($only_cc_v2) {
					## no php packages
					$php_packages = []
				} else {
					$php_packages = [
						'php7', 'php7-mysql', 'apache2-mod_php7', 'php7-gd', 'php7-curl', 'php7-ldap', 
						'php7-xmlreader', 'php7-ctype', 'php7-json',
					]
				}

				$cc_packages = ['clustercontrol-notifications', 'clustercontrol-ssh', 'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools']

				if ($online_install) {	
					$loc_dependencies  = [
						'apache2', 'wget', 'mailx', 'curl', 'cronie', 'bind-utils', 
						## shall fix the issues with systemd and sysvinit scripts
						'insserv-compat', 'sysvinit-tools', 
						'openssl', 'ca-certificates', 
						'gnuplot', 'expect', 'perl-XML-XPath', 'psmisc',
						#'mod_ssl'
					]
				} else {
					$loc_dependencies  = [
						'apache2', 'wget', 'mailx', 'curl', 'cronie', 'bind-utils', 'insserv-compat', 'sysvinit-tools',
						'openssl', 'ca-certificates', 'gnuplot', 'expect', 'perl-XML-XPath', 'psmisc',
						#'mod_ssl'
					]
				}
				
				/*notify{"<<<<<<<<<<<<<CC Debugger:>>>>>>>>>>>>>The value is: ${lower_operatingsystem}  and ${cc_hostname_lo} and ${lsbdistcodename} and ${os_majrelease} and data-type is: ${typevar})": }*/
			
				#$apache_s9s_conf_file = '/etc/apache2/vhosts.d/s9s.conf'
				$apache_s9s_conf_file = '/etc/apache2/vhosts.d/s9s.conf'
				$apache_s9s_ssl_conf_file = '/etc/apache2/vhosts.d/ssl.conf'

				$apache_s9s_cc_frontend_conf_file = '/etc/apache2/vhosts.d/cc-frontend.conf'
				$apache_s9s_cc_proxy_conf_file = '/etc/apache2/vhosts.d/cc-proxy.conf'
				

				$cert_file        = '/etc/ssl/certs/s9server.crt'
				$key_file         = '/etc/ssl/private/s9server.key'
				$apache_user      = 'wwwrun'
				$apache_service   = 'apache2'
			
				$apache_log_dir   = "/var/log/apache2/"
				$wwwroot          = '/var/www/html'
				$mysql_cnf        = '/etc/my.cnf'
			
				
				if (Integer($operatingsystemmajrelease) >= 15) {
					$mysql_service    = 'mariadb'
					$mysql_packages   = ['mariadb','mariadb-client']
					$cc_dependencies = $loc_dependencies + $php_packages + $cc_packages
				} else {

					fail("This Puppet Module ClusterControl only supports SUSE/OpenSUSE >= 15 versions. " +
						 "Obsolete or versions that passed EOL is no longer supported. Please contact " + 
						 "Severalnines (support@severalnines.com) if you see unusual behavior.")
				}
			
			} else {
				fail("This Puppet Module ClusterControl only supports SUSE/OpenSUSE >= 15 versions. " +
					 "Obsolete or versions that passed EOL is no longer supported. Please contact " + 
					 "Severalnines (support@severalnines.com) if you see unusual behavior.")
			}
			
		
			if ($online_install) {
				## Execute repo fetch and updates for s9s only when has internet connection or access to s9s site.
				zypprepo {
					"s9s-repo":
					descr     => "Severalnines Repository",
					baseurl   => "http://$repo_host/rpm/os/x86_64",
					enabled   => 1,
					gpgkey    => "http://$repo_host/severalnines-repos.asc",
					gpgcheck  => 1
				}
		
				zypprepo {
					"s9s-tools-repo":
					descr     => "s9s-tools - $s9s_tools_repo_osname",
					baseurl   => "http://$repo_host/s9s-tools/$s9s_tools_repo_osname",
					enabled   => 1,
					gpgkey    => "http://$repo_host/s9s-tools/$s9s_tools_repo_osname/repodata/repomd.xml.key",
					gpgcheck  => 1
				}
			}
		
		}
		default: {
				fail("This Puppet Module ClusterControl only supports RHEL/CentOS >= 7, Ubuntu >= 16, Debian >= 9 versions. Obsolete or versions that passed EOL is no longer supported. Please contact Severalnines (support@severalnines.com) if you see unusual behavior.")
		}
	}
}
