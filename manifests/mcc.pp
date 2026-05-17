# == Class: clustercontrol::mcc
#
# Enables and starts all ClusterControl services in correct order,
# then creates the ccsetup user for first-run GUI registration.
#
class clustercontrol::mcc {

  $mysql_root_pass = $clustercontrol::mysql_root_password

  # ----------------------------------------------------------------------------
  # Enable and start all CC services in order
  # Order matches cc deployment: cmon -> cmon-ssh -> cmon-events -> cmon-cloud
  #                            -> cmon-proxy -> kuber-proxy
  # ----------------------------------------------------------------------------
  service { 'cmon':
    ensure  => running,
    enable  => true,
    require => Class['clustercontrol::configure_mcc'],
  }

  service { 'cmon-ssh':
    ensure  => running,
    enable  => true,
    require => Service['cmon'],
  }

  service { 'cmon-events':
    ensure  => running,
    enable  => true,
    require => Service['cmon-ssh'],
  }

  service { 'cmon-cloud':
    ensure  => running,
    enable  => true,
    require => Service['cmon-events'],
  }

  # cmon-proxy is already started by configure_mcc, just ensure it's enabled
  # (it MUST be running for ccmgradm init to work)

  service { 'kuber-proxy':
    ensure  => running,
    enable  => true,
    require => Service['cmon-cloud'],
  }

  # ----------------------------------------------------------------------------
  # Unsuspend the cmon-init-created 'admin' user
  # (any failed login attempts may have suspended it before ccsetup creation)
  # ----------------------------------------------------------------------------
  exec { 'unsuspend-admin-user':
    command  => "mysql -u root -p\"${mysql_root_pass}\" cmon -NBe \"UPDATE users SET properties = JSON_SET(properties, '\$.suspended', false, '\$.n_failed_logins', 0) WHERE username = 'admin';\"",
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    onlyif   => "mysql -u root -p\"${mysql_root_pass}\" cmon -NBe \"SELECT JSON_EXTRACT(properties, '\$.suspended') FROM users WHERE username='admin';\" 2>/dev/null | grep -q true",
    require  => Service['cmon'],
  }

  # ----------------------------------------------------------------------------
  # Create ccsetup user for MCC initial registration
  # IMPORTANT: NO --email-address flag  so the GUI
  # registration form's email field stays editable.
  # ----------------------------------------------------------------------------
  exec { 'create-ccsetup-user':
    command  => "export S9S_USER_CONFIG=/tmp/ccsetup.conf; s9s user --create --new-password=admin --group=admins --controller=\"https://localhost:9501\" ccsetup",
    path     => ['/bin', '/usr/bin', '/usr/sbin'],
    provider => shell,
    unless   => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM cmon.users WHERE username='ccsetup';\" 2>/dev/null | grep -q 1",
    require  => [
      Service['cmon'],
      Service['kuber-proxy'],
      Exec['unsuspend-admin-user'],
    ],
  }
}
