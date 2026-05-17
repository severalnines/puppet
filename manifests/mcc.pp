# == Class: clustercontrol::mcc
#
# Enables and starts all ClusterControl services in correct order,
# syncs the admin user password with /etc/s9s.conf, then creates the
# ccsetup user for first-run GUI registration.
#
class clustercontrol::mcc {

  $mysql_root_pass = $clustercontrol::mysql_root_password

  # ----------------------------------------------------------------------------
  # Ship the admin password sync helper script
  # ----------------------------------------------------------------------------
  file { '/usr/local/sbin/sync_cmon_admin.sh':
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0750',
    source => 'puppet:///modules/clustercontrol/sync_cmon_admin.sh',
  }

  # ----------------------------------------------------------------------------
  # Step 1: Enable and start all CC services on boot
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
  # Step 3: Wait for cmon RPC to be ready
  # ----------------------------------------------------------------------------
  exec { 'wait-for-cmon-rpc':
    command  => 'for i in $(seq 1 30); do curl -k -s -o /dev/null https://127.0.0.1:9501 && exit 0; sleep 2; done; exit 1',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    require  => Exec['mark-services-restarted'],
  }

  # ----------------------------------------------------------------------------
  # Step 4: Sync admin password with /etc/s9s.conf (using helper script)
  # Only runs if s9s currently CAN'T authenticate (i.e. there's a mismatch).
  # If everything's already in sync, this is skipped.
  # ----------------------------------------------------------------------------
  exec { 'sync-admin-password':
    command  => "/usr/local/sbin/sync_cmon_admin.sh '${mysql_root_pass}'",
    path     => ['/bin', '/usr/bin', '/usr/local/sbin'],
    onlyif   => 'command -v s9s >/dev/null 2>&1 && ! s9s user --list >/dev/null 2>&1',
    provider => shell,
    require  => [
      File['/usr/local/sbin/sync_cmon_admin.sh'],
      Exec['wait-for-cmon-rpc'],
    ],
  }

  # ----------------------------------------------------------------------------
  # Step 5: Restart cmon so it loads the synced admin password
  # ----------------------------------------------------------------------------
  exec { 'restart-cmon-after-password-sync':
    command  => 'systemctl restart cmon && sleep 8',
    path     => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    provider => shell,
    refreshonly => true,
    subscribe   => Exec['sync-admin-password'],
  }

  # ----------------------------------------------------------------------------
  # Step 6: Wait for s9s to authenticate successfully
  # ----------------------------------------------------------------------------
  exec { 'wait-for-s9s-auth':
    command  => 'for i in $(seq 1 30); do s9s user --list >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1',
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    require  => [
      Exec['sync-admin-password'],
      Exec['restart-cmon-after-password-sync'],
    ],
  }

  # ----------------------------------------------------------------------------
  # Step 7: Create ccsetup user for first-run GUI registration
  # NO --email-address flag so the GUI email field stays editable.
  # ----------------------------------------------------------------------------
  exec { 'create-ccsetup-user':
    command  => 'rm -f /tmp/ccsetup.conf; S9S_USER_CONFIG=/tmp/ccsetup.conf s9s user --create --new-password=admin --group=admins --controller="https://localhost:9501" ccsetup',
    path     => ['/bin', '/usr/bin', '/usr/sbin'],
    provider => shell,
    unless   => "mysql -u root -p\"${mysql_root_pass}\" -NBe \"SELECT 1 FROM cmon.users WHERE username='ccsetup';\" 2>/dev/null | grep -q 1",
    require  => Exec['wait-for-s9s-auth'],
  }
}
