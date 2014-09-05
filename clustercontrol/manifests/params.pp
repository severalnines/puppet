class clustercontrol::params {
  $repo_host = 'repo.severalnines.com'
  $cc_controller = 'clustercontrol-controller'
  $cc_cmonapi = 'clustercontrol-cmonapi'
  $cc_ui = 'clustercontrol'
  $cmon_conf = '/etc/cmon.cnf'
  $cmon_sql_path    = '/usr/share/cmon'
  
  case $osfamily {
    'Redhat': {
      $apache_conf_file = '/etc/httpd/conf/httpd.conf'
      $apache_ssl_conf_file = '/etc/httpd/conf.d/ssl.conf'
      $cert_file        = '/etc/pki/tls/certs/s9server.crt'
      $key_file        = '/etc/pki/tls/certs/s9server.key'
      $apache_user      = 'apache'
      $apache_service   = 'httpd'
      $wwwroot          = '/var/www/html'
      $mysql_service    = 'mysqld'
      $mysql_cnf        = '/etc/my.cnf'
      $mysql_packages   = ['mysql','mysql-server']
      $cc_dependencies  = [
        'httpd', 'wget', 'mailx', 'cronie', 'nc', 'curl', 'php', 'php-mysql', 'php-gd', 'php-ldap', 'mod_ssl', 'openssl'
      ]
      yumrepo {
        "s9s-repo":
          descr     => "Severalnines Release Repository",
          baseurl   => "http://$repo_host/rpm/os/x86_64",
          enabled   => 1,
          gpgkey    => "http://$repo_host/severalnines-repos.asc",
          gpgcheck  => 1
      }
      $severalnines_repo = Yumrepo["s9s-repo"]
      
      file { $apache_conf_file :
          ensure  => present,
          mode    => 644,
          owner   => root, group => root,
          require => Package[$cc_dependencies],
          notify  => Service[$apache_service]
          }
      
      file { $apache_ssl_conf_file :
        ensure  => present,
        content => template('clustercontrol/ssl.conf.erb'),
        notify  => Service[$apache_service]
      }
      
      file { '/etc/selinux/config':
        ensure  => present,
        content => template('clustercontrol/selinux-config.erb'),
      }
      
      exec { 'disable-extra-security' :
        path        => ['/usr/sbin','/bin'],
        unless      => 'grep SELINUX=disabled /etc/sysconfig/selinux',
        command     => 'setenforce 0',
        require     => File['/etc/selinux/config']
      }
      
    }
    'Debian': {
      if ($operatingsystem == 'Ubuntu') and ($lsbmajdistrelease > 12) {
        $wwwroot          = '/var/www/html'
        $apache_conf_file = '/etc/apache2/sites-available/s9s.conf'
        $apache_target_file = '/etc/apache2/sites-enabled/001-s9s.conf'
        $apache_ssl_conf_file = '/etc/apache2/sites-available/s9s-ssl.conf'
        $apache_ssl_target_file = '/etc/apache2/sites-enabled/001-s9s-ssl.conf'
        $extra_options     = 'Require all granted'
       
        file { [
          '/etc/apache2/sites-enabled/000-default.conf',
          '/etc/apache2/sites-enabled/default-ssl.conf',
          '/etc/apache2/sites-enabled/001-default-ssl.conf'
          ] :
          ensure  => absent,
        }
      } else {
        $wwwroot          = '/var/www'
        $apache_conf_file = '/etc/apache2/sites-available/default'
        $apache_target_file = '/etc/apache2/sites-enabled/000-default'
        $apache_ssl_conf_file = '/etc/apache2/sites-available/default-ssl.conf'
        $apache_ssl_target_file = '/etc/apache2/sites-enabled/000-default-ssl'
        $extra_options     = ''
      }
      
      $cert_file        = '/etc/ssl/certs/s9server.crt'
      $key_file         = '/etc/ssl/private/s9server.key'
      $apache_user      = 'www-data'
      $apache_service   = 'apache2'
      $mysql_service    = 'mysql'
      $mysql_cnf        = '/etc/mysql/my.cnf'
      $repo_list        = "deb [arch=amd64] http://$repo_host/deb ubuntu main"
      $repo_source      = '/etc/apt/sources.list.d/s9s-repo.list'
      $mysql_packages   = ['mysql-client','mysql-server']
      $cc_dependencies  = [
        'apache2', 'wget', 'mailutils', 'curl', 'php5-common', 'php5-mysql', 'php5-gd', 'php5-ldap', 'php5-curl', 'libapache2-mod-php5', 'php5-json'
      ]

      exec { 'apt-update-severalnines' :
        path        => ['/bin','/usr/bin'],
        command     => 'apt-get update',
        require     => File["$repo_source"],
        refreshonly => true
      }
      exec { 'import-severalnines-key' :
        path        => ['/bin','/usr/bin'],
        command     => "wget http://$repo_host/severalnines-repos.asc -O- | apt-key add -"
      }
      file { "$repo_source":
        content     => template('clustercontrol/s9s-repo.list.erb'),
        require     => Exec['import-severalnines-key'],
        notify      => Exec['apt-update-severalnines']
      }
      $severalnines_repo = Exec['apt-update-severalnines']
      
      exec { 'enable-apache-modules': 
        path  => ['/usr/sbin','/sbin', '/usr/bin'],
        command => "a2enmod ssl && a2enmod rewrite",
        require => Package[$cc_dependencies]
        }
      
      file { $apache_conf_file :
          ensure  => present,
          content => template('clustercontrol/s9s.conf.erb'),
          mode    => 644,
          owner   => root, group => root,
          require => Package[$cc_ui],
          notify   => File[$apache_target_file]
        }
      
      file { $apache_ssl_conf_file :
          ensure  => present,
          content => template('clustercontrol/s9s-ssl.conf.erb'),
          mode    => 644,
          owner   => root, group => root,
          require => Package[$cc_ui],
          notify   => File[$apache_ssl_target_file]
        }
        
      file { $apache_ssl_target_file :
          ensure => 'link',
          target => "$apache_ssl_conf_file"
        }
        
      file { $apache_target_file :
          ensure => 'link',
          target => "$apache_conf_file"
        }
        
      exec { 'disable-extra-security' :
        path        => ['/usr/sbin', '/usr/bin'],
        onlyif      => 'which apparmor_status',
        command     => '/etc/init.d/apparmor stop; /etc/init.d/apparmor teardown; update-rc.d -f apparmor remove',
      }
    }
    default: {
    }
  }
}