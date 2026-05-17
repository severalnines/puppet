# == Class: clustercontrol::install::redhat
#
# Installs MySQL 8.4 Community + ClusterControl packages on RHEL/CentOS/Rocky/Alma 7-9.
#
class clustercontrol::install::redhat {

  $params = $clustercontrol::params::params
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
      onlyif  => 'dnf repolist --disabled 2>/dev/null | grep -q crb',
      require => Package['epel-release'],
    }
  }

  package { $clustercontrol::params::base_packages:
    ensure  => present,
    require => Package['epel-release'],
  }

  # ----------------------------------------------------------------------------
  # MySQL 8.4 Community Server setup 
  # ----------------------------------------------------------------------------

  # Disable RHEL AppStream MySQL module
  exec { 'disable-rhel-mysql-module':
    command => 'dnf -y module disable mysql',
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    unless  => 'dnf module list mysql 2>/dev/null | grep -q "\[d\]"',
    require => Package[$clustercontrol::params::base_packages],
  }

  # Import MySQL GPG key
  exec { 'import-mysql-gpg-key':
    command => "rpm --import ${clustercontrol::params::mysql_gpg_key}",
    path    => ['/bin', '/usr/bin'],
    unless  => 'rpm -q gpg-pubkey | xargs -I{} rpm -qi {} 2>/dev/null | grep -q "MySQL Release Engineering"',
    require => Exec['disable-rhel-mysql-module'],
  }

  # Install MySQL 8.4 community repo RPM
  package { 'mysql84-community-release':
    ensure   => present,
    provider => rpm,
    source   => $clustercontrol::params::mysql_community_rpm,
    require  => Exec['import-mysql-gpg-key'],
  }

  # Enable MySQL 8.4 LTS repo, disable older repos
  exec { 'enable-mysql84-repo':
    command => 'dnf -y config-manager --disable mysql57-community mysql80-community 2>/dev/null; dnf -y config-manager --enable mysql-8.4-lts-community',
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    unless  => 'dnf repolist enabled 2>/dev/null | grep -q mysql-8.4-lts-community',
    require => Package['mysql84-community-release'],
  }

  # Remove conflicting MariaDB packages
  package { ['mariadb-libs', 'mariadb', 'mariadb-server']:
    ensure  => absent,
    require => Exec['enable-mysql84-repo'],
  }

  # Install MySQL 8.4 server packages
  package { $clustercontrol::params::mysql_packages:
    ensure  => present,
    require => [
      Exec['enable-mysql84-repo'],
      Package['mariadb-libs'],
    ],
  }

  # Python MySQL client library
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
      command => 'systemctl stop firewalld; systemctl disable firewalld',
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      onlyif  => 'systemctl is-active firewalld 2>/dev/null || systemctl is-enabled firewalld 2>/dev/null',
      provider => shell,
    }
  }

  # ----------------------------------------------------------------------------
  # MySQL 8 insecure init for ClusterControl compatibility
  # ----------------------------------------------------------------------------
  exec { 'mysql8-initialize-insecure':
    command => "mysqld --initialize-insecure --user=mysql --basedir=/usr --datadir=/var/lib/mysql",
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    creates => '/var/lib/mysql/mysql',
    require => Package[$clustercontrol::params::mysql_packages],
    before  => Service[$clustercontrol::params::mysql_daemon],
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
  # ----------------------------------------------------------------------------
  $pkg_ensure = $clustercontrol::cc_package_state ? {
    'latest' => 'latest',
    default  => 'present',
  }

  package { $clustercontrol::params::clustercontrol_controller_packages:
    ensure  => $pkg_ensure,
    require => [
      Exec['download-severalnines-repo'],
      Exec['download-severalnines-cli-repo'],
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
}
