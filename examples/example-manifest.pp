# Example Puppet manifest for ClusterControl

node 'clustercontrol.local' {
  class { 'clustercontrol':
    # MySQL credentials
    mysql_root_username => 'root',
    mysql_root_password => 'MySQLRootPassw0rd!',
    cmon_mysql_user     => 'cmon',
    cmon_mysql_password => 'MySQLCmonPassw0rd!',

    # Run mode
    cc_install_mode  => 'mcc',
    cc_package_state => 'latest',   # 'latest' or 'present'

    # MCC settings
    mcc_web_port => 443,
    mcc_web_root => '/var/www/html/clustercontrol-mcc',
  }
}
