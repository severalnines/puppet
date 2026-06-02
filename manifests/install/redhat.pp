# == Class: clustercontrol::install::redhat
#
# Installs MariaDB + ClusterControl packages on RHEL/CentOS/Rocky/AlmaLinux 7-9.
# MariaDB is the officially supported database for ClusterControl on EL systems.
#
class clustercontrol::install::redhat {

  $os_major = $clustercontrol::params::os_major

  # ----------------------------------------------------------------------------
  # EPEL + base packages
  # ----------------------------------------------------------------------------
  package { 'epel-release':
    ensure => present,
  }

  # Enable CRB repo on RHEL 9 (required by EPEL)
  if ($os_major == 9) {
    exec { 'enable-crb-repo':
      command => 'dnf config-manager --set-enabled crb',
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      onlyif  => 'dnf repolist --disabled 2>/dev/null | grep -q "^crb "',
      unless  => 'dnf repolist --enabled 2>/dev/null | grep -q "^crb "',
      require => Package['epel-release'],
    }
  }

  package { $clustercontrol::params::base_packages:
    ensure  => present,
    require => Package['epel-release'],
  }

  # ----------------------------------------------------------------------------
  # MariaDB Server setup
  # ----------------------------------------------------------------------------
  package { $clustercontrol::params::mysql_packages:
    ensure  => present,
    require => Package[$clustercontrol::params::base_packages],
  }

  # Python MySQL client library (for any dependent tooling)
  package { $clustercontrol::params::python_mysql:
    ensure  => present,
    require => Package[$clustercontrol::params::mysql_packages],
  }

  # ----------------------------------------------------------------------------
  # Disable SELinux + firewalld
  # ----------------------------------------------------------------------------
  if ($clustercontrol::disable_selinux) {
    exec { 'disable-selinux-runtime':
      command => 'setenforce 0',
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      onlyif  => 'which getenforce && getenforce | grep -qi enforcing',
    }
    file { '/etc/selinux/config':
      ensure  => file,
      content => "# Managed by Puppet - clustercontrol module\nSELINUX=disabled\nSELINUXTYPE=targeted\n",
      mode    => '0644',
    }
  }

  if ($clustercontrol::disable_firewall) {
    exec { 'stop-disable-firewalld':
      command  => 'systemctl stop firewalld; systemctl disable firewalld',
      path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      onlyif   => 'systemctl is-active firewalld 2>/dev/null || systemctl is-enabled firewalld 2>/dev/null',
      provider => shell,
    }
  }

  # ----------------------------------------------------------------------------
  # ClusterControl repository setup
  # ----------------------------------------------------------------------------
  exec { 'import-severalnines-gpg-key':
    command => "rpm --import ${clustercontrol::params::gpg_key}",
    path    => ['/bin', '/usr/bin'],
    unless  => "test -f ${clustercontrol::params::repo_config_path}",
  }

  exec { 'download-severalnines-repo':
    command => "wget -qO ${clustercontrol::params::repo_config_path} ${clustercontrol::params::repo_config_url}",
    path    => ['/bin', '/usr/bin'],
    creates => $clustercontrol::params::repo_config_path,
    require => Exec['import-severalnines-gpg-key'],
  }

  exec { 'download-severalnines-cli-repo':
    command => "wget -qO ${clustercontrol::params::repo_cli_config_path} ${clustercontrol::params::clustercontrol_cli_repository}",
    path    => ['/bin', '/usr/bin'],
    creates => $clustercontrol::params::repo_cli_config_path,
    require => Exec['download-severalnines-repo'],
  }

  # ----------------------------------------------------------------------------
  # Install ClusterControl packages
  #
  # Package ensure value follows this precedence:
  #   1. clustercontrol_version == 'latest' (default) → ensure => 'latest'
  #   2. clustercontrol_version == '2.3.3' (or any version) → that version
  #   3. cc_package_state == 'present' → 'present' (only when version is latest)
  #
  # Special cases:
  #   - clustercontrol-kuber-proxy: always 'latest'. Its RPM build separator
  #     (underscore between version and build, e.g. 2.4.0_638-1) does not
  #     match the user-facing version string, so version pinning is unreliable.
  #     Installing latest is safe and matches the package's intent (the
  #     Kubernetes integration is an add-on that tracks the controller).
  #   - s9s-tools: always 'latest'. The CLI follows an independent version
  #     stream from the main ClusterControl release.
  # ----------------------------------------------------------------------------
  $pkg_ensure = $clustercontrol::clustercontrol_version ? {
    'latest' => $clustercontrol::cc_package_state ? {
      'latest' => 'latest',
      default  => 'present',
    },
    default  => $clustercontrol::clustercontrol_version,
  }

  # Versioned packages — pinnable by user
  $versioned_controller_packages = [
    'clustercontrol-controller',
    'clustercontrol-proxy',
  ]

  $versioned_ui_packages = [
    'clustercontrol-mcc',
    'clustercontrol-notifications',
    'clustercontrol-ssh',
    'clustercontrol-cloud',
    'clustercontrol-clud',
  ]

  package { $versioned_controller_packages:
    ensure  => $pkg_ensure,
    require => [
      Exec['download-severalnines-repo'],
      Exec['download-severalnines-cli-repo'],
      Package[$clustercontrol::params::mysql_packages],
    ],
  }

  # clustercontrol-kuber-proxy: always latest (see comment above)
  package { 'clustercontrol-kuber-proxy':
    ensure  => 'latest',
    require => Package[$versioned_controller_packages],
  }

  package { $versioned_ui_packages:
    ensure  => $pkg_ensure,
    require => Package['clustercontrol-kuber-proxy'],
  }

  # s9s-tools: always latest (independent version stream)
  package { $clustercontrol::params::clustercontrol_cli_packages:
    ensure  => 'latest',
    require => Package[$versioned_ui_packages],
  }
}
