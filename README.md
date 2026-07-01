# clustercontrol

## Table of Contents

1. [Overview](#overview)
2. [Module Description](#module-description)
3. [Setup](#setup)
   * [Requirements](#requirements)
   * [Installation](#installation)
4. [Usage](#usage)
5. [Multi-Node Deployment](#multi-node-deployment)
6. [Installation & Upgrade Behavior](#installation--upgrade-behavior)
7. [Idempotency & Upgrades](#idempotency--upgrades)
8. [Limitations](#limitations)
9. [Development](#development)

## Overview

Installs ClusterControl for your new database node/cluster deployment or on top of your existing database node/cluster. ClusterControl is a management and automation software for database clusters. It helps deploy, monitor, manage and scale your database cluster. This module will install ClusterControl and configure it to manage and monitor an existing database cluster.

Supported database clusters managed by ClusterControl (deployed/managed via the ClusterControl UI after this module installs CC):

- MySQL Replication (Percona/MariaDB/Oracle MySQL)
- MySQL Galera (Percona XtraDB/MariaDB)
- MySQL Cluster (NDB)
- TimescaleDB
- PostgreSQL (Single or Streaming Replication, including pgvector and EnterpriseDB)
- MongoDB ReplicaSet (Percona/MongoDB) including MongoDB Enterprise
- MongoDB Shards (Percona/MongoDB) including MongoDB Enterprise
- MS SQL Server 2022
- Redis Sentinel
- Elasticsearch

More details at [Severalnines ClusterControl](http://www.severalnines.com/clustercontrol) website.

## Module Description

The Puppet module for ClusterControl automates the following actions:

- Setup of ClusterControl required repositories (Severalnines repo, with modern signed-by GPG keyrings on Debian/Ubuntu).
- Download and installs dependencies. For ClusterControl 2.4.x in MCC mode these are minimal — **MySQL Community Server 8.4 is required, and Apache + PHP are no longer needed** (the web UI is served directly by `cmon-proxy`).
- Install ClusterControl components: `clustercontrol-controller`, `clustercontrol-mcc`, `clustercontrol-proxy`, `clustercontrol-kuber-proxy`, `clustercontrol-notifications`, `clustercontrol-ssh`, `clustercontrol-cloud`, `clustercontrol-clud`, and `s9s-tools`.
- Configures `cmon-proxy` to serve the web UI on port 443 (HTTPS).
- Automates MySQL installation:
  - Creates the `cmon` database, grants the `cmon` user for `localhost`, `127.0.0.1`, and the controller's IP, and configures the DB connection for ClusterControl.
- Initializes the controller (`cmon --init`) and registers it with `cmon-proxy` (`ccmgradm init`), guarded by state markers so re-runs are safe.
- Creates the `ccsetup` bootstrap user via the `s9s` CLI so the first-time GUI registration flow works automatically.
- Disables SELinux by default on RHEL-family systems (configurable). *You can enable once set up correctly.*

If you have any questions, feel free to raise issues via <https://github.com/severalnines/puppet/issues> or via the [Community Forums](https://support.severalnines.com/hc/en-us/community/topics) or [Slack](https://join.slack.com/t/clustercontrol/shared_invite/zt-b15k9477-jLllD6qJOUm3bGnOWynVig).

## Setup

### What ClusterControl affects

- Severalnines yum/apt repository
- ClusterControl controller, MCC, proxy, kuber-proxy, notifications, SSH, cloud and clud packages
- The `s9s-tools` CLI package
- SELinux/AppArmor (disabled by default — configurable)
- MySQL Community Server 8.4 server and client
- `cmon-proxy` web server listening on port 443
- The `ccsetup` bootstrap user (one-time, removed by the GUI after first registration)

### Requirements

Make sure you meet the following criteria prior to deployment:

- ClusterControl node must run on a **clean dedicated host** with internet connection.
- If you are running as a non-root user, make sure the user can escalate to root via `sudo`.
- **Puppet 7 or 8** is required on master and agent.

### Installation

This ClusterControl module for Puppet is available either on [Puppet Forge](https://forge.puppet.com/severalnines/clustercontrol) or by cloning this repository directly. Place it under your Puppet master's modulepath directory and make sure the directory is named `clustercontrol`, e.g. `/etc/puppetlabs/code/environments/production/modules/clustercontrol`.

```
$ cd /etc/puppetlabs/code/environments/production/modules
$ git clone https://github.com/severalnines/puppet.git clustercontrol
```

Given the example scenario, let's say you have the following host:

```
clustercontrol.local    192.168.1.10
```

Then, create a manifest file, e.g. `clustercontrol.pp`:

```
root@master:/etc/puppetlabs/code/environments/production# ls -alth manifests/clustercontrol.pp
-rw-r--r-- 1 root root 1.4K Oct 23 15:00 manifests/clustercontrol.pp
```

With the following minimal node definition (only two required parameters):

```
node 'clustercontrol.local' { # Applies only to the mentioned node. If nothing mentioned, applies to all.
    class { 'clustercontrol':
        mysql_root_password => 'R00tP@55',
        cmon_mysql_password => 'R00tP@55',
    }
}
```

Then run the command on the target ClusterControl host:

```
puppet agent -t
```

Once deployment is complete, open the ClusterControl web UI at `https://<ClusterControl_host>/` and you will be redirected to the registration page. Authenticate with the `ccsetup` / `admin` credentials (created automatically by this module) and create your real admin user. The `ccsetup` user is removed by ClusterControl after registration.

## Usage

### Available Options

#### `mysql_root_password`

The MySQL root password. This module will set the root user with this password during installation. **(Required)**
**Example: (String) `'R00tP@55'`**

#### `cmon_mysql_password`

The MySQL password for user `cmon`. The module will grant this user with the specified password for `localhost`, `127.0.0.1`, and the controller's IP address (the host running ClusterControl). Required by ClusterControl to access its own `cmon` database. **(Required)**
**Default: (String) `'cmon'`**

#### `mysql_root_username`

The MariaDB root username. It's recommended to keep the default.
**Default: (String) `'root'`**

#### `cmon_mysql_user`

The MariaDB super user account username for ClusterControl. It's recommended to keep the default.
**Default: (String) `'cmon'`**

#### `cmon_mysql_port`

MySQL/MariaDB server port that holds the `cmon` database.
**Default: (Integer) `3306`**

#### `cc_install_mode`

Install mode for ClusterControl. Only `mcc` is implemented in this module (modern CC 2.4.x with `cmon-proxy`). Legacy CCv1 with Apache + PHP is no longer supported.
**Default: (Enum) `'mcc'`**

#### `cc_package_state`

How to manage ClusterControl package versions:
- `'latest'` — always upgrade to the newest version available in the repo (default behavior on every Puppet run).
- `'present'` — install if missing; do not upgrade if already installed.

**Default: (Enum) `'latest'`**

#### `clustercontrol_version`

Which version of ClusterControl packages to install. Use `'latest'` for the newest available version in the Severalnines repository, or pin to a specific version like `'2.3.3'`. Re-runs are idempotent. Upgrades happen when you change this value and re-apply the manifest.

When set to a specific version, `clustercontrol-controller`, `clustercontrol-proxy`, `clustercontrol-mcc`, `clustercontrol-notifications`, `clustercontrol-ssh`, `clustercontrol-cloud`, and `clustercontrol-clud` are pinned to that version. The `clustercontrol-kuber-proxy` and `s9s-tools` packages are always installed at the latest available version regardless of this setting, because they follow independent version streams.

**Default: (String) `'latest'`**

#### `mcc_web_port`

HTTPS port for the ClusterControl GUI served by `cmon-proxy`.
**Default: (Integer) `443`**

#### `mcc_web_root`

Filesystem path to the ClusterControl MCC web root.
**Default: (String) `'/var/www/html/clustercontrol-mcc'`**

#### `disable_selinux`

Disables SELinux on RHEL-family systems. ClusterControl is a complex piece of software and historically has SELinux issues with the `cmon` daemon. You can re-enable SELinux once you have your contexts sorted out. If set to `false`, the module will leave SELinux untouched.
**Default: (Boolean) `true`**

#### `disable_firewall`

Disables `firewalld` on RHEL-family systems. If set to `false`, the module will leave your current firewall configuration untouched.
**Default: (Boolean) `true`**

## Multi-Node Deployment

The same manifest can be applied to many ClusterControl hosts. Each agent compiles its own catalog from the master and applies the configuration locally — so deploying 5 or more hosts uses the same code.

### Manifest for Multiple Identical Nodes

If you have several CC hosts using the same configuration, list them comma-separated in a single `node` block:

```
node 'clustercontrol1.local',
     'clustercontrol2.local',
     'clustercontrol3.local',
     'clustercontrol4.local',
     'clustercontrol5.local' {
    class { 'clustercontrol':
        mysql_root_password => 'R00tP@55',
        cmon_mysql_password => 'R00tP@55',
    }
}
```

Each host receives an independent ClusterControl installation. Their own MySQL, their own `cmon-proxy` on port 443, their own GUI.

## Installation & Upgrade Behavior

The module installs the **latest** version of ClusterControl available in the Severalnines repository and handles in-place upgrades automatically when newer versions are released.

### Default Behavior — Install Latest and Auto-Upgrade

```
node 'clustercontrol.local' {
    class { 'clustercontrol':
        mysql_root_password => 'R00tP@55',
        cmon_mysql_password => 'R00tP@55',
    }
}
```

- On first run, installs the latest available version of all ClusterControl packages.
- On subsequent Puppet runs, automatically upgrades any package whose newer version becomes available in the Severalnines repo (because `cc_package_state` defaults to `'latest'`).
- This is the same behavior as cc-ansible's default mode.

### Re-running Puppet After Successful Install

When no new versions are available, repeated `puppet agent -t` runs are no-ops:

- Re-runs complete in under a couple of seconds.
- No packages reinstalled, no services restarted.
- State markers in `/var/lib/cmon` ensure `cmon --init` and `ccmgradm init` each run exactly once.

See [Idempotency & Upgrades](#idempotency--upgrades) below for the complete idempotency contract.

### Upgrading When Severalnines Releases a New Version

You don't need to do anything special for upgrades — they happen automatically:

1. Severalnines publishes (for example) ClusterControl 2.5.0 to their repository.
2. On the agent's next Puppet run (`puppet agent -t`), the module detects new versions and upgrades all CC packages in place.
3. `cmon` services restart as needed; the GUI keeps working.

If you prefer to upgrade only on demand (no automatic upgrades during scheduled Puppet runs), set `cc_package_state => 'present'`:

```
class { 'clustercontrol':
    mysql_root_password => 'R00tP@55',
    cmon_mysql_password => 'R00tP@55',
    cc_package_state    => 'present',
}
```

With `'present'`:
- First run installs the latest available version.
- Subsequent Puppet runs do **not** upgrade packages, even if newer versions are in the repo.
- To trigger an upgrade later, temporarily set back to `'latest'`, run Puppet once, then return to `'present'`. Or use the OS-level package manager (`dnf upgrade clustercontrol-*` / `apt upgrade 'clustercontrol-*'`).

### Pinning To A Specific Version

To install a specific version of ClusterControl (rather than always tracking the latest), set the `clustercontrol_version` parameter to the version string:

```
class { 'clustercontrol':
    mysql_root_password    => 'R00tP@55',
    cmon_mysql_password    => 'R00tP@55',
    clustercontrol_version => '2.3.3',
}
```

This installs `clustercontrol-controller`, `clustercontrol-proxy`, `clustercontrol-mcc`, `clustercontrol-notifications`, `clustercontrol-ssh`, `clustercontrol-cloud`, and `clustercontrol-clud` at version `2.3.3`. To upgrade later, change the value and re-apply the manifest.

**Always-latest exceptions:** The following two packages are always installed at the latest available version, regardless of `clustercontrol_version`:

- `clustercontrol-kuber-proxy` — the Kubernetes integration add-on. Its RPM build separator (an underscore between version and build, e.g. `2.4.0_638`) does not match the user-facing version string, so version pinning is unreliable. Installing the latest available build is safe; it tracks the controller.
- `s9s-tools` — the CLI client follows an independent version stream from the main ClusterControl release.

If you need to lock these to a specific build for compliance reasons, do it at the OS level: use `dnf versionlock` (RHEL family) or `apt-mark hold` / `/etc/apt/preferences.d/` (Debian family).

## Idempotency & Upgrades

This module is fully idempotent and supports controlled ClusterControl upgrades. To ensure safe and consistent execution, the process follows these rules:

- **MySQL initialization runs only once** during the first installation. The root password is set once; subsequent runs detect the existing password and skip the bootstrap step.
- **CMON initialization is marker-guarded.** `cmon --init` runs exactly once, tracked by `/var/lib/cmon/.puppet-cmon-initialized`.
- **MCC initialization is marker-guarded.** `ccmgradm init` runs exactly once, tracked by `/var/lib/cmon/.puppet-mcc-initialized`. A wrapper script treats "Controller already exists" as success for re-run safety.
- **Safe to re-run the manifest.** Repeated `puppet agent -t` runs are no-ops after a successful deployment (typical re-run time: under 2 seconds).
- **Safe to upgrade automatically.** With `clustercontrol_version => 'latest'` (the default), the next Puppet run after Severalnines publishes a newer version performs an in-place upgrade of all ClusterControl packages and restarts the affected services.
- **Safe to upgrade by changing `clustercontrol_version`.** When pinned to a specific version, change the value and re-apply the manifest to perform a controlled upgrade. See [Installation & Upgrade Behavior](#installation--upgrade-behavior) above.

State markers stored in `/var/lib/cmon`:

| Marker | Purpose |
|---|---|
| `.puppet-cmon-initialized` | `cmon --init` completed |
| `.puppet-mcc-initialized` | `ccmgradm init` completed |
| `.puppet-services-restarted` | First post-init service restart cycle done |
| `.puppet-cmon-password-synced` | Admin password sync between `/etc/s9s.conf` and the `cmon` DB done |

## Limitations

ClusterControl Module for Puppet supports only Debian/Ubuntu and RHEL/CentOS/Alma/Oracle/Rocky Linux. From these supported distros, all versions that have passed their EOL or are nearly EOL are no longer supported. Below are the supported versions:

- Debian 11.x (Bullseye)
- Debian 12.x (Bookworm)
- Ubuntu 20.04 LTS (Focal Fossa)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 24.04 LTS (Noble Numbat) (catalog-only / pending real VM validation)

**SLES support:** v3.0.0 does not yet support SUSE/SLES. If you need it, please open an issue.

**ClusterControl UI version 1 (CCv1) is no longer supported by this module.** CCv1 is end-of-life upstream. If you need CCv1, use the older v2.0.0 of this module (which itself is no longer maintained).

This module only supports bootstrapping the ClusterControl host itself. It does **not** SSH out to manage database nodes — passwordless SSH from the ClusterControl host to your database nodes must be configured separately (typically through the ClusterControl GUI after deployment).

This module configures MySQL with `skip-name-resolve` enabled, so the `cmon` user is granted only on `localhost`, `127.0.0.1`, and the controller's IP address (not hostnames).

[ClusterControl known issues and limitations](http://www.severalnines.com/docs/troubleshooting.html#known-issues-and-limitations).

## Development

This module is structured into focused classes that handle each phase of the install. Re-runs are idempotent.

| Class | Responsibility |
|---|---|
| `clustercontrol::params` | OS detection, package/repo definitions |
| `clustercontrol::install::redhat` | RHEL-family package + repo setup |
| `clustercontrol::install::debian` | Debian/Ubuntu package + repo setup |
| `clustercontrol::configure_mysql` | MySQL config + `cmon` user grants |
| `clustercontrol::configure_mcc` | `cmon --init` + `ccmgradm init` (marker-guarded) |
| `clustercontrol::mcc` | Service management + `ccsetup` bootstrap user |

Tests:
- Run rspec-puppet locally: `bundle exec rspec spec/`
- Multi-OS catalog tests run automatically via GitHub Actions on every push/PR.

Please report bugs or suggestions via our support channel: <https://support.severalnines.com>
