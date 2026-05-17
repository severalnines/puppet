# Puppet Module: ClusterControl

Installs and configures Severalnines ClusterControl on RHEL/CentOS/Rocky/AlmaLinux or Debian/Ubuntu servers. This module is **idempotent** and **upgrade-safe**.

The following packages are installed:

- `clustercontrol-controller`
- `clustercontrol-mcc`
- `clustercontrol-proxy`
- `clustercontrol-ssh`
- `clustercontrol-cloud`
- `clustercontrol-notifications`
- `clustercontrol-clud`
- `clustercontrol-kuber-proxy`
- `s9s-tools`

## Overview

Installs ClusterControl 2.4.x using **MCC mode** (`cmon-proxy` as the web server, no Apache required).

Supported database clusters managed by ClusterControl:

- MySQL/MariaDB Replication
- Percona XtraDB Cluster
- MariaDB Cluster (Galera)
- MySQL Cluster
- MongoDB Replica Set / Sharded Cluster
- PostgreSQL Streaming Replication
- TimescaleDB Streaming Replication

## Supported Operating Systems

| OS | Versions |
|---|---|
| RHEL / CentOS / Rocky / AlmaLinux / OracleLinux | 7, 8, 9 |
| Ubuntu | 18.04, 20.04, 22.04, 24.04 |
| Debian | 9, 10, 11, 12 |

## Requirements

- ClusterControl server must run on a **clean dedicated host** with internet access.
- Root access.
- Puppet 7 or 8.

## Installation

Clone the module into your Puppet modules directory:

```bash
cd /etc/puppetlabs/code/environments/production/modules
git clone https://github.com/severalnines/puppet.git clustercontrol
```

## Example Manifest

```puppet
node 'your-cc-host' {
  class { 'clustercontrol':
    mysql_root_password => 'MySQLRootPassw0rd!',
    cmon_mysql_password => 'MySQLCmonPassw0rd!',
    cc_install_mode     => 'mcc',
    cc_package_state    => 'latest',
    mcc_web_port        => 443,
    mcc_web_root        => '/var/www/html/clustercontrol-mcc',
  }
}
```

Apply on the target host:

```bash
puppet agent -t
```

Once installation is complete, access the ClusterControl UI at:

```
https://<clustercontrol-host>/
```

**Note:** On first access, you'll be redirected to a registration page where you create your admin user. The username `admin` is reserved — pick a different one.

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `mysql_root_password` | String | (required) | MySQL root password |
| `cmon_mysql_password` | String | (required) | Password for the `cmon` database user |
| `cmon_mysql_user` | String | `cmon` | DB username for cmon |
| `cmon_mysql_port` | Integer | `3306` | MySQL port |
| `cc_install_mode` | Enum | `mcc` | Only `mcc` is implemented |
| `cc_package_state` | Enum | `latest` | `latest` or `present` |
| `mcc_web_port` | Integer | `443` | Port for the web GUI |
| `mcc_web_root` | String | `/var/www/html/clustercontrol-mcc` | Web root |
| `disable_selinux` | Boolean | `true` | Disable SELinux on RHEL-family |
| `disable_firewall` | Boolean | `true` | Disable firewalld on RHEL-family |

## Architecture

The module is split into focused classes that handle each phase of the install:

| Puppet class | Responsibility |
|---|---|
| `clustercontrol::params` | OS detection, package/repo definitions |
| `clustercontrol::install::redhat` | RHEL-family package + repo setup |
| `clustercontrol::install::debian` | Debian/Ubuntu package + repo setup |
| `clustercontrol::configure_mysql` | MySQL config + cmon user grants |
| `clustercontrol::configure_mcc` | `cmon --init` + `ccmgradm init` (idempotent via markers) |
| `clustercontrol::mcc` | Service management + ccsetup user |

State markers (`/var/lib/cmon/.puppet-cmon-initialized` and `.puppet-mcc-initialized`) ensure `cmon --init` and `ccmgradm init` each run exactly once.

## License

Apache-2.0
