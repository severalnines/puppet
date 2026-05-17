# == Class: clustercontrol::mcc
#
# Enables and starts all ClusterControl services in correct order,
# then creates the ccsetup user for first-run GUI registration.
#
class clustercontrol::mcc {

  $mysql_root_pass = $clustercontrol::mysql_root_password

  # ----------------------------------------------------------------------------
  # Step 1: Enable all CC services on boot
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

  service { 'kuber-proxy':
    ensure  => running,
    enable  => true,
    require => Service['cmon-cloud'],
  }

  # ----------------------------------------------------------------------------
  # Step 2: Restart all CC services to clear in-memory state from initialization
  # This is critical — cmon must be restarted after cmon --init writes its config,
  # and cmon-proxy must be restarted to pick up the controller registration from
  # ccmgradm init. Without these restarts, s9s commands silently fail because the
  # admin user state in memory doesn't match what's in the DB.
  # ----------------------------------------------------------------------------
  exec { 'restart-all-cc-services':
    command  => 'systemctl restart cmon cmon-ssh cmon-events cmon-cloud cmon-proxy kuber-proxy',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    onlyif   => 'test ! -f /var/lib/cmon/.puppet-services-restarted',
    require  => [
      Service['cmon'],
      Service['cmon-ssh'],
      Service['cmon-events'],
      Service['cmon-cloud'],
      Service['kuber-proxy'],
    ],
  }

  exec { 'mark-services-restarted':
    command  => 'touch /var/lib/cmon/.puppet-services-restarted',
    path     => ['/bin', '/usr/bin'],
    creates  => '/var/lib/cmon/.puppet-services-restarted',
    require  => Exec['restart-all-cc-services'],
  }

  # ----------------------------------------------------------------------------
  # Step 3: Wait for services to be fully ready before creating ccsetup user
  # ----------------------------------------------------------------------------
  exec { 'wait-for-cmon-rpc':
    command  => 'for i in $(seq 1 30); do curl -k -s -o /dev/null https://127.0.0.1:9501 && exit 0; sleep 2; done; exit 1',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    require  => Exec['mark-services-restarted'],
  }

  # ----------------------------------------------------------------------------
  # Step 4: Unsuspend the cmon-init-created 'admin' user
  # The cmon controller may have suspended admin during init/restart cycles.
  # This MUST happen after the service restart so the change is picked up.
  # ----------------------------------------------------------------------------
  exec { 'unsuspend-admin-user':
    command  => "mysql -u root -p\"${mysql_root_pass}\" cmon -NBe \"UPDATE users SET properties = JSON_SET(properties, '\$.suspended', false, '\$.n_failed_logins', 0) WHERE username = 'admin';\"",
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    require  => Exec['wait-for-cmon-rpc'],
  }

  # ----------------------------------------------------------------------------
  # Step 5: Restart cmon ONE more time so it picks up the unsuspended admin
  # ----------------------------------------------------------------------------
  exec { 'restart-cmon-after-unsuspend':
    command  => 'systemctl restart cmon && sleep 5',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    onlyif   => 'test ! -f /var/lib/cmon/.puppet-cmon-restarted',
    require  => Exec['unsuspend-admin-user'],
  }

  exec { 'mark-cmon-restarted':
    command  => 'touch /var/lib/cmon/.puppet-cmon-restarted',
    path     => ['/bin', '/usr/bin'],
    creates  => '/var/lib/cmon/.puppet-cmon-restarted',
    require  => Exec['restart-cmon-after-unsuspend'],
  }

  # ----------------------------------------------------------------------------
  # Step 6: Create ccsetup user for first-run GUI registration
  # NO --email-address flag so the GUI email field stays editable on registration.
  # ----------------------------------------------------------------------------
  exec { 'create-ccsetup-user':
    command  => 'export S9S_USER_CONFIG=/tmp/ccsetup.conf; rm -f /tmp/ccsetup.conf; s9s user --create --new-password=admin --group=admins --controller="https://localhost:9501" ccsetup || true; unset S9S_USER_CONFIG',
    path     => ['/bin', '/usr/bin', '/usr/sbin'],
    provider => shell,
    unless   => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM cmon.users WHERE username='ccsetup';\" 2>/dev/null | grep -q 1",
    require  => Exec['mark-cmon-restarted'],
  }
}
