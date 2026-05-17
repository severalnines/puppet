# == Class: clustercontrol::install::debian
#
# Installs MySQL 8.x from MySQL APT repo + ClusterControl on Ubuntu 18-24 / Debian 9-12.
#
class clustercontrol::install::debian {

  $os_major     = $clustercontrol::params::os_major
  $distro_code  = $clustercontrol::params::distro_codename
  $keyrings_dir = $clustercontrol::params::apt_keyrings_dir

  # ----------------------------------------------------------------------------
  # Base prerequisites
  # ----------------------------------------------------------------------------
  exec { 'apt-update-initial':
    command => 'apt-get update',
    path    => ['/bin', '/usr/bin'],
    refreshonly => false,
    onlyif  => 'test ! -f /var/cache/apt/pkgcache.bin -o $(find /var/cache/apt/pkgcache.bin -mmin -60 2>/dev/null | wc -l) -eq 0',
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
  # MySQL Official APT Repository
  # ----------------------------------------------------------------------------

  # Download mysql-apt-config.deb
  exec { 'download-mysql-apt-config':
    command => "wget -qO /tmp/mysql-apt-config.deb ${clustercontrol::params::mysql_apt_config_deb}",
    path    => ['/bin', '/usr/bin'],
    creates => '/tmp/mysql-apt-config.deb',
    require => Package[$clustercontrol::params::base_packages],
  }

  # Install mysql-apt-config (non-interactive)
  exec { 'install-mysql-apt-config':
    command  => 'DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt-config.deb',
    path     => ['/bin', '/usr/bin'],
    creates  => '/etc/apt/sources.list.d/mysql.list',
    provider => shell,
    require  => Exec['download-mysql-apt-config'],
  }

  # Workaround: refresh MySQL signing key from Ubuntu keyserver 
  exec { 'refresh-mysql-signing-key':
    command  => 'curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xB7B3B788A8D3785C" -o /tmp/mysql-keyserver.asc && gpg --import /tmp/mysql-keyserver.asc 2>/dev/null && gpg --yes --output /usr/share/keyrings/mysql-apt-config.gpg --export BCA43417C3B485DD128EC6D4B7B3B788A8D3785C && rm -f /tmp/mysql-keyserver.asc',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    unless   => 'test -f /usr/share/keyrings/mysql-apt-config.gpg',
    require  => Exec['install-mysql-apt-config'],
  }

  exec { 'apt-update-after-mysql':
    command     => 'apt-get update',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    subscribe   => Exec['refresh-mysql-signing-key'],
  }

  # Pin MySQL packages to MySQL repo
  file { '/etc/apt/preferences.d/mysql':
    ensure  => file,
    mode    => '0644',
    content => "Package: mysql-*\nPin: origin \"repo.mysql.com\"\nPin-Priority: 1001\n",
    require => Exec['install-mysql-apt-config'],
    notify  => Exec['apt-update-after-mysql'],
  }

  # Fix any broken dpkg state
  exec { 'fix-dpkg-state':
    command  => 'dpkg --configure -a || true; apt-get -f install -y || true',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    onlyif   => 'dpkg --audit 2>&1 | grep -q .',
    require  => File['/etc/apt/preferences.d/mysql'],
  }

  # Install mysql-common from MySQL repo first
  package { 'mysql-common':
    ensure  => latest,
    require => [
      File['/etc/apt/preferences.d/mysql'],
      Exec['apt-update-after-mysql'],
    ],
  }

  # Install remaining MySQL packages
  package { ['mysql-server', 'mysql-client']:
    ensure  => present,
    require => Package['mysql-common'],
  }

  # Python MySQL client library
  package { $clustercontrol::params::python_mysql:
    ensure  => present,
    require => Package[['mysql-server', 'mysql-client']],
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
  # ----------------------------------------------------------------------------
  $pkg_ensure = $clustercontrol::cc_package_state ? {
    'latest' => 'latest',
    default  => 'present',
  }

  package { $clustercontrol::params::clustercontrol_controller_packages:
    ensure  => $pkg_ensure,
    require => [
      File[$clustercontrol::params::repo_config_path],
      Exec['apt-update-after-cc-repos'],
      Package['mysql-server'],
    ],
  }

  package { $clustercontrol::params::clustercontrol_ui_packages:
    ensure  => $pkg_ensure,
    require => Package[$clustercontrol::params::clustercontrol_controller_packages],
  }

  package { $clustercontrol::params::clustercontrol_cli_packages:
    ensure  => latest,
    require => Package[$clustercontrol::params::clustercontrol_ui_packages],
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
