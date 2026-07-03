# == Class: clustercontrol::params
#
# Default values and OS-specific package/repo definitions for the ClusterControl
# Puppet module. Uses MySQL Community Server 8.4 LTS to match Severalnines'
# official cc-ansible reference implementation.
#
# Supports:
#   - RHEL/CentOS/Rocky/AlmaLinux 8, 9
#   - Ubuntu 20.04, 22.04, 24.04
#   - Debian 11, 12
#
class clustercontrol::params {

  # ==========================================================================
  # Common settings
  # ==========================================================================
  $repo_host = 'repo.severalnines.com'
  $gpg_key   = "https://${repo_host}/severalnines-repos.asc"

  # CC package groups
  $clustercontrol_ui_packages = [
    'clustercontrol-mcc',
    'clustercontrol-notifications',
    'clustercontrol-ssh',
    'clustercontrol-cloud',
    'clustercontrol-clud',
  ]

  $clustercontrol_controller_packages = [
    'clustercontrol-controller',
    'clustercontrol-proxy',
    'clustercontrol-kuber-proxy',
  ]

  $clustercontrol_cli_packages = ['s9s-tools']

  # Web / runtime paths
  $cmon_config_file  = '/etc/cmon.cnf'
  $cmon_default_file = '/etc/default/cmon'
  $cmon_sql_path     = '/usr/share/cmon'
  $cmon_state_dir    = '/var/lib/cmon'
  $cmon_init_marker  = "${cmon_state_dir}/.puppet-cmon-initialized"
  $mcc_init_marker   = "${cmon_state_dir}/.puppet-mcc-initialized"
  $mysql_init_marker = "${cmon_state_dir}/.puppet-mysql-initialized"
  $rpc_token_file    = "${cmon_state_dir}/cc_rpc_token"

  # MCC defaults
  $mcc_web_port = 443
  $mcc_web_root = '/var/www/html/clustercontrol-mcc'

  # MySQL data dir (common across OS families)
  $mysql_datadir = '/var/lib/mysql'

  # ==========================================================================
  # OS-family branching
  # ==========================================================================
  $os_family   = $facts['os']['family']
  $os_name     = $facts['os']['name']
  $os_major    = Integer(split($facts['os']['release']['full'], '[.]')[0])

  case $os_family {

    'RedHat': {
      # Version guard - EL8 and EL9 only (MySQL 8.4 not available for EL7)
      if ($os_major < 8 or $os_major > 9) {
        fail("ClusterControl on ${os_name} requires major version 8 or 9. Got: ${os_major}")
      }

      # MySQL Community Server 8.4 LTS (matches cc-ansible setup-RedHat.yml)
      # We explicitly switch away from MariaDB to avoid the well-known EL9
      # systemd cgroup tracking issue with mariadb.service that produces:
      #   "Will not start ... while processes exist"
      $mysql_packages = [
        'mysql-community-server',
        'mysql-community-client',
        'mysql-community-common',
        'mysql-community-libs',
      ]
      # MariaDB packages we explicitly remove (if present)
      $mariadb_packages_to_remove = [
        'mariadb-server',
        'mariadb',
        'mariadb-libs',
      ]
      $mysql_daemon            = 'mysqld'
      $mysql_config_file       = '/etc/my.cnf'
      $mysql_config_include_dir = '/etc/my.cnf.d'
      $mysql_socket            = '/var/lib/mysql/mysql.sock'
      $mysql_pid_file          = '/var/lib/mysql/mysql.pid'

      # MySQL 8.4 community repo
      $mysql_community_rpm = "https://repo.mysql.com/mysql84-community-release-el${os_major}-1.noarch.rpm"
      $mysql_gpg_key_url   = 'https://repo.mysql.com/RPM-GPG-KEY-mysql-2023'

      # Python MySQL client
      $python_mysql = 'python3-PyMySQL'

      # Repository paths
      $repo_config_dir       = '/etc/yum.repos.d'
      $repo_config_path      = '/etc/yum.repos.d/s9s-repo.repo'
      $repo_cli_config_path  = '/etc/yum.repos.d/s9s-tools.repo'
      $repo_config_url       = 'https://www.severalnines.com/downloads/cmon/s9s-repo.repo'

      # s9s-tools CLI repo
      $clustercontrol_cli_repository = "https://${repo_host}/s9s-tools/RHEL_${os_major}/s9s-tools.repo"

      $apache_service = 'httpd'
      $apache_user    = 'apache'

      $base_packages = [
        'dnf-plugins-core',
        'gnuplot',
        'wget',
      ]
    }

    'Debian': {
       if ($os_name == 'Ubuntu') {
         if ($os_major < 20 or $os_major > 24) {
           fail("ClusterControl on Ubuntu requires version 20.04, 22.04, or 24.04 LTS. Got: ${os_major}")
        }
      } elsif ($os_name == 'Debian') {
        if ($os_major < 11 or $os_major > 12) {
          fail("ClusterControl on Debian requires version 11 or 12. Got: ${os_major}")
        }
      } else {
        fail("Unsupported Debian-family OS: ${os_name}")
      }

      # MySQL Community Server (matches cc-ansible setup-Debian.yml)
      $mysql_packages = [
        'mysql-common',
        'mysql-server',
        'mysql-client',
      ]
      # MariaDB packages we explicitly remove (if present)
      $mariadb_packages_to_remove = [
        'mariadb-server',
        'mariadb-client',
        'mariadb-common',
      ]
      $mysql_daemon             = 'mysql'
      $mysql_config_file        = '/etc/mysql/my.cnf'
      $mysql_config_include_dir = '/etc/mysql/conf.d'
      $mysql_socket             = '/var/run/mysqld/mysqld.sock'
      $mysql_pid_file           = '/var/run/mysqld/mysqld.pid'

      # MySQL APT config
      $mysql_apt_config_deb = 'https://repo.mysql.com/mysql-apt-config.deb'
      $mysql_gpg_key_id     = '0xB7B3B788A8D3785C'
      $mysql_gpg_fingerprint = 'BCA43417C3B485DD128EC6D4B7B3B788A8D3785C'

      # Python MySQL client
      $python_mysql = $os_major ? {
        18      => 'python-mysqldb',
        default => 'python3-mysqldb',
      }

      # Repository paths
      $repo_config_dir       = '/etc/apt/sources.list.d'
      $repo_config_path      = '/etc/apt/sources.list.d/s9s-repo.list'
      $repo_cli_config_path  = '/etc/apt/sources.list.d/s9s-tools.list'
      $repo_config_url       = 'https://www.severalnines.com/downloads/cmon/s9s-repo.list'

      $distro_codename = $facts['os']['distro']['codename']
      $clustercontrol_cli_repository = "deb [signed-by=/etc/apt/keyrings/severalnines-tools.asc] https://${repo_host}/s9s-tools/${distro_codename}/ ./"
      $clustercontrol_cli_key        = "https://${repo_host}/s9s-tools/${distro_codename}/Release.key"

      $apache_service = 'apache2'
      $apache_user    = 'www-data'

      $apt_keyrings_dir = '/etc/apt/keyrings'

      $base_packages = [
        'gnupg',
        'ca-certificates',
        'wget',
        'curl',
      ]
    }

    default: {
      fail("Unsupported OS family: ${os_family}. Supported: RedHat, Debian.")
    }
  }
}
