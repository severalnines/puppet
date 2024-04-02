class clustercontrol::create_cert ($cert_file, $key_file) {

	$domain="*.severalnines.local"
	$commonname=$domain
	$san="dev.severalnines.local" #"dev.severalnines.local"
	$country="SE"
	$state="Stockholm"
	$locality=$state
	$organization='Severalnines AB'
	$organizationalunit="Severalnines"
	$email="support@severalnines.com"
	$keylength=2048
	$expires=1825
	$keyname="/tmp/ssl/server.key"
	$certname="/tmp/ssl/server.crt"
	$csrname="/tmp/ssl/server.csr"
	$tmpfile="/tmp/ssl/ssl_tmp_flag"

	$user_root = "root"
	$home_root = "home_$username"
	$home_path_root = inline_template("<%= scope.lookupvar('::$home') %>")


	$format = "%i"
	$a_version_no = scanf($operatingsystemmajrelease, $format)
	$os_majrelease = $a_version_no[0]
	/*notice(">>>>>> CC Debugger >>>>>> value is: $os_majrelease + ${operatingsystemmajrelease}")*/

	$typevar = type($os_majrelease)
	$lower_operatingsystem = downcase($operatingsystem)

	## create /tmp/ssl directory
	file { '/tmp/ssl':
		ensure => 'directory',
	}


	file {"/tmp/v3.ext":
		ensure  => present,
		content => template('clustercontrol/openssl-extension.txt.erb'),
		owner  => 'root',
		group  => 'root',
		mode   => '0644'
	}

	# "==> Generating tls certificate for $domain"
	file { "${home_path_root}/.rnd" :
		ensure  => present,
		require => Package["$clustercontrol::params::cc_ui2"]
	}

	exec { "create-ssl-dir-for-ssl-keys" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "install -d ${clustercontrol::params::wwwroot}/clustercontrol/ssl",
		require => File["${home_path_root}/.rnd"]
	}   

	exec { "openssl-genrsa" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "openssl genrsa -out $keyname $keylength",
		require => File["${home_path_root}/.rnd"]
	} 

	# if ($lower_operatingsystem == 'redhat' && $os_majrelease >= 8)
	# 	exec { "openssl-genrsa2" :
	# 		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
	# 		command => "openssl req -new -key $keyname -out $csrname -addext \"subjectAltName = DNS:${san}\" -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\" &>/dev/null",
	# 		require => Exec["openssl-genrsa"],
	# 		subscribe => Exec['openssl-genrsa3'],
	# 		logoutput => on_failure
	# 		# creates => $tmpfile
	# 	} 
	# } else {
	# 	exec { "openssl-genrsa3" :
	# 		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
	# 		command => "openssl req -new -key $keyname -out $csrname -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\"",
	# 		provider  => 'shell',
	# 		# unless    => 'test ! -f $tmpfile',
	# 		refresh   => true,
	# 		require => File["${home_path_root}/.rnd"]
	# 	}
	# }


	# exec { "openssl-genrsa2_or_3" :
	# 	path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
	# 	unless => "openssl req -new -key $keyname -out $csrname -addext \"subjectAltName = DNS:${san}\" -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\" &>/dev/null ",
	# 	command => "openssl req -new -key $keyname -out $csrname -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\"",
	# 	require => Exec["openssl-genrsa"],
	# 	logoutput => on_failure
	# 	# creates => $tmpfile
	# }



	exec { "openssl-genrsa2" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "openssl req -new -key $keyname -out $csrname -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\"",
		require => Exec["openssl-genrsa"],
		logoutput => on_failure,
		notify => Exec["openssl-genrsa3"]
		# creates => $tmpfile
	}

	exec { "openssl-genrsa3" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "openssl req -new -key $keyname -out $csrname -addext \"subjectAltName = DNS:${san}\" -subj \"/C=$country/ST=$state/L=$locality/O=$organization/OU=$organizationalunit/CN=$commonname/emailAddress=$email\" &>/dev/null ",
		require => Exec["openssl-genrsa"],
		logoutput => on_failure,
		noop => true
		# creates => $tmpfile
	}


	exec { "openssl-genrsa4" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "openssl x509 -req -extfile /tmp/v3.ext -days $expires -sha256 -in $csrname -signkey $keyname -out $certname",
		require => Exec["openssl-genrsa2"]
	}    

	exec { "openssl-genrsa5" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "rm -rf /tmp/v3.txt",
		require => Exec["openssl-genrsa4"]
	}   


	exec { "copy-certname-to-certfile" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "cp -f $certname $cert_file &>/dev/null",
		# require => Package["$clustercontrol::params::cc_ui2"]
		require => File["${home_path_root}/.rnd"]
	}    


	exec { "copy-server-key-to-key-file" :
		path    => ['/usr/sbin','/sbin', '/bin', '/usr/bin', '/usr/local/bin'],
		command => "cp -f $keyname $key_file &>/dev/null",
		# require => Package["$clustercontrol::params::cc_ui2"]
		require => File["${home_path_root}/.rnd"]
	}
}
