class clustercontrol::create_cert ($cert_file, $key_file) {

  $domain              = '*.severalnines.local'
  $commonname          = $domain
  $san                 = 'dev.severalnines.local'
  $country             = 'SE'
  $state               = 'Stockholm'
  $locality            = $state
  $organization        = 'Severalnines AB'
  $organizationalunit  = 'Severalnines'
  $email               = 'support@severalnines.com'
  $keylength           = 2048
  $expires             = 1825
  $keyname             = '/tmp/ssl/server.key'
  $certname            = '/tmp/ssl/server.crt'
  $csrname             = '/tmp/ssl/server.csr'

  # Puppet 8 / Facter 4 structured facts
  $os_name       = downcase($facts['os']['name'])
  $os_family     = downcase($facts['os']['family'])
  $os_major      = Integer($facts['os']['release']['major'])

  # Home directory for root user
  $home_path_root = '/root'

  ## Create /tmp/ssl directory
  file { '/tmp/ssl':
    ensure => directory,
  }

  file { '/tmp/v3.ext':
    ensure  => present,
    content => template('clustercontrol/openssl-extension.txt.erb'),
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
  }

  file { "${home_path_root}/.rnd":
    ensure  => present,
    require => Package[$clustercontrol::params::cc_ui2],
  }

  exec { 'create-ssl-dir-for-ssl-keys':
    path    => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
    command => "install -d ${clustercontrol::params::wwwroot}/clustercontrol/ssl",
    require => File["${home_path_root}/.rnd"],
  }

  exec { 'openssl-genrsa':
    path    => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
    command => "openssl genrsa -out ${keyname} ${keylength}",
    require => File["${home_path_root}/.rnd"],
  }

  # EL 8/9, Ubuntu 20+, Debian 11+, SLES 15+ all support -addext (openssl >= 1.1.1)
  # Use -addext for SAN on modern OS; fallback for older
  $use_addext = ($os_family == 'redhat' and $os_major >= 8) or
                ($os_name   == 'ubuntu' and $os_major >= 20) or
                ($os_name   == 'debian' and $os_major >= 11) or
                ($os_family == 'suse'   and $os_major >= 15)

  if $use_addext {
    exec { 'openssl-genrsa2':
      path      => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
      command   => "openssl req -new -key ${keyname} -out ${csrname} -addext \"subjectAltName = DNS:${san}\" -subj \"/C=${country}/ST=${state}/L=${locality}/O=${organization}/OU=${organizationalunit}/CN=${commonname}/emailAddress=${email}\" 2>/dev/null",
      require   => Exec['openssl-genrsa'],
      logoutput => on_failure,
      notify    => Exec['openssl-genrsa4'],
    }
  } else {
    exec { 'openssl-genrsa2':
      path      => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
      command   => "openssl req -new -key ${keyname} -out ${csrname} -subj \"/C=${country}/ST=${state}/L=${locality}/O=${organization}/OU=${organizationalunit}/CN=${commonname}/emailAddress=${email}\"",
      require   => Exec['openssl-genrsa'],
      logoutput => on_failure,
      notify    => Exec['openssl-genrsa4'],
    }
  }

  exec { 'openssl-genrsa4':
    path        => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
    command     => "openssl x509 -req -extfile /tmp/v3.ext -days ${expires} -sha256 -in ${csrname} -signkey ${keyname} -out ${certname}",
    require     => Exec['openssl-genrsa2'],
    refreshonly => true,
  }

  exec { 'copy-certname-to-certfile':
    path    => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
    command => "cp -f ${certname} ${cert_file} 2>/dev/null",
    require => Exec['openssl-genrsa4'],
  }

  exec { 'copy-server-key-to-key-file':
    path    => ['/usr/sbin', '/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
    command => "cp -f ${keyname} ${key_file} 2>/dev/null",
    require => Exec['openssl-genrsa4'],
  }
}
