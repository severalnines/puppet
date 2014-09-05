# clustercontrol #

##Table of Contents

1. [Overview](#overview)
2. [Module Description](#module-description)
3. [Setup](#setup)
    * [Requirements](#requirements)
    * [Pre-installation](#pre-installation)
    * [Installation](#installation)
4. [Usage](#usage)
5. [Limitations](#limitations)
6. [Development](#development)

##Overview

Installs ClusterControl on your existing database cluster. ClusterControl is a management and automation software for database clusters. It helps deploy, monitor, manager and scale your database cluster. This module will install ClusterControl and configure it to manage and monitor an existing database cluster. 

Supported database clusters:
* Galera Cluster for MySQL
* Percona XtraDB Cluster
* MariaDB Galera Cluster
* MySQL Replication
* MySQL Cluster
* MongoDB Replica Set
* MongoDB Sharded Cluster
* TokuMX Cluster

More details at [Severalnines](http://www.severalnines.com/clustercontrol) website.


##Module Description

The Puppet module for ClusterControl manages and configures ClusterControl and all of its components:
* Install ClusterControl controller, cmonapi and UI via Severalnines package repository.
* Install and configure MySQL, create CMON DB, grant cmon user and configure DB for ClusterControl UI.
* Install and configure Apache, check permission for ClusterControl UI and install SSL.
* Copy the generated SSH key to all nodes.

If you have any questions, you are welcome to get in touch via our [contact us](http://www.severalnines.com/contact-us) page or email us at info@severalnines.com.


##Setup

###What ClusterControl affects
* Severalnines yum/apt repository
* ClusterControl controller, cmonapi and web UI
* MySQL server and client
* Apache web server with PHP 5
* SSH key (authorized_keys)

###Requirements

Make sure you meet following criteria prior to the deployment:
* ClusterControl node must run on a clean dedicated host with internet connection.
* ClusterControl node must run on the same operating system distribution with your database hosts (mixing Debian with Ubuntu or CentOS with Red Hat is possible)
* Make sure your database cluster is up and running.
* If you are running as sudo user, make sure the user is able to escalate to root with sudo command.
* SELinux/AppArmor must be turned off. Services or ports to be enabled are listed [here](http://www.severalnines.com/docs/clustercontrol-administration-guide/administration/securing-clustercontrol).

###Pre-installation

ClusterControl requires proper SSH key configuration and a ClusterControl API token. Use the helper script located at `$modulepath/clustercontrol/files/s9s_helper.sh` to generate them.

* Generate SSH key to be used by ClusterControl to manage your database nodes. Run following command in Puppet master:
```bash
$ bash /etc/puppet/modules/clustercontrol/files/s9s_helper.sh --generate-key
```

* Then, generate an API token:
```bash
$ bash /etc/puppet/modules/clustercontrol/files/s9s_helper.sh --generate-token
```

*These steps are mandatory and just need to run once (unless if you want to intentionally regenerate them). The first command will generate a RSA key (if not exists) to be used by the module and the key must exist in the Puppet master module's directory before the deployment begins.*

###Installation

Specify the generated token in the node definition similar to example below:

Example hosts:
```
clustercontrol.local 	192.168.1.10
galera1.local 		    192.168.1.11
galera2.local 		    192.168.1.12
galera3.local 		    192.168.1.13
```

Example node definition:
```puppet
node "galera1.local", "galera2.local", "galera3.local" {
        class {'clustercontrol':
                is_controller => false,
	            ssh_user => 'root',
                mysql_root_password => 'dpassword',
                clustercontrol_host => '192.168.1.10'
        }
}
node "clustercontrol.local" {
        class { 'clustercontrol':
                is_controller => true,
                email_address => 'youremail@domain.tld',
                ssh_user => 'root',
                mysql_server_addresses => '192.168.1.11,192.168.1.12,192.168.1.13',
                api_token => 'b7e515255db703c659677a66c4a17952515dbaf5'
        }
}
```

Once deployment is complete, open the ClusterControl web UI at https://[ClusterControl IP address]/clustercontrol and login with specified email address with default password 'admin'.


##Usage

###ClusterControl General Options

Following options are used for the general ClusterControl set up:

####`is_controller`
Define whether the node is ClusterControl controller host. All database nodes that you want ClusterControl to manage should be set to false.
Default: true

####`clustercontrol_host`
Specify the IP address of the ClusterControl node. You can specify ClusterControl's FQDN only if the monitored MySQL servers are configured to perform host name resolution (skip-name-resolve is disabled) or MongoDB servers. Only specify this option on nodes that you want to be managed by ClusterControl.
Example: '192.168.0.10'

####`email_address`
Specify an email as root user for ClusterControl UI. You will login using this email with default password 'admin'.
Default: 'admin@domain.com'

####`ssh_user`
Specify the SSH user that ClusterControl will use to manage the database nodes. Unless root, make sure this user is in sudoers list.
Default: 'root'

####`sudo_password`
If sudo user has password, specify it here. ClusterControl requires this to automate database recovery or perform other management procedures. If `ssh_user` is root, this will be ignored.
Example: 'mysud0p4ssword'

####`api_token`
Specify the 40-character ClusterControl token generated from s9s_helper script.
Example: 'b7e515255db703c659677a66c4a17952515dbaf5'

####`mysql_cmon_root_password`
Specify the MySQL root password for ClusterControl host. This module will install a MySQL server and use this as root password.
Default: 'password'

####`mysql_cmon_password`
Specify the MySQL password for user cmon. The module will grant this user with specified password, and is needed by ClusterControl.
Default: 'cmon'

####`mysql_cmon_port`
MySQL server port that holds CMON database.
Default: 3306

####`cluster_name`
Give your monitored database cluster a name.
Default: 'default_cluster_1'

####`cluster_type`
The database cluster type. MySQL replication falls under mysql_single. Supported values: galera, mysqlcluster, mongodb, mysql_single
Default: 'galera'

####`ssh_port`
Specify the SSH port used by ClusterControl to SSH into database hosts. All nodes in the cluster must use the same SSH port.
Default: 22

####`datadir`
Comma-separated list of database's data directory that should be monitored by ClusterControl. MySQL is equal to datadir while MongoDB is equal to dbpath.
Example: '/var/lib/mysql,/var/lib/mysqlcluster'

####`modulepath`
Change this to the location of Puppet's module path.
Default: '/etc/puppet/modules/clustercontrol'

###MySQL Specific Options

Following options are used for supported MySQL-based cluster type particularly Galera Cluster, MySQL Replication or MySQL Cluster.

####`mysql_basedir`
The location of MySQL base directory of monitored MySQL servers, equal to @@basedir.
Default: '/usr'

####`mysql_server_addresses`
Comma-separated list of MySQL servers' IP address that ClusterControl should monitor. For MySQL cluster, specify the MySQL API nodes list instead.
Example: '12.12.12.12,13.13.13.13,14.14.14.14'

####`vendor`
Database cluster provider (Galera Clusters only). Supported values: percona, mariadb or codership.
Default: 'percona'

####`mysql_root_password`
MySQL root password of your database cluster to be monitored by ClusterControl.
Default: 'password'

####`galera_port`
Galera cluster port of monitored cluster.
Default: 4567

####`datanode_addresses`
Comma-separated list of MySQL data nodes' IP address that ClusterControl should monitor (MySQL Cluster only).
Example: '12.12.12.12,13.13.13.13,14.14.14.14'

####`mgmnode_addresses`
Comma-separated list of MySQL data nodes' IP address that ClusterControl should monitor (MySQL Cluster only).
Example: '12.12.12.12,13.13.13.13,14.14.14.14'

####`ndb_connectstring`
NDB connection string used by MySQL Cluster (MySQL Cluster only).
Example: '12.12.12.12:1186,13.13.13.13:1186'

####`ndb_binary`
Type of NDB binary that used by the monitored MySQL Cluster, either ndbd or ndbmtd.
Default: 'ndbd'

###MongoDB Specific Options

Following options are used for supported MongoDB and TokuMX cluster type particularly Sharded Cluster or Replica Set.

####`mongodb_server_addresses`
Comma-separated list of IP address/hostname with port of MongoDB/TokuMX shard/replica set nodes that ClusterControl should monitor.
Example: '12.12.12.12:27017,13.13.13.13:27017'

####`mongoarbiter_server_addresses`
Comma-separated list of IP address/hostname with port of MongoDB/TokuMX arbiter node (if any) that ClusterControl should monitor.
Example: '12.12.12.12:30000,13.13.13.13:30000'

####`mongocfg_server_addresses`
Comma-separated list of IP address/hostname with port of MongoDB/TokuMX config node (sharded cluster only) that ClusterControl should monitor.
Example: '12.12.12.12:27019,13.13.13.13:27019'

####`mongos_server_addresses`
Comma-separated list of IP address/hostname with port of MongoDB/TokuMX mongos node (sharded cluster only) that ClusterControl should monitor.
Example: '12.12.12.12:27017,13.13.13.13:27017'

####`mongodb_basedir`
MongoDB/TokuMX base directory of monitored MongoDB servers.
Defaut: '/usr'


##Limitations

This module has been tested on following platforms:
* Debian 7.* (wheezy)
* Debian 6.* (squeeze)
* Ubuntu 14.04 LTS (trusty)
* Ubuntu 12.04 LTS (precise)
* Ubuntu 10.04 LTS (lucid)
* RHEL 5/6
* CentOS 5/6

This module only supports bootstrapping MySQL servers with IP address only (it expects skip-name-resolve is enabled on all MySQL nodes). However, for MongoDB you can specify hostname as described under MongoDB Specific Options.

[ClusterControl known issues and limitations](http://www.severalnines.com/docs/clustercontrol-troubleshooting-guide/known-issues-limitations).

##Development

Please report bugs or suggestions via our support channel: [https://support.severalnines.com](https://support.severalnines.com)
