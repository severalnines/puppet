# == Class: clustercontrol::configure_mcc
#
# Idempotent CMON + MCC initialization using marker files.
#
class clustercontrol::configure_mcc {

  $state_dir   = $clustercontrol::params::cmon_state_dir
  $cmon_marker = $clustercontrol::params::cmon_init_marker
  $mcc_marker  = $clustercontrol::params::mcc_init_marker
  $token_file  = $clustercontrol::params::rpc_token_file
  $cmon_cnf    = $clustercontrol::params::cmon_config_file
  $cmon_default = $clustercontrol::params::cmon_default_file
  $cmon_user   = $clustercontrol::cmon_mysql_user
  $cmon_pass   = $clustercontrol::cmon_mysql_password
  $cmon_port   = $clustercontrol::cmon_mysql_port
  $web_port    = $clustercontrol::mcc_web_port
  $web_root    = $clustercontrol::mcc_web_root
  $controller_ip = $clustercontrol::controller_ip

  # /var/lib/cmon directory is created by clustercontrol::configure_mysql
  # (runs first in the dependency chain). We just use it here.

  # ----------------------------------------------------------------------------
  # /etc/default/cmon  -  EVENTS_CLIENT + CLOUD_SERVICE
  # ----------------------------------------------------------------------------
  file { $cmon_default:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => "EVENTS_CLIENT=\"http://127.0.0.1:9510\"\nCLOUD_SERVICE=\"http://127.0.0.1:9518\"\n",
  }

  # ----------------------------------------------------------------------------
  # Generate RPC token once and persist to disk
  # ----------------------------------------------------------------------------
  exec { 'generate-rpc-token':
    command  => "cat /proc/sys/kernel/random/uuid | sha1sum | cut -f1 -d' ' > ${token_file}; chmod 0600 ${token_file}",
    path     => ['/bin', '/usr/bin'],
    creates  => $token_file,
    provider => shell,
    require  => File[$state_dir],
  }

  # ----------------------------------------------------------------------------
  # Remove package-default /etc/cmon.cnf ONLY before first init
  # (After first init, marker file prevents this from running again)
  # ----------------------------------------------------------------------------
  exec { 'remove-default-cmon-cnf':
    command  => "rm -f ${cmon_cnf}",
    path     => ['/bin', '/usr/bin'],
    provider => shell,
    onlyif   => "test ! -f ${cmon_marker} && test -f ${cmon_cnf}",
    require  => File[$state_dir],
  }

  # ----------------------------------------------------------------------------
  # cmon --init runs ONCE (guarded by marker)
  # ----------------------------------------------------------------------------
  exec { 'cmon-init':
    command  => "cmon --init --mysql-hostname='127.0.0.1' --mysql-port='${cmon_port}' --mysql-username='${cmon_user}' --mysql-password='${cmon_pass}' --mysql-database='cmon' --hostname='${controller_ip}' --rpc-token=\"\$(cat ${token_file})\" --controller-id='clustercontrol'",
    path     => ['/bin', '/usr/bin', '/usr/sbin'],
    provider => shell,
    creates  => $cmon_marker,
    require  => [
      Exec['generate-rpc-token'],
      Exec['remove-default-cmon-cnf'],
      File[$cmon_default],
    ],
  }

  exec { 'create-cmon-init-marker':
    command  => "touch ${cmon_marker}",
    path     => ['/bin', '/usr/bin'],
    creates  => $cmon_marker,
    require  => Exec['cmon-init'],
  }

  # ----------------------------------------------------------------------------
  # Ensure cmon-proxy is started before ccmgradm init
  # ----------------------------------------------------------------------------
  service { 'cmon-proxy':
    ensure  => running,
    enable  => true,
    require => Exec['create-cmon-init-marker'],
  }

  # ----------------------------------------------------------------------------
  # Deploy ccmgradm init wrapper script
  # The wrapper treats "Controller already exists" as success since that means
  # the controller IS in the desired registered state from a previous attempt.
  # ----------------------------------------------------------------------------
  file { '/usr/local/sbin/ccmgradm_init_wrapper.sh':
    ensure => file,
    mode   => '0755',
    owner  => 'root',
    group  => 'root',
    source => 'puppet:///modules/clustercontrol/ccmgradm_init_wrapper.sh',
  }

  # ----------------------------------------------------------------------------
  # ccmgradm init runs ONCE (guarded by marker)
  # The wrapper handles both fresh registration and re-registration cases.
  # ----------------------------------------------------------------------------
  exec { 'mcc-init':
    command  => "/usr/local/sbin/ccmgradm_init_wrapper.sh ${web_port} ${web_root}",
    path     => ['/bin', '/usr/bin', '/usr/sbin'],
    provider => shell,
    creates  => $mcc_marker,
    onlyif   => 'command -v ccmgradm >/dev/null 2>&1',
    require  => [
      Service['cmon-proxy'],
      File['/usr/local/sbin/ccmgradm_init_wrapper.sh'],
    ],
  }

  exec { 'create-mcc-init-marker':
    command  => "touch ${mcc_marker}",
    path     => ['/bin', '/usr/bin'],
    creates  => $mcc_marker,
    require  => Exec['mcc-init'],
  }

  # Restart cmon-proxy after init using a one-shot exec instead of a service notify
  # (a service notify back to cmon-proxy would create a dependency cycle)
  exec { 'restart-cmon-proxy-after-mcc-init':
    command     => 'systemctl restart cmon-proxy',
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    refreshonly => true,
    subscribe   => Exec['mcc-init'],
    require     => Exec['create-mcc-init-marker'],
  }

  # ----------------------------------------------------------------------------
  # Fix web root directory permissions (per official ClusterControl docs)
  # On systems with a strict default umask (typically Ubuntu/Debian), the
  # /var/www/html/clustercontrol-mcc directory tree may be created without
  # read+execute permissions for group/others, causing a "Not Found" page
  # when accessing the GUI. Set 755 on the full path to allow cmon-proxy
  # to serve the static frontend files.
  # ----------------------------------------------------------------------------
  exec { 'fix-web-root-permissions':
    command  => 'chmod 755 /var /var/www /var/www/html /var/www/html/clustercontrol-mcc',
    path     => ['/bin', '/usr/bin'],
    onlyif   => 'test -d /var/www/html/clustercontrol-mcc',
    unless   => "test $(stat -c '%a' /var/www/html/clustercontrol-mcc) = '755' && test $(stat -c '%a' /var/www/html) = '755'",
    provider => shell,
    require  => Exec['create-mcc-init-marker'],
    notify   => Exec['restart-cmon-proxy-after-mcc-init'],
  }
}
