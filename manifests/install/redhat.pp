# == Class: clustercontrol::install::redhat
#
# Installs MySQL Community Server 8.4 LTS + ClusterControl on RHEL/Rocky/AlmaLinux 8-9.
#
# This module uses MySQL Community 8.4 (matching Severalnines' cc-ansible
# reference implementation) rather than MariaDB. This avoids the well-known
# EL9 systemd cgroup tracking issue with mariadb.service:
#   "Will not start ... while processes exist"
#   "Failed to run 'start-pre' task: Device or resource busy"
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

  # ============================================================================
  # MySQL Community 8.4 LTS setup (matches cc-ansible setup-RedHat.yml)
  # ============================================================================

  # ----------------------------------------------------------------------------
  # Step 1: Disable RHEL AppStream mysql module (to avoid conflict)
  # ----------------------------------------------------------------------------
  exec { 'disable-rhel-mysql-module':
    command  => 'dnf -y module disable mysql 2>&1 || true',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    unless   => 'dnf module list mysql 2>&1 | grep -q "Disabled profiles"',
    require  => Package[$clustercontrol::params::base_packages],
  }

  # ----------------------------------------------------------------------------
  # Step 2: Import MySQL GPG key
  # ----------------------------------------------------------------------------
  exec { 'import-mysql-gpg-key':
    command  => "rpm --import ${clustercontrol::params::mysql_gpg_key_url}",
    path     => ['/bin', '/usr/bin'],
    unless   => 'rpm -q gpg-pubkey 2>/dev/null | grep -qi mysql',
    require  => Exec['disable-rhel-mysql-module'],
  }

  # ----------------------------------------------------------------------------
  # Step 3: Install MySQL 8.4 community repo RPM
  # ----------------------------------------------------------------------------
  exec { 'install-mysql-community-repo':
    command  => "dnf -y install ${clustercontrol::params::mysql_community_rpm}",
    path     => ['/bin', '/usr/bin'],
    creates  => '/etc/yum.repos.d/mysql-community.repo',
    require  => Exec['import-mysql-gpg-key'],
  }

  # ----------------------------------------------------------------------------
  # Step 4: Enable mysql-8.4-lts-community repo, disable older streams
  # ----------------------------------------------------------------------------
  exec { 'enable-mysql-84-repo':
    command  => 'dnf -y config-manager --disable mysql57-community mysql80-community 2>/dev/null || true; dnf -y config-manager --enable mysql-8.4-lts-community',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    unless   => 'dnf repolist --enabled 2>/dev/null | grep -q "^mysql-8.4-lts-community "',
    require  => Exec['install-mysql-community-repo'],
  }

  # ----------------------------------------------------------------------------
  # Step 5: Remove MariaDB packages if present (avoid conflicts)
  # ----------------------------------------------------------------------------
  exec { 'remove-mariadb-packages':
    command  => 'dnf -y remove mariadb-server mariadb mariadb-libs 2>&1 || true',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    onlyif   => 'rpm -q mariadb-server mariadb mariadb-libs 2>/dev/null | grep -v "is not installed" | grep -q .',
    require  => Exec['enable-mysql-84-repo'],
    before   => Package[$clustercontrol::params::mysql_packages],
  }

  # ----------------------------------------------------------------------------
  # Step 6: Install MySQL Community Server packages
  # ----------------------------------------------------------------------------
  package { $clustercontrol::params::mysql_packages:
    ensure  => present,
    require => [
      Exec['enable-mysql-84-repo'],
      Exec['remove-mariadb-packages'],
    ],
  }

  # Python MySQL client library
  package { $clustercontrol::params::python_mysql:
    ensure  => present,
    require => Package[$clustercontrol::params::mysql_packages],
  }

  # ----------------------------------------------------------------------------
  # Step 7: Initialize MySQL 8 datadir (insecure init - ClusterControl compat)
  #
  # MySQL 8 must be initialized with --initialize-insecure on first install
  # to leave root passwordless. configure_mysql.pp then sets the real root
  # password. This is the approach used by Severalnines' cc-ansible.
  # ----------------------------------------------------------------------------
  exec { 'ensure-mysql-datadir-ownership':
    command => "chown -R mysql:mysql ${clustercontrol::params::mysql_datadir}",
    path    => ['/bin', '/usr/bin'],
    onlyif  => "test -d ${clustercontrol::params::mysql_datadir}",
    unless  => "test \"$(stat -c %U ${clustercontrol::params::mysql_datadir} 2>/dev/null)\" = mysql",
    require => Package[$clustercontrol::params::mysql_packages],
  }

  # Init-insecure runs only once - guarded by datadir's 'mysql' subdir presence
  exec { 'mysql-initialize-insecure':
    command  => "mysqld --initialize-insecure --user=mysql --basedir=/usr --datadir=${clustercontrol::params::mysql_datadir}",
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    creates  => "${clustercontrol::params::mysql_datadir}/mysql",
    require  => Exec['ensure-mysql-datadir-ownership'],
  }

  # ----------------------------------------------------------------------------
  # Disable SELinux + firewalld
  # ----------------------------------------------------------------------------
  if ($clustercontrol::disable_selinux) {
    file { '/etc/selinux/config':
      ensure  => file,
      content => "# Managed by Puppet - clustercontrol module\nSELINUX=disabled\nSELINUXTYPE=targeted\n",
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
    }

    exec { 'set-selinux-permissive':
      command => 'setenforce 0',
      path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
      onlyif  => 'test -x /usr/sbin/getenforce && /usr/sbin/getenforce | grep -qi "Enforcing"',
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
    require => [
      Exec['import-severalnines-gpg-key'],
      Package[$clustercontrol::params::base_packages],
    ],
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
      Exec['download-severalnines-repo'],
      Exec['download-severalnines-cli-repo'],
      Package[$clustercontrol::params::mysql_packages],
      Exec['mysql-initialize-insecure'],
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
}
