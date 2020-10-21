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

Installs ClusterControl for your new database node/cluster deployment or on top of your existing database node/cluster. ClusterControl is a management and automation software for database clusters. It helps deploy, monitor, manage and scale your database cluster. This module will install ClusterControl and configure it to manage and monitor an existing database cluster. 

Supported database clusters:
* MySQL Replication (Percona/MariaDB/Oracle MySQL)
* MySQL Galera (Percona XtraDB/MariaDB)
* MySQL Cluster (NDB)
* TimesaleDB
* PostgreSQL (supports Single or Streaming Replication)
* MongoDB ReplicaSet (Percona/Mongodb)
* MongoDB Shards (Percona/Mongodb)
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
* If you are running as non-root user, make sure the user is able to escalate to root with sudo command.

###Pre-installation

ClusterControl requires an API token. Use the helper script located at `$modulepath/clustercontrol/files/s9s_helper.sh` to generate them:
```bash
$ bash /etc/puppet/modules/clustercontrol/files/s9s_helper.sh --generate-token
```

###Installation

Specify the generated token in the node definition similar to example below:

Example hosts:
```
clustercontrol.local 	192.168.1.10
galera1.local 		    192.168.1.11
galera2.local 		    192.168.1.12
galera3.local 		    192.168.1.13
```

Example node definition for ClusterControl node:
```puppet
node "clustercontrol.local" {
        class { 'clustercontrol':
                is_controller => true,
                ssh_user => 'root',
                api_token => 'b7e515255db703c659677a66c4a17952515dbaf5'
        }
}
```

Once deployment is complete, open the ClusterControl web UI at https://[ClusterControl IP address]/clustercontrol and create a default admin login. You can now start to add existing database node/cluster, or deploy a new one. Ensure that passwordless SSH is configured properly from ClusterControl node to all DB nodes beforehand. 

To setup passwordless SSH on target database nodes, use following commands on ClusterControl node (as ssh_user), e.g:

```bash
ssh-copy-id 192.168.1.11  # galera1
ssh-copy-id 192.168.1.12  # galera2
ssh-copy-id 192.168.1.13  # galera3
```

##Usage

###General Options

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

####`ssh_key`
Specify the SSH key used by ``ssh_user`` to perform passwordless SSH to the database nodes.
Default: '/home/$USER/.ssh/id_rsa' (non-root,sudoer)
Default: '/root/.ssh/id_rsa' (root)

####`ssh_port`
Specify the SSH port used by ClusterControl to SSH into database hosts. All nodes in the cluster must use the same SSH port.
Default: 22

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

####`datadir`
MySQL datadir on ClusterControl node.
Default: '/var/lib/mysql'

####`modulepath`
Change this to the location of Puppet's module path.
Default: '/etc/puppet/modules/clustercontrol'

##Limitations

This module has been tested on following platforms:
* Debian 8.x (jessie)
* Debian 7.x (wheezy)
* Debian 6.x (squeeze)
* Ubuntu 14.04 LTS (trusty)
* Ubuntu 12.04 LTS (precise)
* Ubuntu 10.04 LTS (lucid)
* RHEL/CentOS 6/7

This module only supports bootstrapping MySQL servers with IP address only (it expects skip-name-resolve is enabled on all MySQL nodes). However, for MongoDB you can specify hostname as described under MongoDB Specific Options.

[ClusterControl known issues and limitations](http://www.severalnines.com/docs/troubleshooting.html#known-issues-and-limitations).

##Development

Please report bugs or suggestions via our support channel: [https://support.severalnines.com](https://support.severalnines.com)

