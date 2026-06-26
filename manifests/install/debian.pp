# == Class: clustercontrol::install::debian
#
# Installs MySQL Community Server + ClusterControl on Debian 11-12 / Ubuntu 20.04-24.04 LTS.
#
# This module uses MySQL Community (matching Severalnines' cc-ansible reference
# implementation) rather than the distribution's default MariaDB. This provides
# consistent behavior across all supported OS families and aligns with the
# database used in ClusterControl's official deployment tooling.
#
class clustercontrol::install::debian {

  $os_major     = $clustercontrol::params::os_major
  $distro_code  = $clustercontrol::params::distro_codename
  $keyrings_dir = $clustercontrol::params::apt_keyrings_dir

  # ----------------------------------------------------------------------------
  # Base prerequisites
  # ----------------------------------------------------------------------------
  exec { 'apt-update-initial':
    command     => 'apt-get update',
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    refreshonly => false,
    onlyif      => 'test ! -f /var/cache/apt/pkgcache.bin -o $(find /var/cache/apt/pkgcache.bin -mmin -60 2>/dev/null | wc -l) -eq 0',
    provider    => shell,
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

  # ============================================================================
  # MySQL Community setup (matches cc-ansible setup-Debian.yml)
  # ============================================================================

  # ----------------------------------------------------------------------------
  # Step 1: Remove MariaDB packages if present (avoid conflicts)
  # ----------------------------------------------------------------------------
  exec { 'remove-mariadb-packages':
    command  => 'DEBIAN_FRONTEND=noninteractive apt-get -y purge mariadb-server mariadb-client mariadb-common 2>&1 || true; apt-get -y autoremove 2>&1 || true',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    onlyif   => 'dpkg -l mariadb-server mariadb-client mariadb-common 2>/dev/null | grep -q "^ii"',
    require  => Package[$clustercontrol::params::base_packages],
  }

  # ----------------------------------------------------------------------------
  # Step 2: Download and install MySQL APT config package
  # ----------------------------------------------------------------------------
  exec { 'download-mysql-apt-config':
    command => "wget -qO /tmp/mysql-apt-config.deb ${clustercontrol::params::mysql_apt_config_deb}",
    path    => ['/bin', '/usr/bin'],
    creates => '/tmp/mysql-apt-config.deb',
    require => [
      Package[$clustercontrol::params::base_packages],
      Exec['remove-mariadb-packages'],
    ],
  }

  exec { 'install-mysql-apt-config':
    command  => 'DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt-config.deb',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    creates  => '/etc/apt/sources.list.d/mysql.list',
    require  => Exec['download-mysql-apt-config'],
  }

  # ----------------------------------------------------------------------------
  # Step 3: Import MySQL repo signing key (via Ubuntu keyserver)
  # ----------------------------------------------------------------------------
  exec { 'import-mysql-apt-gpg-key':
    command  => "curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=${clustercontrol::params::mysql_gpg_key_id}' -o /tmp/mysql-keyserver.asc && gpg --import /tmp/mysql-keyserver.asc && gpg --yes --output /usr/share/keyrings/mysql-apt-config.gpg --export ${clustercontrol::params::mysql_gpg_fingerprint} && rm -f /tmp/mysql-keyserver.asc",
    path     => ['/bin', '/usr/bin'],
    creates  => '/usr/share/keyrings/mysql-apt-config.gpg',
    provider => shell,
    require  => Exec['install-mysql-apt-config'],
  }

  exec { 'apt-update-after-mysql-repo':
    command     => 'apt-get update',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    subscribe   => Exec['import-mysql-apt-gpg-key'],
  }

  # ----------------------------------------------------------------------------
  # Step 4: Pin MySQL packages to repo.mysql.com (avoid Debian/Ubuntu defaults)
  # ----------------------------------------------------------------------------
  file { '/etc/apt/preferences.d/mysql':
    ensure  => file,
    mode    => '0644',
    content => "Package: mysql-*\nPin: origin \"repo.mysql.com\"\nPin-Priority: 1001\n",
    notify  => Exec['apt-update-after-mysql-pin'],
    require => Exec['import-mysql-apt-gpg-key'],
  }

  exec { 'apt-update-after-mysql-pin':
    command     => 'apt-get update',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
  }

  # ----------------------------------------------------------------------------
  # Step 5: Ensure mysql-common from MySQL repo (must come before mysql-server)
  # ----------------------------------------------------------------------------
  exec { 'install-mysql-common-first':
    command  => 'DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-common',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    unless   => 'dpkg -l mysql-common 2>/dev/null | grep -q "^ii"',
    require  => [
      File['/etc/apt/preferences.d/mysql'],
      Exec['apt-update-after-mysql-pin'],
    ],
  }

  # ----------------------------------------------------------------------------
  # Step 6: Install MySQL Community Server + Client
  # ----------------------------------------------------------------------------
  package { $clustercontrol::params::mysql_packages:
    ensure  => present,
    require => Exec['install-mysql-common-first'],
  }

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

  file { $clustercontrol::params::repo_cli_config_path:
    ensure  => file,
    mode    => '0644',
    content => "${clustercontrol::params::clustercontrol_cli_repository}\n",
    require => Exec['import-clustercontrol-cli-gpg-key'],
  }

  exec { 'import-severalnines-gpg-key':
    command => "wget -qO ${keyrings_dir}/severalnines-repos.asc ${clustercontrol::params::gpg_key}",
    path    => ['/bin', '/usr/bin'],
    creates => "${keyrings_dir}/severalnines-repos.asc",
    require => File[$keyrings_dir],
  }

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
  # ----------------------------------------------------------------------------
  $pkg_ensure = $clustercontrol::clustercontrol_version ? {
    'latest' => $clustercontrol::cc_package_state ? {
      'latest' => 'latest',
      default  => 'present',
    },
    default  => $clustercontrol::clustercontrol_version,
  }

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

  package { 'clustercontrol-kuber-proxy':
    ensure  => 'latest',
    require => Package[$versioned_controller_packages],
  }

  package { $versioned_ui_packages:
    ensure  => $pkg_ensure,
    require => Package['clustercontrol-kuber-proxy'],
  }

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
