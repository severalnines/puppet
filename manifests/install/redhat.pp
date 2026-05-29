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
      Package[$clustercontrol::params::mysql_packages],
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
