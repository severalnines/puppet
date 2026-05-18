# == Class: clustercontrol::params
#
# Default values and OS-specific package/repo definitions for the ClusterControl
# Puppet module. Mirrors the structure of severalnines/cc deployment's vars/.
#
# Supports:
#   - RHEL/CentOS/Rocky/AlmaLinux 7, 8, 9
#   - Ubuntu 18.04, 20.04, 22.04, 24.04
#   - Debian 9, 10, 11, 12
#
class clustercontrol::params {

  # ==========================================================================
  # Common settings
  # ==========================================================================
  $repo_host = 'repo.severalnines.com'
  $gpg_key   = "http://${repo_host}/severalnines-repos.asc"

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
  $rpc_token_file    = "${cmon_state_dir}/cc_rpc_token"

  # MCC defaults
  $mcc_web_port = 443
  $mcc_web_root = '/var/www/html/clustercontrol-mcc'

  # ==========================================================================
  # OS-family branching
  # ==========================================================================
  $os_family   = $facts['os']['family']
  $os_name     = $facts['os']['name']
  # Ubuntu returns '22.04' for release.major, RHEL returns '9'
  # Use release.full and split on '.' to reliably get just the major number
  $os_major    = Integer(split($facts['os']['release']['full'], '[.]')[0])

  case $os_family {

    'RedHat': {
      # Version guard
      if ($os_major < 7 or $os_major > 9) {
        fail("ClusterControl on ${os_name} requires major version 7, 8, or 9. Got: ${os_major}")
      }

      # MariaDB (officially supported by ClusterControl on EL systems)
      # Per https://docs.severalnines.com/clustercontrol/latest/getting-started/installation/manual-installation/
      $mysql_packages = [
        'mariadb-server',
        'mariadb',
      ]
      $mysql_daemon            = 'mariadb'
      $mysql_config_file       = '/etc/my.cnf'
      $mysql_config_include_dir = '/etc/my.cnf.d'
      $mysql_socket            = '/var/lib/mysql/mysql.sock'

      # Python MySQL client
      $python_mysql = $os_major ? {
        7       => 'MySQL-python',
        default => 'python3-PyMySQL',
      }

      # Repository paths
      $repo_config_dir       = '/etc/yum.repos.d'
      $repo_config_path      = '/etc/yum.repos.d/s9s-repo.repo'
      $repo_cli_config_path  = '/etc/yum.repos.d/s9s-tools.repo'
      $repo_config_url       = "http://www.severalnines.com/downloads/cmon/s9s-repo.repo"

      # s9s-tools CLI repo - all RHEL-clones use RHEL_<major>
      # (Rocky, AlmaLinux, OracleLinux all map to RHEL_<major>)
      $clustercontrol_cli_repository = "https://${repo_host}/s9s-tools/RHEL_${os_major}/s9s-tools.repo"

      # ClusterControl uses MariaDB on EL (no external MySQL repo needed)

      # Apache/firewall things (legacy mode only)
      $apache_service = 'httpd'
      $apache_user    = 'apache'

      $base_packages = [
        'dnf-plugins-core',
        'gnuplot',
        'wget',
      ]
    }

    'Debian': {
      # Version guard
      if ($os_name == 'Ubuntu') {
        if ($os_major < 18 or $os_major > 24) {
          fail("ClusterControl on Ubuntu requires version 18/20/22/24. Got: ${os_major}")
        }
      } elsif ($os_name == 'Debian') {
        if ($os_major < 9 or $os_major > 12) {
          fail("ClusterControl on Debian requires version 9/10/11/12. Got: ${os_major}")
        }
      } else {
        fail("Unsupported Debian-family OS: ${os_name}")
      }

      # MariaDB (officially supported by ClusterControl; available in default OS repos)
      $mysql_packages = [
        'mariadb-server',
        'mariadb-client',
      ]
      $mysql_daemon = 'mariadb'
      $mysql_config_file        = '/etc/mysql/my.cnf'
      $mysql_config_include_dir = '/etc/mysql/conf.d'
      $mysql_socket             = '/var/run/mysqld/mysqld.sock'

      # Python MySQL client
      $python_mysql = $os_major ? {
        18      => 'python-mysqldb',
        default => 'python3-mysqldb',
      }

      # Repository paths
      $repo_config_dir       = '/etc/apt/sources.list.d'
      $repo_config_path      = '/etc/apt/sources.list.d/s9s-repo.list'
      $repo_cli_config_path  = '/etc/apt/sources.list.d/s9s-tools.list'
      $repo_config_url       = "http://www.severalnines.com/downloads/cmon/s9s-repo.list"

      # CLI repo uses distribution codename
      $distro_codename = $facts['os']['distro']['codename']
      $clustercontrol_cli_repository = "deb [signed-by=/etc/apt/keyrings/severalnines-tools.asc] https://${repo_host}/s9s-tools/${distro_codename}/ ./"
      $clustercontrol_cli_key        = "http://${repo_host}/s9s-tools/${distro_codename}/Release.key"

      # MySQL community APT repo
      $mysql_apt_config_deb = 'https://repo.mysql.com/mysql-apt-config.deb'
      $mysql_community_rpm  = undef
      $mysql_gpg_key        = '0xB7B3B788A8D3785C'

      # Apache/firewall things (legacy mode only)
      $apache_service = 'apache2'
      $apache_user    = 'www-data'

      # Modern keyrings path
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
