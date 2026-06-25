# == Class: clustercontrol
#
# Installs and configures Severalnines ClusterControl (MCC mode) with
# MySQL Community Server 8.4 LTS, matching Severalnines' cc-ansible
# reference implementation.
#
# Supports:
#   - RHEL/Rocky/AlmaLinux/Oracle Linux 8, 9
#   - Ubuntu 20.04 LTS, 22.04 LTS
#   - Debian 11 (Bullseye), 12 (Bookworm)
#
# === Parameters
#
# [*mysql_root_password*]
#   MySQL root password to set during install.
#
# [*cmon_mysql_password*]
#   Password for the cmon database user.
#
# [*cmon_mysql_user*]
#   Username for cmon DB user. Default: 'cmon'.
#
# [*cmon_mysql_port*]
#   MySQL port. Default: 3306.
#
# [*cc_install_mode*]
#   'mcc' (default) for modern CC 2.x using cmon-proxy.
#   'legacy' for old Apache + PHP CCv1 (not implemented).
#
# [*cc_package_state*]
#   'latest' (default) or 'present'.
#   - 'latest': always upgrade packages to newest available in repo (default).
#   - 'present': install if missing; don't upgrade if already installed.
#
# [*clustercontrol_version*]
#   Which version of ClusterControl packages to install. Use 'latest' for
#   the newest available version in the Severalnines repository, or pin to
#   a specific version like '2.3.3'. Re-runs are idempotent. Upgrades
#   happen when you change this value and re-apply the manifest.
#   Default: 'latest'.
#
#   Note: clustercontrol-kuber-proxy and s9s-tools are always installed at
#   the latest available version regardless of this setting, because they
#   follow independent version streams.
#
# [*mcc_web_port*]
#   Port for the web UI. Default: 443.
#
# [*mcc_web_root*]
#   Web root directory. Default: /var/www/html/clustercontrol-mcc.
#
# === Example
#
# class { 'clustercontrol':
#   mysql_root_password    => 'StrongRootPassword',
#   cmon_mysql_password    => 'StrongCmonPassword',
#   clustercontrol_version => 'latest',
# }
#
class clustercontrol (
  String  $mysql_root_password,
  String  $cmon_mysql_password,
  String  $mysql_root_username = 'root',
  String  $cmon_mysql_user     = 'cmon',
  Integer $cmon_mysql_port     = 3306,
  Enum['mcc', 'legacy']   $cc_install_mode  = 'mcc',
  Enum['latest', 'present'] $cc_package_state = 'latest',
  String  $clustercontrol_version = 'latest',
  Integer $mcc_web_port  = 443,
  String  $mcc_web_root  = '/var/www/html/clustercontrol-mcc',
  Boolean $disable_selinux  = true,
  Boolean $disable_firewall = true,
) inherits clustercontrol::params {

  # Currently only MCC mode is implemented
  if ($cc_install_mode != 'mcc') {
    fail("cc_install_mode='${cc_install_mode}' is not yet implemented. Use 'mcc'.")
  }

  # Use the IP for cmon binding
  $controller_ip = $facts['networking']['ip']

  # ==========================================================================
  # OS-specific package install + repo setup
  # ==========================================================================
  case $clustercontrol::params::os_family {
    'RedHat': { include clustercontrol::install::redhat }
    'Debian': { include clustercontrol::install::debian }
    default:  { fail("Unsupported OS family: ${clustercontrol::params::os_family}") }
  }

  # ==========================================================================
  # MySQL configuration + cmon user setup
  # ==========================================================================
  include clustercontrol::configure_mysql

  # ==========================================================================
  # MCC initialisation (cmon --init + ccmgradm init) - idempotent via markers
  # ==========================================================================
  include clustercontrol::configure_mcc

  # ==========================================================================
  # Service management + ccsetup user creation
  # ==========================================================================
  include clustercontrol::mcc

  # ==========================================================================
  # Dependency ordering (high-level)
  # Only declare the relationship for the OS family that was actually included.
  # ==========================================================================
  case $clustercontrol::params::os_family {
    'RedHat': {
      Class['clustercontrol::install::redhat']
        -> Class['clustercontrol::configure_mysql']
        -> Class['clustercontrol::configure_mcc']
        -> Class['clustercontrol::mcc']
    }
    'Debian': {
      Class['clustercontrol::install::debian']
        -> Class['clustercontrol::configure_mysql']
        -> Class['clustercontrol::configure_mcc']
        -> Class['clustercontrol::mcc']
    }
    default: {}
  }
}
