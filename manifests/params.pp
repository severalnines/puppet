class clustercontrol::params ($online_install = true, $only_cc_v2 = true) {

  # ---------------------------------------------------------------------------
  # Repository & package name constants
  # ---------------------------------------------------------------------------
  $repo_host = 'repo.severalnines.com'

  # Core CC packages (CC 2.4.x names)
  $cc_controller  = 'clustercontrol-controller'
  $cc_ui          = 'clustercontrol'             # CCv1 legacy UI (only_cc_v2 = false)
  $cc_ui2         = 'clustercontrol-mcc'         # CCv2 UI  (was 'clustercontrol2')
  $cc_cloud       = 'clustercontrol-cloud'
  $cc_clud        = 'clustercontrol-clud'
  $cc_ssh         = 'clustercontrol-ssh'
  $cc_notif       = 'clustercontrol-notifications'
  $cc_proxy       = 'clustercontrol-proxy'       # NEW in CC 2.x
  $cc_kuber_proxy = 'clustercontrol-kuber-proxy' # NEW in CC 2.x
  $libs9s         = 'libs9s'
  $s9stools       = 's9s-tools'

  # Paths
  $cmon_conf         = '/etc/cmon.cnf'
  $cmon_sql_path     = '/usr/share/cmon'
  $cmon_default_file = '/etc/default/cmon'

  $apache_httpd_extra_options = 'Require all granted'

  # CC v2 web root (changed from clustercontrol2 -> clustercontrol-mcc in CC 2.x)
  $cc_v2_webroot        = '/var/www/html/clustercontrol-mcc'
  $cc_v2_config_ui_file = "${cc_v2_webroot}/config.js"

  # ---------------------------------------------------------------------------
  # Helper: convert major-release string to integer for numeric comparisons
  # ---------------------------------------------------------------------------
  $format          = "%i"
  $a_version_no    = scanf($operatingsystemmajrelease, $format)
  $os_majrelease   = $a_version_no[0]
  $lower_operatingsystem = downcase($operatingsystem)

  notice(">>> clustercontrol::params  osfamily=${osfamily}  majrelease=${operatingsystemmajrelease}")

  # ---------------------------------------------------------------------------
  # OS-family branching
  # ---------------------------------------------------------------------------
  case $osfamily {

    # =========================================================================
    # Red Hat family  (RHEL / CentOS / Rocky / AlmaLinux / Oracle Linux)
    # Supported: EL 7, 8, 9
    # =========================================================================
    'RedHat': {

      # The s9s-tools repo at repo.severalnines.com only has:
      #   RHEL_7, RHEL_8, RHEL_9, CentOS_7, CentOS_8, CentOS_9, CentOS_9_Stream
      # Rocky Linux, AlmaLinux, OracleLinux are ABI-compatible with RHEL
      # and must use the RHEL_<version> repo path.
      case $operatingsystem {
        'RedHat':                         { $s9s_tools_repo_osname = "RHEL_${operatingsystemmajrelease}" }
        'CentOS':                         { $s9s_tools_repo_osname = "CentOS_${operatingsystemmajrelease}" }
        'Rocky', 'AlmaLinux', 'OracleLinux', 'Scientific': {
          # No Rocky_9/Alma_9 repo exists — use the RHEL equivalent
          $s9s_tools_repo_osname = "RHEL_${operatingsystemmajrelease}"
        }
        default:                          { $s9s_tools_repo_osname = "RHEL_${operatingsystemmajrelease}" }
      }

      if ($os_majrelease >= 10) {
        fail("ClusterControl does not yet support ${operatingsystem} ${operatingsystemmajrelease}. Supported: EL 7, 8, 9.")
      }

      if ($os_majrelease < 7) {
        fail("ClusterControl requires ${operatingsystem} >= 7. Version ${operatingsystemmajrelease} is not supported.")
      }

      # Mailer package differs between EL versions
      if ($os_majrelease >= 9) {
        $mailer = 's-nail'
      } else {
        $mailer = 'mailx'
      }

      # PHP (only needed for CCv1)
      if (! $only_cc_v2) {
        $php_packages_inc = ['php', 'php-gd', 'php-fpm', 'php-xml', 'php-json', 'php-ldap']

        if ($os_majrelease >= 9) {
          # EL 9 ships PHP 8 – install Remi repo for PHP 7.4
          notice("EL ${os_majrelease}: CCv1 requires PHP 7.4 via Remi repository.")
          exec { 'install-remi-release-el9':
            path    => ['/bin', '/usr/bin'],
            command => "dnf install -y https://rpms.remirepo.net/enterprise/remi-release-${operatingsystemmajrelease}.rpm",
            unless  => 'rpm -qa | grep -qi remi',
          }
          package { 'php-module-disable':
            ensure   => disabled,
            name     => 'php',
            provider => dnfmodule,
            require  => Exec['install-remi-release-el9'],
          }
          package { 'php-remi-74':
            ensure      => present,
            name        => 'php:remi-7.4',
            provider    => dnfmodule,
            enable_only => true,
            require     => Package['php-module-disable'],
          }
        }

        if ($os_majrelease == 7) {
          $php_packages = $php_packages_inc + ['php-mysql']
        } else {
          $php_packages = $php_packages_inc + ['php-mysqlnd']
        }
      } else {
        $php_packages = []
      }

      # Base dependencies
      # Note: nmap-ncat is in EPEL on EL 8/9. We ensure epel-release is present first.
      if ($os_majrelease >= 8) {
        exec { 'install-epel-release':
          path    => ['/bin', '/usr/bin'],
          command => 'dnf install -y epel-release',
          unless  => 'rpm -qa | grep -qi epel-release',
        }
      }

      $loc_dependencies = [
        'httpd', 'wget', $mailer, 'curl', 'cronie',
        'bind-utils', 'mod_ssl', 'openssl', 'nmap-ncat',
        'dmidecode', 'hostname',
      ]

      $cc_service_packages = [
        'clustercontrol-notifications', 'clustercontrol-ssh',
        'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools',
      ]

      if ($only_cc_v2) {
        $cc_dependencies = $loc_dependencies + $cc_service_packages
      } else {
        $cc_dependencies = $loc_dependencies + $php_packages + $cc_service_packages
      }

      # Apache / filesystem paths
      $apache_conf_file                 = '/etc/httpd/conf/httpd.conf'
      $apache_security_conf_file        = '/etc/httpd/conf.d/security.conf'
      $apache_log_dir                   = '/var/log/httpd/'
      $apache_s9s_conf_file             = '/etc/httpd/conf.d/s9s.conf'
      $apache_s9s_ssl_conf_file         = '/etc/httpd/conf.d/ssl.conf'
      $apache_s9s_cc_frontend_conf_file = '/etc/httpd/conf.d/cc-frontend.conf'
      $apache_s9s_cc_proxy_conf_file    = '/etc/httpd/conf.d/cc-proxy.conf'
      $cert_file                        = '/etc/pki/tls/certs/s9server.crt'
      $key_file                         = '/etc/pki/tls/private/s9server.key'
      $apache_user                      = 'apache'
      $apache_service                   = 'httpd'
      $wwwroot                          = '/var/www/html'
      $mysql_cnf                        = '/etc/my.cnf'
      $mysql_service                    = 'mariadb'
      $mysql_packages                   = ['mariadb', 'mariadb-server']

      if ($online_install) {
        yumrepo { 's9s-repo':
          descr    => 'Severalnines Repository',
          baseurl  => "http://${repo_host}/rpm/os/x86_64",
          enabled  => 1,
          gpgkey   => "http://${repo_host}/severalnines-repos.asc",
          gpgcheck => 1,
        }
        yumrepo { 's9s-tools-repo':
          descr    => "s9s-tools ${s9s_tools_repo_osname}",
          baseurl  => "http://${repo_host}/s9s-tools/${s9s_tools_repo_osname}",
          enabled  => 1,
          gpgkey   => "http://${repo_host}/s9s-tools/${s9s_tools_repo_osname}/repodata/repomd.xml.key",
          gpgcheck => 1,
        }
        $severalnines_repo = Yumrepo[['s9s-repo', 's9s-tools-repo']]
      }
    }

    # =========================================================================
    # Debian family  (Debian 9-13 / Ubuntu 18-25)
    # Adds:  Ubuntu 24.04 (Noble),  Debian 12 (Bookworm)
    # =========================================================================
    'Debian': {

      # Version guards
      if ($operatingsystem == 'Ubuntu') {
        if ($os_majrelease < 18) {
          fail("Ubuntu ${operatingsystemmajrelease} is not supported. Minimum: Ubuntu 18.04 LTS.")
        }
        if ($os_majrelease >= 26) {
          fail("Ubuntu ${operatingsystemmajrelease} is not yet validated. Please check for a module update.")
        }
      } elsif ($operatingsystem == 'Debian') {
        if ($os_majrelease < 9) {
          fail("Debian ${operatingsystemmajrelease} is not supported. Minimum: Debian 9 (Stretch).")
        }
        if ($os_majrelease >= 14) {
          fail("Debian ${operatingsystemmajrelease} is not yet validated. Please check for a module update.")
        }
      } else {
        fail("Unsupported Debian-family OS: ${operatingsystem}.")
      }

      # PHP for CCv1 only
      if ($only_cc_v2 == false) {
        if (($operatingsystem == 'Ubuntu' and $os_majrelease >= 22) or
            ($operatingsystem == 'Debian' and $os_majrelease >= 11)) {
          # Needs ondrej/php PPA for PHP 7.4
          notice("${operatingsystem} ${operatingsystemmajrelease}: CCv1 needs PHP 7.4 via ondrej/php PPA.")
          exec { 'apt-update-for-php7-prep':
            path    => ['/bin', '/usr/bin'],
            command => 'apt-get update',
          }
          package { 'software-properties-common': ensure => installed }
          package { 'apt-transport-https':         ensure => installed }
          exec { 'add-apt-php7-repo':
            path    => ['/bin', '/usr/bin'],
            command => 'add-apt-repository -y ppa:ondrej/php',
            require => [
              Package['software-properties-common'],
              Package['apt-transport-https'],
            ],
          }
          $php_packages = [
            'php7.4-mysql', 'php7.4-gd', 'libapache2-mod-php7.4',
            'php7.4-curl', 'php7.4-ldap', 'php7.4-xml', 'php7.4-json',
          ]
        } else {
          $php_packages = [
            'php-mysql', 'php-gd', 'libapache2-mod-php',
            'php-curl', 'php-ldap', 'php-xml', 'php-json',
          ]
        }
      } else {
        $php_packages = []
      }

      # MySQL / MariaDB package selection
      # Ubuntu 24 (Noble) + Debian 10+: MariaDB is the preferred choice
      if ($operatingsystem == 'Debian' and $os_majrelease >= 10) {
        $mysql_packages = ['mariadb-client', 'mariadb-server']
        $mysql_service  = 'mariadb'
      } elsif ($operatingsystem == 'Ubuntu' and $os_majrelease >= 24) {
        # Ubuntu 24 Noble: mysql-server now ships as a snap; use mariadb instead
        $mysql_packages = ['mariadb-client', 'mariadb-server']
        $mysql_service  = 'mariadb'
      } else {
        $mysql_packages = ['mysql-client', 'mysql-server']
        $mysql_service  = 'mysql'
      }

      $cc_service_packages = [
        'clustercontrol-notifications', 'clustercontrol-ssh',
        'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools',
      ]

      if ($online_install) {
        $cc_dependencies = [
          'apache2', 'wget', 'mailutils', 'curl', 'dnsutils', 'dmidecode',
        ] + $php_packages + $cc_service_packages
      } else {
        $cc_dependencies = [
          'apache2', 'wget', 'mailutils', 'curl', 'dnsutils', 'dmidecode',
        ] + $php_packages
      }

      # Apache / filesystem paths
      $apache_log_dir                     = '/var/log/apache2/'
      $wwwroot                            = '/var/www/html'
      $apache_conf_file                   = '/etc/apache2/apache2.conf'
      $apache_s9s_conf_file               = '/etc/apache2/sites-available/s9s.conf'
      $apache_s9s_target_file             = '/etc/apache2/sites-enabled/001-s9s.conf'
      $apache_s9s_ssl_conf_file           = '/etc/apache2/sites-available/s9s-ssl.conf'
      $apache_s9s_ssl_target_file         = '/etc/apache2/sites-enabled/001-s9s-ssl.conf'
      $apache_s9s_cc_frontend_conf_file   = '/etc/apache2/sites-available/cc-frontend.conf'
      $apache_s9s_cc_frontend_target_file = '/etc/apache2/sites-enabled/cc-frontend.conf'
      $apache_s9s_cc_proxy_conf_file      = '/etc/apache2/sites-available/cc-proxy.conf'
      $apache_s9s_cc_proxy_target_file    = '/etc/apache2/sites-enabled/cc-proxy.conf'
      $apache_security_conf_file          = '/etc/apache2/conf-available/security.conf'
      $apache_security_target_conf_file   = '/etc/apache2/conf-enabled/security.conf'
      $apache_mods_header_file            = '/etc/apache2/mods-available/headers.load'
      $apache_mods_header_target_file     = '/etc/apache2/mods-enabled/headers.load'
      $cert_file                          = '/etc/ssl/certs/s9server.crt'
      $key_file                           = '/etc/ssl/private/s9server.key'
      $apache_user                        = 'www-data'
      $apache_service                     = 'apache2'
      $mysql_cnf                          = '/etc/mysql/my.cnf'
      $repo_source                        = '/etc/apt/sources.list.d/s9s-repo.list'
      $repo_tools_src                     = '/etc/apt/sources.list.d/s9s-tools.list'

      # Modern APT keyring path (replaces deprecated apt-key on Ubuntu 22+ / Debian 12+)
      $apt_keyrings_dir = '/etc/apt/keyrings'

      # Remove stale default Apache vhosts
      file {
        [
          '/etc/apache2/sites-enabled/000-default.conf',
          '/etc/apache2/sites-enabled/default-ssl.conf',
          '/etc/apache2/sites-enabled/001-default-ssl.conf',
        ]:
          ensure  => absent,
          require => Package[$cc_dependencies],
      }

      if ($online_install) {

        # Ensure /etc/apt/keyrings exists (Ubuntu 22+ / Debian 12+ requirement)
        exec { 'create-apt-keyrings-dir':
          path    => ['/bin', '/usr/bin'],
          command => "mkdir -p ${apt_keyrings_dir}",
          unless  => "test -d ${apt_keyrings_dir}",
        }

        package { 'gpg': ensure => installed }

        # Import Severalnines repo signing key (modern method: file in keyrings/)
        exec { 'import-severalnines-key':
          path    => ['/bin', '/usr/bin'],
          command => "wget -qO ${apt_keyrings_dir}/severalnines-repos.asc http://${repo_host}/severalnines-repos.asc",
          unless  => "test -f ${apt_keyrings_dir}/severalnines-repos.asc",
          require => [Package['gpg'], Exec['create-apt-keyrings-dir']],
        }

        # Import s9s-tools repo signing key
        exec { 'import-severalnines-tools-key':
          path    => ['/bin', '/usr/bin'],
          command => "wget -qO ${apt_keyrings_dir}/severalnines-tools.asc http://${repo_host}/s9s-tools/${lsbdistcodename}/Release.key",
          unless  => "test -f ${apt_keyrings_dir}/severalnines-tools.asc",
          require => [Package['gpg'], Exec['create-apt-keyrings-dir']],
        }

        exec { 'apt-update-severalnines':
          path        => ['/bin', '/usr/bin'],
          command     => 'apt-get update',
          require     => [File[$repo_source], File[$repo_tools_src]],
          refreshonly => true,
        }

        file { $repo_source:
          content => template('clustercontrol/s9s-repo.list.erb'),
          require => Exec['import-severalnines-key'],
          notify  => Exec['apt-update-severalnines'],
        }

        file { $repo_tools_src:
          content => template('clustercontrol/s9s-tools.list.erb'),
          require => Exec['import-severalnines-tools-key'],
          notify  => Exec['apt-update-severalnines'],
        }

        $severalnines_repo = Exec['apt-update-severalnines']
      }
    }

    # =========================================================================
    # SUSE family  (SLES / OpenSUSE >= 15)
    # Requires the puppet-zypprepo module on the Puppet master
    # =========================================================================
    'Suse': {

      if (Integer($operatingsystemmajrelease) < 15) {
        fail("ClusterControl requires SUSE >= 15. Version ${operatingsystemmajrelease} is not supported.")
      }

      if ($operatingsystemmajrelease == '15') {
        $s9s_tools_repo_osname = "${operatingsystemrelease}"
      } else {
        $s9s_tools_repo_osname = "${operatingsystem}_${operatingsystemrelease}"
      }

      if ($only_cc_v2) {
        $php_packages = []
      } else {
        $php_packages = [
          'php7', 'php7-mysql', 'apache2-mod_php7', 'php7-gd',
          'php7-curl', 'php7-ldap', 'php7-xmlreader', 'php7-ctype', 'php7-json',
        ]
      }

      $cc_service_packages = [
        'clustercontrol-notifications', 'clustercontrol-ssh',
        'clustercontrol-cloud', 'clustercontrol-clud', 's9s-tools',
      ]

      $loc_dependencies = [
        'apache2', 'wget', 'mailx', 'curl', 'cronie', 'bind-utils',
        'insserv-compat', 'sysvinit-tools', 'openssl', 'ca-certificates',
        'gnuplot', 'expect', 'perl-XML-XPath', 'psmisc', 'dmidecode',
      ]

      $cc_dependencies = $loc_dependencies + $php_packages + $cc_service_packages

      $apache_s9s_conf_file             = '/etc/apache2/vhosts.d/s9s.conf'
      $apache_s9s_ssl_conf_file         = '/etc/apache2/vhosts.d/ssl.conf'
      $apache_s9s_cc_frontend_conf_file = '/etc/apache2/vhosts.d/cc-frontend.conf'
      $apache_s9s_cc_proxy_conf_file    = '/etc/apache2/vhosts.d/cc-proxy.conf'
      $cert_file                        = '/etc/ssl/certs/s9server.crt'
      $key_file                         = '/etc/ssl/private/s9server.key'
      $apache_user                      = 'wwwrun'
      $apache_service                   = 'apache2'
      $apache_log_dir                   = '/var/log/apache2/'
      $wwwroot                          = '/var/www/html'
      $mysql_cnf                        = '/etc/my.cnf'
      $mysql_service                    = 'mariadb'
      $mysql_packages                   = ['mariadb', 'mariadb-client']

      if ($online_install) {
        zypprepo { 's9s-repo':
          descr    => 'Severalnines Repository',
          baseurl  => "http://${repo_host}/rpm/os/x86_64",
          enabled  => 1,
          gpgkey   => "http://${repo_host}/severalnines-repos.asc",
          gpgcheck => 1,
        }
        zypprepo { 's9s-tools-repo':
          descr    => "s9s-tools - ${s9s_tools_repo_osname}",
          baseurl  => "http://${repo_host}/s9s-tools/${s9s_tools_repo_osname}",
          enabled  => 1,
          gpgkey   => "http://${repo_host}/s9s-tools/${s9s_tools_repo_osname}/repodata/repomd.xml.key",
          gpgcheck => 1,
        }
      }
    }

    default: {
      fail("Unsupported OS family '${osfamily}'. Supported: RedHat (EL 7-9), Debian/Ubuntu, Suse (15+).")
    }
  }
}
