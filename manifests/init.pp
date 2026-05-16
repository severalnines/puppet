# Class: clustercontrol
#
# Installs and configures Severalnines ClusterControl (CC 2.4.x compatible).
# Supports: EL 7/8/9, Ubuntu 18/20/22/24, Debian 9/10/11/12, SLES 15+
#
# Parameters:
#   is_controller           - true  = this node is the CC controller
#   cc_hostname             - IP or FQDN of the CC node (mandatory)
#   api_token               - 40-char RPC token (generate with s9s_helper.sh)
#   ssh_user                - SSH user CC uses to reach DB nodes (default: root)
#   mysql_root_password     - MySQL root password set during install
#   mysql_cmon_password     - Password for the 'cmon' MySQL user
#   only_cc_v2              - true (default) = CCv2 only; false = CCv1 + CCv2
#   is_online_install       - true (default) = pull from internet repo
#   disable_firewall        - true (default) = flush iptables / stop ufw/firewalld
#   disable_os_sec_module   - true (default) = disable SELinux / AppArmor
#
class clustercontrol (
  Boolean $is_controller          = true,
  String  $clustercontrol_host    = '',
  String  $cc_hostname            = $cc_hostname,
  String  $api_token              = '',
  String  $ssh_user               = 'root',
  String  $ssh_user_group         = 'root',
  String  $ssh_port               = '22',
  String  $ssh_key_type           = 'ssh-rsa',
  String  $ssh_key                = '',
  Optional[String] $ssh_opts      = undef,
  Optional[String] $sudo_password = undef,
  String  $mysql_server_addresses = '',
  String  $mysql_root_password    = 'R00tP@55',
  String  $mysql_cmon_password    = 'userP@55',
  String  $mysql_cmon_port        = '3306',
  String  $mysql_basedir          = '',
  String  $modulepath             = '/etc/puppetlabs/code/environments/production/modules/clustercontrol/',
  String  $datadir                = '/var/lib/mysql',
  Boolean $use_repo               = true,
  Boolean $disable_firewall       = true,
  Boolean $disable_os_sec_module  = true,
  String  $controller_id          = '',
  Boolean $is_online_install      = true,

  # Offline installation: full local paths to each CC package file
  Hash    $cc_packages_path = {
    'clustercontrol-controller'   => '',
    'clustercontrol'              => '',
    'clustercontrol-mcc'          => '',
    'clustercontrol-cloud'        => '',
    'clustercontrol-clud'         => '',
    'clustercontrol-ssh'          => '',
    'clustercontrol-notifications'=> '',
    'clustercontrol-proxy'        => '',
    'clustercontrol-kuber-proxy'  => '',
    'libs9s'                      => '',
    's9s-tools'                   => '',
  },

  Boolean $enabled       = true,
  String  $ccsetup_email = 'admin@clustercontrol.com',

  # only_cc_v2:
  #   true  (default) = install CCv2 only (no PHP required)
  #   false           = install CCv1 + CCv2 (legacy; PHP 7.4 required)
  Boolean $only_cc_v2 = true,

) {

  # --------------------------------------------------------------------------
  # Resolve service state
  # --------------------------------------------------------------------------
  if $enabled {
    $service_status = 'running'
  } else {
    $service_status = 'stopped'
  }

  # --------------------------------------------------------------------------
  # SSH user paths & sudo handling
  # --------------------------------------------------------------------------
  if ($ssh_user == 'root') {
    $user_home          = '/root'
    $real_sudo_password = undef
  } else {
    $user_home   = "/home/${ssh_user}"
    $rssh_opts   = '-nqtt'
    if ($sudo_password != undef) {
      $real_sudo_password = "echo ${sudo_password} | sudo -S"
    } else {
      $real_sudo_password = 'sudo'
    }
  }

  if ($ssh_key == '') {
    $ssh_identity     = "${user_home}/.ssh/id_rsa_s9s"
    $ssh_identity_pub = "${user_home}/.ssh/id_rsa_s9s.pub"
  } else {
    $ssh_identity     = "${user_home}/.ssh/id_rsa"
    $ssh_identity_pub = "${user_home}/.ssh/id_rsa.pub"
  }

  $backup_dir  = "${user_home}/backups"
  $staging_dir = "${user_home}/s9s_tmp"

  # --------------------------------------------------------------------------
  # Controller ID
  # --------------------------------------------------------------------------
  if (empty($controller_id)) {
    $l_controller_id = $facts['controller_id']
  } else {
    $l_controller_id = $controller_id
  }

  # --------------------------------------------------------------------------
  # Helpers
  # --------------------------------------------------------------------------
  $l_osfamily = downcase($facts['os']['family'])

  if empty($mysql_basedir) {
    Exec { path => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'] }
  } else {
    Exec { path => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin', "${mysql_basedir}/bin"] }
  }

  # CCv2-only → port 443 for the frontend; legacy CCv1+CCv2 → 9443
  if ($only_cc_v2) {
    $cc_frontend_ssl_port = 443
  } else {
    $cc_frontend_ssl_port = 9443
  }

  # ==========================================================================
  # CONTROLLER NODE
  # ==========================================================================
  if $is_controller {

    class { 'clustercontrol::params':
      online_install => $is_online_install,
      only_cc_v2     => $only_cc_v2,
    }

    # ------------------------------------------------------------------------
    # Firewall
    # ------------------------------------------------------------------------
    if ($disable_firewall) {
      exec { 'check-iptables-presence':
        command => 'iptables -L',
        onlyif  => 'which iptables',
      }
      exec { 'disable-iptables-firewall':
        command => 'iptables -F',
        onlyif  => 'which iptables',
        require => Exec['check-iptables-presence'],
      }
      service { 'iptables':
        enable  => false,
        ensure  => stopped,
        require => Exec['check-iptables-presence'],
      }
    }

    # ------------------------------------------------------------------------
    # SELinux / AppArmor
    # ------------------------------------------------------------------------
    if ($l_osfamily == 'redhat' or $l_osfamily == 'suse') {
      if ($disable_os_sec_module) {
        file { '/etc/selinux/config':
          ensure       => file,
          content      => template('clustercontrol/selinux-config.erb'),
          owner        => 'root',
          group        => 'root',
          mode         => '0644',
          validate_cmd => 'test -f /etc/selinux/config',
        }
        exec { 'disable-os-security-module':
          onlyif  => 'which getenforce && /usr/sbin/getenforce | grep -i enforcing',
          command => 'setenforce 0',
          require => File['/etc/selinux/config'],
        }
      }
      if ($disable_firewall) {
        # Stop firewalld only if it is installed AND active
        # firewall-cmd --stat returns 252 when firewalld is not running - not an error
        exec { 'check-firewalld-presence':
          onlyif  => 'systemctl is-active firewalld',
          command => 'systemctl stop firewalld && systemctl disable firewalld',
          path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
        }
      }
    } elsif ($l_osfamily == 'debian') {
      if ($disable_os_sec_module) {
        exec { 'disable-os-security-module':
          onlyif  => 'which apparmor_status',
          command => '/etc/init.d/apparmor stop; /etc/init.d/apparmor teardown; update-rc.d -f apparmor remove',
        }
      }
      if ($disable_firewall) {
        service { 'ufw':
          ensure => stopped,
          enable => false,
        }
      }
    }

    # ------------------------------------------------------------------------
    # MySQL / MariaDB
    # ------------------------------------------------------------------------
    if ($l_osfamily == 'suse') {
      package { $clustercontrol::params::mysql_packages:
        ensure  => installed,
        require => [
          Zypprepo['s9s-repo'],
          Zypprepo['s9s-tools-repo'],
          Exec['refresh-zypper-auto-import-refresh'],
        ],
      }
      exec { 'refresh-zypper-auto-import-refresh':
        command => 'zypper -n --gpg-auto-import-keys refresh 2>/dev/null',
      }
    } else {
      package { $clustercontrol::params::mysql_packages:
        ensure => installed,
      }
    }

    file { $datadir:
      ensure  => directory,
      owner   => mysql,
      group   => mysql,
      require => Package[$clustercontrol::params::mysql_packages],
      notify  => Service[$clustercontrol::params::mysql_service],
    }

    file { $clustercontrol::params::mysql_cnf:
      ensure  => file,
      force   => true,
      content => template('clustercontrol/my.cnf.erb'),
      owner   => root,
      group   => root,
      mode    => '0644',
      require => Package[$clustercontrol::params::mysql_packages],
      notify  => Service[$clustercontrol::params::mysql_service],
    }

    service { $clustercontrol::params::mysql_service:
      ensure     => running,
      enable     => true,
      hasrestart => true,
      hasstatus  => true,
      require    => [
        Package[$clustercontrol::params::mysql_packages],
        File[$datadir],
      ],
      subscribe  => File[$clustercontrol::params::mysql_cnf],
    }

    exec { 'create-root-password':
      onlyif  => 'mysqladmin -u root status',
      command => "mysqladmin -u root password \"${mysql_root_password}\"",
    }

    # cmon DB grants
    exec { 'grant-cmon-localhost':
      unless   => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -hlocalhost status",
      command  => "mysql -u root -p\"${mysql_root_password}\" -e \"CREATE USER IF NOT EXISTS 'cmon'@'localhost' IDENTIFIED BY '${mysql_cmon_password}'; GRANT ALL PRIVILEGES ON *.* TO 'cmon'@'localhost' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      provider => shell,
    }
    exec { 'grant-cmon-127.0.0.1':
      unless   => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h127.0.0.1 status",
      command  => "mysql -u root -p\"${mysql_root_password}\" -e \"CREATE USER IF NOT EXISTS 'cmon'@'127.0.0.1' IDENTIFIED BY '${mysql_cmon_password}'; GRANT ALL PRIVILEGES ON *.* TO 'cmon'@'127.0.0.1' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      provider => shell,
    }
    exec { 'grant-cmon-ip-address':
      unless   => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h\"${cc_hostname}\" status",
      command  => "mysql -u root -p\"${mysql_root_password}\" -e \"CREATE USER IF NOT EXISTS 'cmon'@'${cc_hostname}' IDENTIFIED BY '${mysql_cmon_password}'; GRANT ALL PRIVILEGES ON *.* TO 'cmon'@'${cc_hostname}' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      provider => shell,
    }
    # Use CREATE USER + GRANT in separate calls to avoid MariaDB ERROR 1133
    # The combined statement fails in some MariaDB versions on FLUSH PRIVILEGES
    exec { 'grant-cmon-fqdn-create':
      unless   => "mysql -u root -p\"${mysql_root_password}\" -e \"SELECT 1 FROM mysql.user WHERE user='cmon' AND host='${facts['networking']['fqdn']}'\" | grep -q 1",
      command  => "mysql -u root -p\"${mysql_root_password}\" -e \"CREATE USER IF NOT EXISTS 'cmon'@'${facts['networking']['fqdn']}' IDENTIFIED BY '${mysql_cmon_password}';\"",
      provider => shell,
    }
    exec { 'grant-cmon-fqdn-grant':
      unless   => "mysqladmin -u cmon -p\"${mysql_cmon_password}\" -h\"${facts['networking']['fqdn']}\" status",
      command  => "mysql -u root -p\"${mysql_root_password}\" -e \"GRANT ALL PRIVILEGES ON *.* TO 'cmon'@'${facts['networking']['fqdn']}' WITH GRANT OPTION; FLUSH PRIVILEGES;\"",
      provider => shell,
      require  => Exec['grant-cmon-fqdn-create'],
    }

    # ------------------------------------------------------------------------
    # Install ClusterControl dependencies + packages
    # ------------------------------------------------------------------------
    package { $clustercontrol::params::cc_dependencies:
      ensure => installed,
    }

    if ($is_online_install) {

      # CCv1 legacy UI (only when requested)
      if ($only_cc_v2 == false) {
        package { $clustercontrol::params::cc_ui:
          ensure  => installed,
          require => Package[$clustercontrol::params::cc_controller],
        }
      }

      # CCv2 UI  (clustercontrol-mcc)
      package { $clustercontrol::params::cc_ui2:
        ensure  => installed,
        require => Package[$clustercontrol::params::cc_controller],
      }

      # New CC 2.x services
      package { $clustercontrol::params::cc_proxy:
        ensure  => installed,
        require => Package[$clustercontrol::params::cc_ui2],
      }
      package { $clustercontrol::params::cc_kuber_proxy:
        ensure  => installed,
        require => Package[$clustercontrol::params::cc_proxy],
      }

      if ($l_osfamily == 'suse') {
        package { $clustercontrol::params::cc_controller:
          ensure  => installed,
          require => [
            Zypprepo['s9s-repo'],
            Zypprepo['s9s-tools-repo'],
            Package[$clustercontrol::params::cc_dependencies],
          ],
        }
      } else {
        package { $clustercontrol::params::cc_controller:
          ensure  => installed,
          require => [
            $clustercontrol::params::severalnines_repo,
            Package[$clustercontrol::params::cc_dependencies],
          ],
        }
      }

    } else {
      # ---- Offline installation --------------------------------------------
      if ($l_osfamily == 'redhat' or $l_osfamily == 'suse') {
        $l_provider     = 'rpm'
        $l_provider_pkg = 'rpm'
      } elsif ($l_osfamily == 'debian') {
        $l_provider     = 'apt'
        $l_provider_pkg = 'dpkg'
      } else {
        fail('Offline install not supported for this OS family.')
      }

      package { $clustercontrol::params::cc_cloud:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_cloud],
        require  => Package[$clustercontrol::params::cc_dependencies],
      }
      package { $clustercontrol::params::cc_clud:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_clud],
        require  => Package[$clustercontrol::params::cc_cloud],
      }
      package { $clustercontrol::params::cc_ssh:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_ssh],
        require  => Package[$clustercontrol::params::cc_clud],
      }
      package { $clustercontrol::params::cc_notif:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_notif],
        require  => Package[$clustercontrol::params::cc_ssh],
      }

      if ($l_osfamily == 'debian') {
        package { $clustercontrol::params::libs9s:
          ensure   => installed,
          provider => $l_provider_pkg,
          source   => $cc_packages_path[$clustercontrol::params::libs9s],
          require  => Package[$clustercontrol::params::cc_notif],
        }
        package { $clustercontrol::params::s9stools:
          ensure   => installed,
          provider => $l_provider,
          source   => $cc_packages_path[$clustercontrol::params::s9stools],
          require  => Package[$clustercontrol::params::libs9s],
        }
      } else {
        package { $clustercontrol::params::s9stools:
          ensure   => installed,
          provider => $l_provider,
          source   => $cc_packages_path[$clustercontrol::params::s9stools],
          require  => Package[$clustercontrol::params::cc_notif],
        }
      }

      if ($only_cc_v2 == false) {
        package { $clustercontrol::params::cc_ui:
          ensure   => installed,
          provider => $l_provider,
          source   => $cc_packages_path[$clustercontrol::params::cc_ui],
          require  => Package[$clustercontrol::params::s9stools],
        }
      }

      package { $clustercontrol::params::cc_ui2:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_ui2],
        require  => Package[$clustercontrol::params::s9stools],
      }

      package { $clustercontrol::params::cc_proxy:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_proxy],
        require  => Package[$clustercontrol::params::cc_ui2],
      }

      package { $clustercontrol::params::cc_kuber_proxy:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_kuber_proxy],
        require  => Package[$clustercontrol::params::cc_proxy],
      }

      package { $clustercontrol::params::cc_controller:
        ensure   => installed,
        provider => $l_provider,
        source   => $cc_packages_path[$clustercontrol::params::cc_controller],
        require  => Package[$clustercontrol::params::cc_kuber_proxy],
      }
    }

    # ------------------------------------------------------------------------
    # SSL certificate generation
    # ------------------------------------------------------------------------
    class { 'clustercontrol::create_cert':
      cert_file => $clustercontrol::params::cert_file,
      key_file  => $clustercontrol::params::key_file,
    }

    # ------------------------------------------------------------------------
    # Apache configuration (OS-specific)
    # ------------------------------------------------------------------------
    $wwwroot                    = $clustercontrol::params::wwwroot
    $apache_httpd_extra_options = $clustercontrol::params::apache_httpd_extra_options
    $cert_file                  = $clustercontrol::params::cert_file
    $key_file                   = $clustercontrol::params::key_file

    if $l_osfamily == 'redhat' {

      if ($only_cc_v2 == false) {
        file { $clustercontrol::params::apache_s9s_conf_file:
          ensure  => present,
          mode    => '0644',
          owner   => root, group => root,
          content => template('clustercontrol/s9s.conf.erb'),
          require => Package[$clustercontrol::params::cc_dependencies],
        }
        file { $clustercontrol::params::apache_s9s_ssl_conf_file:
          ensure  => present,
          mode    => '0644',
          owner   => root, group => root,
          content => template('clustercontrol/s9s-ssl.conf.erb'),
          require => Package[$clustercontrol::params::cc_dependencies],
        }
        exec { 'enable-ssl-port':
          unless  => "grep -q 'Listen 443' ${clustercontrol::params::apache_conf_file}",
          command => "sed -i '1s|^|Listen 443\\n|' ${clustercontrol::params::apache_conf_file}",
          require => File[$clustercontrol::params::apache_s9s_conf_file],
        }
        exec { 'enable-ssl-servername-localhost':
          unless  => "grep -q 'ServerName 127.0.0.1' ${clustercontrol::params::apache_conf_file}",
          command => "sed -i '1s|^|ServerName 127.0.0.1\\n|' ${clustercontrol::params::apache_conf_file}",
          require => File[$clustercontrol::params::apache_s9s_conf_file],
        }
      }

      file { $clustercontrol::params::apache_s9s_cc_frontend_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-frontend.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
      }
      file { $clustercontrol::params::apache_s9s_cc_proxy_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-proxy.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
      }
      file { $clustercontrol::params::apache_security_conf_file:
        ensure  => present,
        owner   => root, group => root,
        content => template('clustercontrol/s9s-security.conf.erb'),
        require => Package[$clustercontrol::params::cc_dependencies],
      }

    } elsif $l_osfamily == 'debian' {

      if ($only_cc_v2 == false) {
        file { $clustercontrol::params::apache_s9s_ssl_conf_file:
          ensure  => present,
          content => template('clustercontrol/s9s-ssl.conf.erb'),
          mode    => '0644',
          owner   => root, group => root,
          require => Package[$clustercontrol::params::cc_ui],
          notify  => File[$clustercontrol::params::apache_s9s_ssl_target_file],
        }
        file { $clustercontrol::params::apache_s9s_ssl_target_file:
          ensure    => link,
          target    => $clustercontrol::params::apache_s9s_ssl_conf_file,
          subscribe => File[$clustercontrol::params::apache_s9s_ssl_conf_file],
        }
        file { $clustercontrol::params::apache_s9s_conf_file:
          ensure  => present,
          content => template('clustercontrol/s9s.conf.erb'),
          mode    => '0644',
          owner   => root, group => root,
          require => Package[$clustercontrol::params::cc_ui],
          notify  => File[$clustercontrol::params::apache_s9s_target_file],
        }
        file { $clustercontrol::params::apache_s9s_target_file:
          ensure    => link,
          target    => $clustercontrol::params::apache_s9s_conf_file,
          subscribe => File[$clustercontrol::params::apache_s9s_conf_file],
        }
      }

      file { $clustercontrol::params::apache_s9s_cc_frontend_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-frontend.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
        notify  => File[$clustercontrol::params::apache_s9s_cc_frontend_target_file],
      }
      file { $clustercontrol::params::apache_s9s_cc_frontend_target_file:
        ensure    => link,
        target    => $clustercontrol::params::apache_s9s_cc_frontend_conf_file,
        subscribe => File[$clustercontrol::params::apache_s9s_cc_frontend_conf_file],
      }
      file { $clustercontrol::params::apache_s9s_cc_proxy_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-proxy.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
        notify  => File[$clustercontrol::params::apache_s9s_cc_proxy_target_file],
      }
      file { $clustercontrol::params::apache_s9s_cc_proxy_target_file:
        ensure    => link,
        target    => $clustercontrol::params::apache_s9s_cc_proxy_conf_file,
        subscribe => File[$clustercontrol::params::apache_s9s_cc_proxy_conf_file],
      }
      file { $clustercontrol::params::apache_mods_header_target_file:
        ensure  => link,
        target  => $clustercontrol::params::apache_mods_header_file,
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      exec { 'enable-securityconf-sameorigin':
        unless  => "grep -q '^Header set X-Frame-Options' ${clustercontrol::params::apache_security_conf_file}",
        command => "sed -i 's|\\#Header set X-Frame-Options: \"sameorigin\"|Header set X-Frame-Options: \"sameorigin\"|' ${clustercontrol::params::apache_security_conf_file}",
        require => File[$clustercontrol::params::apache_mods_header_target_file],
      }
      exec { 'enable-apache-modules':
        command => 'a2enmod ssl rewrite proxy proxy_http proxy_wstunnel headers',
        require => Package[$clustercontrol::params::cc_dependencies],
      }

    } elsif $l_osfamily == 'suse' {

      if ($only_cc_v2 == false) {
        file { $clustercontrol::params::apache_s9s_ssl_conf_file:
          ensure  => present,
          content => template('clustercontrol/s9s-ssl.conf.erb'),
          mode    => '0644',
          owner   => root, group => root,
          require => Package[$clustercontrol::params::cc_ui],
        }
        file { $clustercontrol::params::apache_s9s_conf_file:
          ensure  => present,
          content => template('clustercontrol/s9s.conf.erb'),
          mode    => '0644',
          owner   => root, group => root,
          require => Package[$clustercontrol::params::cc_ui],
        }
      }

      file { $clustercontrol::params::apache_s9s_cc_frontend_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-frontend.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
      }
      file { $clustercontrol::params::apache_s9s_cc_proxy_conf_file:
        ensure  => present,
        content => template('clustercontrol/cc-proxy.conf.erb'),
        mode    => '0644',
        owner   => root, group => root,
        require => Package[$clustercontrol::params::cc_ui2],
      }
      exec { 'enable-apache-modules':
        command => 'a2enmod ssl rewrite headers proxy proxy_http proxy_wstunnel',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      file_line { 'enable-apache-php':
        path    => '/etc/apache2/mod_mime-defaults.conf',
        line    => 'AddType application/x-httpd-php .php',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      file_line { 'enable-apache-proxy_module':
        path    => '/etc/apache2/loadmodule.conf',
        line    => 'LoadModule proxy_module modules/mod_proxy.so',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      file_line { 'enable-apache-proxy_http_module':
        path    => '/etc/apache2/loadmodule.conf',
        line    => 'LoadModule proxy_http_module modules/mod_proxy_http.so',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      file_line { 'enable-apache-proxy_wstunnel_module':
        path    => '/etc/apache2/loadmodule.conf',
        line    => 'LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
      file_line { 'enable-SSL-flag-for-apache2':
        path    => '/etc/sysconfig/apache2',
        line    => 'APACHE_SERVER_FLAGS="SSL"',
        require => Package[$clustercontrol::params::cc_dependencies],
      }
    }

    # ------------------------------------------------------------------------
    # SSH keys for ClusterControl → DB nodes
    # ------------------------------------------------------------------------
    file { $ssh_identity:
      ensure => present,
      owner  => $ssh_user,
      group  => $ssh_user_group,
      mode   => '0600',
      source => 'puppet:///modules/clustercontrol/id_rsa_s9s',
    }
    file { $ssh_identity_pub:
      ensure => present,
      owner  => $ssh_user,
      group  => $ssh_user_group,
      mode   => '0644',
      source => 'puppet:///modules/clustercontrol/id_rsa_s9s.pub',
    }

    # ------------------------------------------------------------------------
    # /etc/default/cmon  (required by cmon-events and cmon-cloud)
    # ------------------------------------------------------------------------
    file { $clustercontrol::params::cmon_default_file:
      ensure  => file,
      content => template('clustercontrol/cmon_default.erb'),
      owner   => root,
      group   => root,
      mode    => '0644',
      require => Package[$clustercontrol::params::cc_controller],
    }

    # ------------------------------------------------------------------------
    # CMON initialisation (replaces raw cmon.cnf template write)
    # cmon --init writes /etc/cmon.cnf and bootstraps the schema
    # ------------------------------------------------------------------------
    exec { 'cmon-init':
      command => "cmon --init \
        --mysql-hostname=\"127.0.0.1\" \
        --mysql-port=\"${mysql_cmon_port}\" \
        --mysql-username=\"cmon\" \
        --mysql-password=\"${mysql_cmon_password}\" \
        --mysql-database=\"cmon\" \
        --hostname=\"${cc_hostname}\" \
        --rpc-token=\"${api_token}\" \
        --controller-id=\"${l_controller_id}\"",
      unless  => 'test -f /etc/cmon.cnf',
      require => [
        Package[$clustercontrol::params::cc_controller],
        File[$clustercontrol::params::cmon_default_file],
        Service[$clustercontrol::params::mysql_service],
        Exec['grant-cmon-localhost'],
        Exec['grant-cmon-127.0.0.1'],
        Exec['grant-cmon-ip-address'],
        Exec['grant-cmon-fqdn-grant'],
      ],
    }

    # ------------------------------------------------------------------------
    # ccmgradm initialises the web application (CCv2 GUI)
    # ------------------------------------------------------------------------
    exec { 'ccmgradm-init':
      command => "ccmgradm init --local-cmon -p 443 -f ${clustercontrol::params::cc_v2_webroot}",
      unless  => "test -f ${clustercontrol::params::cc_v2_config_ui_file}",
      require => [
        Package[$clustercontrol::params::cc_ui2],
        Exec['cmon-init'],
      ],
    }

    # Fix permissions on the web root (755 required by cmon-proxy)
    exec { 'fix-cc-webroot-permissions':
      command => "chmod 755 /var /var/www /var/www/html ${clustercontrol::params::cc_v2_webroot}",
      unless  => "stat -c '%a' ${clustercontrol::params::cc_v2_webroot} | grep -q '755'",
      require => Exec['ccmgradm-init'],
    }

    # ------------------------------------------------------------------------
    # Start all CC services
    # Order: DB → cmon → cmon-{ssh,events,cloud} → cmon-proxy → kuber-proxy → apache
    # ------------------------------------------------------------------------
    service { 'cmon':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => Exec['cmon-init'],
    }

    service { 'cmon-ssh':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => Service['cmon'],
    }

    service { 'cmon-events':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => Service['cmon'],
    }

    service { 'cmon-cloud':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => Service['cmon'],
    }

    service { 'cmon-proxy':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => [
        Service['cmon'],
        Package[$clustercontrol::params::cc_proxy],
        Exec['ccmgradm-init'],
        Exec['fix-cc-webroot-permissions'],
      ],
    }

    service { 'kuber-proxy':
      ensure     => $service_status,
      enable     => $enabled,
      hasrestart => true,
      hasstatus  => true,
      require    => [
        Service['cmon-proxy'],
        Package[$clustercontrol::params::cc_kuber_proxy],
      ],
    }

    # CCv1 bootstrap (only when running legacy CCv1+CCv2 mode)
    if ($only_cc_v2 == false) {
      exec { 'configure-cc-bootstrap':
        command => "sed -i 's|DBPASS|${mysql_cmon_password}|g' ${wwwroot}/clustercontrol/bootstrap.php && \
          sed -i 's|DBPORT|${mysql_cmon_port}|g' ${wwwroot}/clustercontrol/bootstrap.php",
        require => Package[$clustercontrol::params::cc_controller],
      }
      exec { 'configure-cmonapi-bootstrap':
        command => "sed -i 's|RPCTOKEN|${api_token}|g' ${wwwroot}/clustercontrol/bootstrap.php",
        require => Package[$clustercontrol::params::cc_controller],
      }
      file { "${wwwroot}/clustercontrol/bootstrap.php":
        ensure  => present,
        replace => no,
        source  => "${wwwroot}/clustercontrol/bootstrap.php.default",
        require => Package[$clustercontrol::params::cc_ui],
        notify  => Exec[['configure-cmonapi-bootstrap', 'configure-cc-bootstrap']],
      }
    }

    # ------------------------------------------------------------------------
    # Apache web server
    # ------------------------------------------------------------------------
    # In CC 2.4.x with only_cc_v2=true, cmon-proxy (ccmgr) IS the web server
    # and listens on 80/443 directly. Apache is only required for legacy CCv1.
    # See: https://docs.severalnines.com/clustercontrol/latest/reference-manuals/components/clustercontrol-proxy/
    if (!$only_cc_v2) {
      service { $clustercontrol::params::apache_service:
        ensure     => $service_status,
        enable     => $enabled,
        hasrestart => true,
        hasstatus  => true,
        require    => [
          Service['cmon-proxy'],
          File[$clustercontrol::params::apache_s9s_cc_frontend_conf_file],
          File[$clustercontrol::params::apache_s9s_cc_proxy_conf_file],
        ],
      }
    } else {
      # Ensure Apache is stopped and disabled - cmon-proxy owns the ports
      service { $clustercontrol::params::apache_service:
        ensure => stopped,
        enable => false,
      }
    }

    # Cmon upload schema directory (always needed)
    exec { 'create-cmon-upload-schema-directory':
      command => "mkdir -p ${clustercontrol::params::wwwroot}/cmon/upload/schema",
      require => [
        Package[$clustercontrol::params::cc_dependencies],
        File[$ssh_identity, $ssh_identity_pub],
      ],
    }

    # Ownership of web directories
    if ($only_cc_v2) {
      exec { 'change-owner-to-apache-user':
        command => "chown -R ${clustercontrol::params::apache_user}:${clustercontrol::params::apache_user} \
          ${clustercontrol::params::wwwroot}/cmon/ \
          ${clustercontrol::params::cc_v2_webroot}",
        require => [
          Package[$clustercontrol::params::cc_ui2],
          File[$ssh_identity, $ssh_identity_pub],
        ],
        notify  => Service['cmon'],
      }
    } else {
      exec { 'change-owner-to-apache-user':
        command => "chown -R ${clustercontrol::params::apache_user}:${clustercontrol::params::apache_user} \
          ${clustercontrol::params::wwwroot}/clustercontrol/app/tmp/ \
          ${clustercontrol::params::wwwroot}/clustercontrol/app/upload \
          ${clustercontrol::params::wwwroot}/cmon \
          ${clustercontrol::params::wwwroot}/clustercontrol \
          ${clustercontrol::params::cc_v2_webroot}",
        require => [
          Package[$clustercontrol::params::cc_ui],
          File[$ssh_identity, $ssh_identity_pub],
        ],
        notify  => Service['cmon'],
      }
    }

    # ------------------------------------------------------------------------
    # ClusterControl user setup
    # ------------------------------------------------------------------------
    # CC 2.4.x: Use ccmgradm to manage cmon-proxy users (replaces old s9s ccrpc/ccsetup)
    # See: https://docs.severalnines.com/clustercontrol/latest/reference-manuals/components/clustercontrol-proxy/
    $home_path = $ssh_user ? {
      'root'  => '/root',
      default => "/home/${ssh_user}",
    }
    $user_path = "${home_path}/.s9s/ccrpc.conf"

    file { "${home_path}/.s9s/":
      ensure  => directory,
      owner   => 'root',
      group   => 'root',
      mode    => '0700',
      require => Service['cmon'],
    }

    # ----- CCv2 user setup via ccmgradm (CC 2.4.x) -----
    if ($only_cc_v2) {
      # Create the initial admin user for cmon-proxy GUI
      # Default password 'admin' - user is prompted to change on first login
      exec { 'ccmgradm-add-admin-user':
        command  => "ccmgradm adduser --email '${ccsetup_email}' admin admin",
        provider => shell,
        unless   => "ccmgradm listusers 2>/dev/null | grep -qw admin",
        require  => [
          Service['cmon-proxy'],
          Exec['ccmgradm-init'],
        ],
      }
    } else {
      # ----- Legacy CCv1 user setup via s9s -----
      exec { 'create_ccrpc_user':
        command  => "S9S_USER_CONFIG=${user_path} s9s user --create --new-password=${api_token} --generate-key --private-key-file=/root/.s9s/ccrpc.key --group=admins --controller=https://127.0.0.1:9501 ccrpc",
        provider => shell,
        unless   => "S9S_USER_CONFIG=${user_path} s9s user --list 2>/dev/null | grep -q ccrpc",
        require  => [Service['cmon'], File["${home_path}/.s9s/"]],
      }

      exec { 'create_ccrpc_set_firstname':
        command  => "S9S_USER_CONFIG=${user_path} s9s user --set --first-name=RPC --last-name=API",
        provider => shell,
        unless   => "S9S_USER_CONFIG=${user_path} s9s user --list --long 2>/dev/null | grep -q RPC",
        require  => Exec['create_ccrpc_user'],
      }

      exec { 'ccsetup_unlink':
        command  => 'rm -f /tmp/ccsetup.conf',
        provider => shell,
        require  => [Exec['create_ccrpc_set_firstname'], Exec['create_ccrpc_user']],
      }

      exec { 'create_ccsetup_user':
        command  => "S9S_USER_CONFIG=/tmp/ccsetup.conf s9s user --create --new-password=admin --group=admins --email-address='${ccsetup_email}' --controller='https://127.0.0.1:9501' ccsetup",
        provider => shell,
        unless   => "S9S_USER_CONFIG=/tmp/ccsetup.conf s9s user --list 2>/dev/null | grep -q ccsetup",
        require  => [Service['cmon'], File["${home_path}/.s9s/"]],
      }
    }

  # ==========================================================================
  # DB NODE  (is_controller = false)
  # ==========================================================================
  } else {

    ssh_authorized_key { $ssh_user:
      ensure => present,
      key    => generate('/bin/bash', "${modulepath}/files/s9s_helper.sh", '--read-key', $modulepath),
      name   => "${ssh_user}@${clustercontrol_host}",
      user   => $ssh_user,
      type   => 'ssh-rsa',
      notify => Exec['grant-cmon-controller', 'grant-cmon-localhost', 'grant-cmon-127.0.0.1'],
    }

    exec { 'grant-cmon-controller':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"${clustercontrol_host}\" IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }
    exec { 'grant-cmon-localhost':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@localhost IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }
    exec { 'grant-cmon-127.0.0.1':
      onlyif  => 'which mysql',
      command => "mysql -u root -p\"${mysql_root_password}\" -e 'GRANT ALL PRIVILEGES ON *.* TO cmon@\"127.0.0.1\" IDENTIFIED BY \"${mysql_cmon_password}\" WITH GRANT OPTION; FLUSH PRIVILEGES;'",
    }
  }
}
