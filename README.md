# clustercontrol #

## Table of Contents

1. [Overview](#overview)
2. [Module Description](#module-description)
3. [Setup](#setup)
    * [Requirements](#requirements)
    * [Pre-installation](#pre-installation)
    * [Installation](#installation)
4. [Usage](#usage)
5. [Limitations](#limitations)
6. [Development](#development)

## Overview

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


## Module Description

The Puppet module for ClusterControl automates the following actions based on the scope of this module:
* Setup ClusterControl required repositories
* Download and installs dependencies. These dependencies are required by its compontents such as Apache, PHP, OpenSSL, MySQL/MariaDB are among its basic packages required.
* Install ClusterControl components such as the controller, front-end, CMON cloud, CMON SSH, and CMON Clud (upload/download cloud link)
* Automates configuration for Apache
	* configures the *<VirtualHost>* for port 80 and port 443 (for SSL/TLS). This includes its designated rewrite rules needed
	* ensures port 443 is enabled
	* enables header module setting *X-Frame-Options: sameorigin*
	* check permission for ClusterControl UI and install SSL.
* Automates MySQL/MariaDB installation. 
	* create CMON DB, grant cmon user and configure DB for ClusterControl UI.

[//]: <> (Copy the generated SSH key to all nodes.)

If you have any questions, feel free to raise issues via https://github.com/severalnines/puppet/issues or hit your question via our [Community Forums](https://support.severalnines.com/hc/en-us/community/topics) or via [Slack](https://join.slack.com/t/clustercontrol/shared_invite/zt-b15k9477-jLllD6qJOUm3bGnOWynVig)

## Setup

### What ClusterControl affects
* Severalnines yum/apt repository
* ClusterControl controller, frontend, cmon-cloud and cmon-clud, and cmon-ssh packages
* Disables SELinux/AppArmor. *You can enable once setup correctly*.
* MySQL server and client
* Apache web server with PHP 5
* SSH key (authorized_keys)

### Requirements

Make sure you meet following criteria prior to the deployment:
* ClusterControl node must run on a clean dedicated host with internet connection.
* If you are running as non-root user, make sure the user is able to escalate to root with sudo command.
* For SUSE(SLES) or OpenSUSE Linux, make sure you install tye zypprepo module (Checkout Zypprepo [here](https://forge.puppet.com/modules/puppet/zypprepo/readme)). You can do that by installing it to your puppet master as follows,
```bash
$ puppet module install puppet-zypprepo
```

### Installation

Our ClusterControl module for puppet is available either on [Puppet Forge](https://forge.puppet.com/severalnines/clustercontrol) or using this [Severalnines Puppet](https://github.com/severalnines/puppet) by cloning or downloading it as a zip. Then place it under puppetlabs modulepath directory and make sure to name your module directory as *clustercontrol*, i.e. */etc/puppetlabs/code/environments/production/modules/clustercontrol* for example.

First you need to generate an API Token. To do this, go to $modulepath/clustercontrol/files, then run the following. For example,
```bash
root@master:/etc/puppetlabs/code/environments/production/modules/clustercontrol# files/s9s_helper.sh --generate-token
efc6ac7fbea2da1b056b901541697ec7a9be6a77
```
Reserve that toke which you will use that as an input parameter for your manifests file.

Given the example scenario, let say you have the following hosts:
```
clustercontrol.local 	192.168.1.10
galera1.local 		    192.168.1.11
galera2.local 		    192.168.1.12
galera3.local 		    192.168.1.13
```

Then, create a manifests file, let say we named it *clustercontrol.pp*
```bash
root@master:/etc/puppetlabs/code/environments/production# ls -alth manifests/clustercontrol.pp
-rw-r--r-- 1 root root 1.4K Oct 23 15:00 manifests/clustercontrol.pp
```
Then have the following example puppet agent node below where the hostname of the target to install CC using puppet is 192.168.40.90. Below is the definition for ClusterControl as follows:
```puppet
node 'clustercontrol.puppet.local' { # Applies only to mentioned node. If nothing mentioned, applies to all.
        class { 'clustercontrol':
            is_controller => true,
            cc_hostname => '192.168.40.90',
            mysql_cmon_password => 'R00tP@55',
            api_token => 'efc6ac7fbea2da1b056b901541697ec7a9be6a77',
            ssh_user => 'vagrant'
        }
}
```

Then run the command,
```bash
puppet agent -t
```
on the target clustercontrol, which is the host *clustercontrol.puppet.local* for this example installation.

Once deployment is complete, open the ClusterControl web UI at https://[ClusterControl IP address]/clustercontrol and create a default admin login. You can now start to add existing database node/cluster, or deploy a new one. Ensure that passwordless SSH is configured properly from ClusterControl node to all DB nodes beforehand. 

To setup passwordless SSH on target database nodes, use following commands on ClusterControl node (as ssh_user), e.g:

```bash
ssh-copy-id 192.168.1.11  # galera1
ssh-copy-id 192.168.1.12  # galera2
ssh-copy-id 192.168.1.13  # galera3
```

## Usage

### General Options

#### `is_controller`
Define whether the node is ClusterControl controller host. All database nodes that you want ClusterControl to manage should be set to false.  
**Default: (Boolean) true**

#### `clustercontrol_host`
Specify the IP address of the ClusterControl node. You can specify ClusterControl's FQDN only if the monitored MySQL servers are configured to perform host name resolution (skip-name-resolve is disabled) or MongoDB servers. Only specify this option on nodes that you want to be managed by ClusterControl.  
**Example: (String) '192.168.0.10'**

#### `email_address`
Specify an email as root user for ClusterControl UI. You will login using this email with default password 'admin'.  
**Default: (String) 'admin@domain.com'**

#### `ssh_user`
Specify the SSH user that ClusterControl will use to manage the database nodes. Unless root, make sure this user is in sudoers list.  
**Default: (String) 'root'**

#### `ssh_key`
#####`is_controller`
Define whether the node is ClusterControl controller host. All database nodes that you want ClusterControl to manage should be set to false.  
**Default: (Boolean) true**

##### `clustercontrol_host`
Specify the IP address of the ClusterControl node. You can specify ClusterControl's FQDN only if the monitored MySQL servers are configured to perform host name resolution (skip-name-resolve is disabled) or MongoDB servers. Only specify this option on nodes that you want to be managed by ClusterControl.  
**Example: (String) '192.168.0.10'**

##### `email_address`
Specify an email as root user for ClusterControl UI. You will login using this email with default password 'admin'.  
**Default: (String) 'admin@domain.com'**

##### `ssh_user`
Specify the SSH user that ClusterControl will use to manage the database nodes. Unless root, make sure this user is in sudoers list.  
**Default: (String) 'root'**

##### `ssh_key`
Specify the SSH key used by ``ssh_user`` to perform passwordless SSH to the database nodes.  
**Default: (String) '/home/$USER/.ssh/id_rsa' (non-root,sudoer)**  
**Default: (String) '/root/.ssh/id_rsa' (root)**

#### `ssh_port`
Specify the SSH port used by ClusterControl to SSH into database hosts. All nodes in the cluster must use the same SSH port.  
**Default: (Integer) 22**

#### `sudo_password`
If sudo user has password, specify it here. ClusterControl requires this to automate database recovery or perform other management procedures. If `ssh_user` is root, this will be ignored.  
**Example: (String) 'mysud0p4ssword'**

#### `api_token`
Specify the 40-character ClusterControl token generated from s9s_helper script.  
**Example: (String) 'b7e515255db703c659677a66c4a17952515dbaf5'**

#### `mysql_cmon_root_password`
Specify the MySQL root password for ClusterControl host. This module will install a MySQL server and use this as root password.  
**Default: (String) 'password'**

#### `mysql_cmon_password`
Specify the MySQL password for user cmon. The module will grant this user with specified password, and is needed by ClusterControl.  
**Default: (String) 'cmon'**

#### `mysql_cmon_port`
MySQL server port that holds CMON database.  
**Default: (Integer) 3306**

#### `datadir`
MySQL datadir on ClusterControl node.  
**Default: (String) '/var/lib/mysql'**

#### `modulepath`
The modulepath of your Puppet Server setup, equivalent to what's defined in your environment.conf with the clustercontrol module name.  
**Default:  (String) '/etc/puppetlabs/code/environments/production/modules/clustercontrol/'**


##### `ssh_port`
Specify the SSH port used by ClusterControl to SSH into database hosts. All nodes in the cluster must use the same SSH port.  
**Default (Integer) 22**

##### `sudo_password`
If sudo user has password, specify it here. ClusterControl requires this to automate database recovery or perform other management procedures. If `ssh_user` is root, this will be ignored.  
**Example: (String) 'mysud0p4ssword'**

##### `api_token`
Specify the 40-character ClusterControl token generated from s9s_helper script.  
**Example: (String) 'b7e515255db703c659677a66c4a17952515dbaf5'**

##### `mysql_cmon_root_password`
Specify the MySQL root password for ClusterControl host. This module will install a MySQL server and use this as root password.  
**Default: (String) 'password'**

##### `mysql_cmon_password`
Specify the MySQL password for user cmon. The module will grant this user with specified password, and is needed by ClusterControl.  
**Default: (String) 'cmon'**

##### `mysql_cmon_port`
MySQL server port that holds CMON database.  
**Default: (Integer) 3306**

##### `datadir`
MySQL datadir on ClusterControl node.  
**Default: (String) '/var/lib/mysql'**

##### `disable_firewall`
Disables the firewall by default which is set to true. When disable_firewall is true, it means that flushing the iptables, then stops the ufw/firewalld. If `disable_firewall` is set to false, the module will just do nothing and let your current firewall configuration untouched.  
**Default: (Boolean) true**

##### `disable_os_sec_module`
Disables the OS security module i.e. Apparmor or SELinux, which is by default. It's not the ideal setup for security. Since ClusterControl is a complex software, it's ideal to disable it as its known to have issues when running the cmon daemon, for example with SELinux enabled. You can later enable your security module anyway once you have setup required levels all sorted out. Once you have that, do not forget to change the security module as well so Puppet will not update your current CC setup.  If `disable_os_sec_module` is set to false, the module will just do nothing and let your current Apparmor/SELinux configuration untouched.  
**Default: (Boolean) true**

##### `controller_id`
The `controller_id` is an arbitrary string which ClusterControl requires to work properly. By default, it uses a UUID random string which references the `uuidgen` Linux command which is part of the `libuuid` or util-linux package, so this shall be present in all recent Linux systems we support. Checkout the documentation for the components under the [CMON section](https://severalnines.com/docs/components.html#cmon) for more details.  
**Default: (UUID) string**

##### `is_online_install`
The `is_online_install` option is used to flag whether the type of setup for installation is online (default) or offline. By default, the option `is_online_install` is set to true and it will always rely on the repository to access the internet to download and install OS packages. For more private and encapsulated type of environment, then offline installation is for you. You just have to set the `is_online_install` to false or `is_online_install=false`.  
**Default: (Boolean) true**

##### `cc_packages_path`
The `cc_packages_path` option is a Hash data type which uses key-value. This option defines the following key-value as shown below:

```
## For Debian/Ubuntu
  $cc_packages_path				= {
  	'clustercontrol-controller' => '',
	'clustercontrol' => '',
	'clustercontrol-cloud' => '',
	'clustercontrol-clud' => '',
	'clustercontrol-ssh' => '',
	'clustercontrol-notifications' => '',
	'libs9s' => '',
	's9s-tools' => ''
  },
## For RHEL/CentOS
  $cc_packages_path				= {
  	'clustercontrol-controller' => '',
	'clustercontrol' => '',
	'clustercontrol-cloud' => '',
	'clustercontrol-clud' => '',
	'clustercontrol-ssh' => '',
	'clustercontrol-notifications' => '',
	's9s-tools' => ''
  },
```
The keys has to be exactly as shown above, and its values is the exact full path where the packages are located and it has to be coming from the target host/node where CC is to be installed. To grab the ClusterControl packages, click this page https://severalnines.com/downloads/cmon/?C=M;O=D. For the s9s CLI tools, click check out http://repo.severalnines.com/s9s-tools/. For example, my target hostname called `pupnode2.puppet.local` where ClusterControl will be installed is a Debian 10 (Buster). Then in my manifests file `/etc/puppetlabs/code/environments/production/manifests/clustercontrol.pp`, here's the following:
```
node 'pupnode2.puppet.local' { # Applies only to mentioned node. If nothing mentioned, applies to all.

        class { 'clustercontrol':
                        is_controller => true,
                        cc_hostname => '192.168.40.20',
                        mysql_root_password => 'R00tP@55',
                        mysql_cmon_root_password => 'R00tP@55',
                        mysql_cmon_password => 'R00tP@55',
                        api_token => '6df80ef0cf75be2537f9bd07f00fd35813e5a59b',
                        ssh_user => 'vagrant',
                        is_online_install => false,
                        cc_packages_path => {
                                'clustercontrol-controller' => '/opt/clustercontrol/binaries/clustercontrol-controller-1.8.2-4478-x86_64.deb',
                                'clustercontrol' => '/opt/clustercontrol/binaries/clustercontrol_1.8.2-7804_x86_64.deb',
                                'clustercontrol-cloud' => '/opt/clustercontrol/binaries/clustercontrol-cloud_1.8.2-280_x86_64.deb',
                                'clustercontrol-clud' => '/opt/clustercontrol/binaries/clustercontrol-clud_1.8.2-280_x86_64.deb',
                                'clustercontrol-ssh' => '/opt/clustercontrol/binaries/clustercontrol-ssh_1.8.2-105_x86_64.deb',
                                'clustercontrol-notifications' => '/opt/clustercontrol/binaries/clustercontrol-notifications_1.8.2-267_x86_64.deb',
                                'libs9s' => '/opt/clustercontrol/binaries/s9s_debian_buster/libs9s0_1.8.20210126-release1_amd64.deb',
                                's9s-tools' => '/opt/clustercontrol/binaries/s9s_debian_buster/s9s-tools_1.8.20210126-release1_amd64.deb'
                        }/*
                        cc_packages_path => {
                                'clustercontrol-controller' => '/opt/clustercontrol/binaries/clustercontrol-controller-1.8.2-4478-x86_64.rpm',
                                'clustercontrol' => '/opt/clustercontrol/binaries/clustercontrol-1.8.2-7836-x86_64.rpm',
                                'clustercontrol-cloud' => '/opt/clustercontrol/binaries/clustercontrol-cloud-1.8.2-286-x86_64.rpm',
                                'clustercontrol-clud' => '/opt/clustercontrol/binaries/clustercontrol-clud-1.8.2-286-x86_64.rpm',
                                'clustercontrol-ssh' => '/opt/clustercontrol/binaries/clustercontrol-ssh-1.8.2-105-x86_64.rpm',
                                'clustercontrol-notifications' => '/opt/clustercontrol/binaries/clustercontrol-notifications-1.8.2-267-x86_64.rpm',
                                's9s-tools' => '/opt/clustercontrol/binaries/s9s_el8/s9s-tools-1.8-11.1.x86_64.rpm'
                        }*/
        }
}
``` 
**Default: (Hash) key-value**  

## Limitations

ClusterControl Module for Puppet supports only Debian/Ubuntu and RHEL/CentOS combination of Linux OS versions. From these supported distros, all versions that had passed its EOL or almost reaching its EOL are no longer supported. Below are the supported versions:
* Debian 9.x (stretch)
* Debian 10.x (buster)
* Ubuntu 16.x LTS (Xenial Xerus)
* Ubuntu 18.x LTS(Bionic Beaver)
* Ubuntu 20.04.x LTS (Focal Fossa)
* RHEL/CentOS 7.x/8.x

Puppet Labs has no support yet for the version below,
* Ubuntu 20.10 LTS (Groovy Gorilla)
Once this is totally supported and ClusterControl works, then we'll have it included in the supported versions in the future.


This module only supports bootstrapping MySQL servers with IP address only (it expects skip-name-resolve is enabled on all MySQL nodes). However, for MongoDB you can specify hostname as described under MongoDB Specific Options.

[ClusterControl known issues and limitations](http://www.severalnines.com/docs/troubleshooting.html#known-issues-and-limitations).

## Development

Please report bugs or suggestions via our support channel: [https://support.severalnines.com](https://support.severalnines.com)