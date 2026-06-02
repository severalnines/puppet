# == Class: clustercontrol::install::debian
#
# Installs MariaDB + ClusterControl packages on Ubuntu 18-24 / Debian 9-12.
# MariaDB is the officially supported database for ClusterControl and is
# available in the default OS repositories (no external MySQL repo needed).
#
class clustercontrol::install::debian {

  $os_major     = $clustercontrol::params::os_major
  $distro_code  = $clustercontrol::params::distro_codename
  $keyrings_dir = $clustercontrol::params::apt_keyrings_dir

  # ----------------------------------------------------------------------------
  # Base prerequisites
  # ----------------------------------------------------------------------------
  exec { 'apt-update-initial':
    command  => 'apt-get update',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    refreshonly => false,
    onlyif   => 'test ! -f /var/cache/apt/pkgcache.bin -o $(find /var/cache/apt/pkgcache.bin -mmin -60 2>/dev/null | wc -l) -eq 0',
    provider => shell,
  }

  package { $clustercontrol::params::base_packages:
    ensure  => present,
    require => Exec['apt-update-initial'],
  }

  # Modern APT keyrings dir
  file { $keyrings_dir:
    ensure => directory,
    mode   => '0755',
  }

  # ----------------------------------------------------------------------------
  # MariaDB Server setup (from default OS repos - no external repo needed)
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
  # ClusterControl repository setup
  # ----------------------------------------------------------------------------

  # CLI GPG key
  exec { 'import-clustercontrol-cli-gpg-key':
    command => "wget -qO ${keyrings_dir}/severalnines-tools.asc ${clustercontrol::params::clustercontrol_cli_key}",
    path    => ['/bin', '/usr/bin'],
    creates => "${keyrings_dir}/severalnines-tools.asc",
    require => File[$keyrings_dir],
  }

  # CLI repo file
  file { $clustercontrol::params::repo_cli_config_path:
    ensure  => file,
    mode    => '0644',
    content => "${clustercontrol::params::clustercontrol_cli_repository}\n",
    require => Exec['import-clustercontrol-cli-gpg-key'],
  }

  # Severalnines main GPG key
  exec { 'import-severalnines-gpg-key':
    command => "wget -qO ${keyrings_dir}/severalnines-repos.asc ${clustercontrol::params::gpg_key}",
    path    => ['/bin', '/usr/bin'],
    creates => "${keyrings_dir}/severalnines-repos.asc",
    require => File[$keyrings_dir],
  }

  # Severalnines main repo file
  file { $clustercontrol::params::repo_config_path:
    ensure  => file,
    mode    => '0644',
    content => "deb [arch=amd64 signed-by=${keyrings_dir}/severalnines-repos.asc] http://${clustercontrol::params::repo_host}/deb ubuntu main\n",
    require => Exec['import-severalnines-gpg-key'],
  }

  exec { 'apt-update-after-cc-repos':
    command     => 'apt-get update',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    subscribe   => [
      File[$clustercontrol::params::repo_config_path],
      File[$clustercontrol::params::repo_cli_config_path],
    ],
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
  #   - clustercontrol-kuber-proxy: always 'latest'. Tracks the controller as
  #     an add-on; safer to always install the matching/latest build.
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
      File[$clustercontrol::params::repo_config_path],
      Exec['apt-update-after-cc-repos'],
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

  # Remove default Apache vhosts (in case apache2 got pulled in)
  file {
    [
      '/etc/apache2/sites-enabled/000-default.conf',
      '/etc/apache2/sites-enabled/default-ssl.conf',
    ]:
      ensure => absent,
  }
}
