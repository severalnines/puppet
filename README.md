# clustercontrol

## Table of Contents

1. [Overview](#overview)
2. [Module Description](#module-description)
3. [Setup](#setup)
   * [Requirements](#requirements)
   * [Pre-installation](#pre-installation)
   * [Installation](#installation)
4. [Usage](#usage)
5. [Version Management](#version-management)
6. [Idempotency & Upgrades](#idempotency--upgrades)
7. [Limitations](#limitations)
8. [Development](#development)

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
- Download and installs dependencies. For ClusterControl 2.4.x in MCC mode these are minimal — **MariaDB server is required, and Apache + PHP are no longer needed** (the web UI is served directly by `cmon-proxy`).
- Install ClusterControl components: `clustercontrol-controller`, `clustercontrol-mcc`, `clustercontrol-proxy`, `clustercontrol-kuber-proxy`, `clustercontrol-notifications`, `clustercontrol-ssh`, `clustercontrol-cloud`, `clustercontrol-clud`, and `s9s-tools`.
- Configures `cmon-proxy` to serve the web UI on port 443 (HTTPS).
- Automates MariaDB installation:
  - Creates the `cmon` database, grants the `cmon` user for `localhost`, `127.0.0.1`, and the controller's IP, and configures the DB connection for ClusterControl.
- Initializes the controller (`cmon --init`) and registers it with `cmon-proxy` (`ccmgradm init`), guarded by state markers so re-runs are safe.
- Creates the `ccsetup` bootstrap user via the `s9s` CLI so the first-time GUI registration flow works automatically.
- Disables SELinux/AppArmor by default (configurable). *You can enable once set up correctly.*

If you have any questions, feel free to raise issues via <https://github.com/severalnines/puppet/issues> or via the [Community Forums](https://support.severalnines.com/hc/en-us/community/topics) or [Slack](https://join.slack.com/t/clustercontrol/shared_invite/zt-b15k9477-jLllD6qJOUm3bGnOWynVig).

## Setup

### What ClusterControl affects

- Severalnines yum/apt repository
- ClusterControl controller, MCC, proxy, kuber-proxy, notifications, SSH, cloud and clud packages
- The `s9s-tools` CLI package
- SELinux/AppArmor (disabled by default — configurable)
- MariaDB server and client
- `cmon-proxy` web server listening on port 443
- The `ccsetup` bootstrap user (one-time, removed by the GUI after first registration)

### Requirements

Make sure you meet the following criteria prior to deployment:

- ClusterControl node must run on a **clean dedicated host** with internet connection.
- If you are running as a non-root user, make sure the user can escalate to root via `sudo`.
- **Puppet 7 or 8** is required on master and agent.

### Pre-installation

No API token generation is required (CC 2.4.x removed the API token concept — the `ccsetup` bootstrap user replaces it). On first GUI access, you authenticate with `ccsetup` / `admin` and are redirected to a registration page where you create your real admin user.

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

With the following minimal node definition (only two required parameters — see [Parameter Migration from v2.x](#parameter-migration-from-v2x) below if you're upgrading from an older module):

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

The MariaDB root password. This module will set the root user with this password during installation. **(Required)**
**Example: (String) `'R00tP@55'`**

#### `cmon_mysql_password`

The MariaDB password for user `cmon`. The module will grant this user with the specified password for `localhost`, `127.0.0.1`, and the controller's IP address (the host running ClusterControl). Required by ClusterControl to access its own `cmon` database. **(Required)**
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

How to manage ClusterControl package versions when `clustercontrol_version` is not set:
- `'latest'` — always upgrade to the newest version available in the repo.
- `'present'` — install if missing; do not upgrade if already installed.

When `clustercontrol_version` is set, that parameter takes precedence. See [Version Management](#version-management).
**Default: (Enum) `'latest'`**

#### `clustercontrol_version`

Optional. Pin all ClusterControl packages to a specific version (e.g. `'2.4.0'`). Overrides `cc_package_state` for ClusterControl packages. Re-runs are idempotent. Upgrades happen by changing this value and re-applying. See [Version Management](#version-management).
**Default: (Optional[String]) `undef`**

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

### Parameter Migration from v2.x

If you used the previous version (v2.0.0, for ClusterControl 1.9.x), the following parameters have changed in v3.0.0. The required parameter count dropped from **7 to 2**.

| Old (v2.0.0) | Status in v3.0.0 | Notes |
|---|---|---|
| `is_controller` | ❌ Removed | Module always installs the controller; no separate agent mode |
| `cc_hostname` | ❌ Removed | Auto-detected from `$facts['networking']['ip']` |
| `mysql_cmon_password` | 🔄 Renamed → `cmon_mysql_password` | Naming-convention consistency |
| `mysql_cmon_root_password` | 🔄 Renamed → `mysql_root_password` | Cleaner name |
| `mysql_cmon_port` | 🔄 Renamed → `cmon_mysql_port` | Naming-convention consistency |
| `api_token` | ❌ Removed | Obsolete in CC 2.4.x — `ccsetup` user replaces it |
| `ssh_user` / `ssh_user_group` / `ssh_key` / `ssh_port` / `sudo_password` | ❌ Removed | No more SSH-based remote deployment from the module |
| `only_cc_v2` | ❌ Removed | v3.0.0 only supports CC 2.4.x (MCC) — flag is implicit |
| `email_address` | ❌ Removed | GUI registration handles this |
| `is_online_install` / `cc_packages_path` | ❌ Removed | Offline install no longer supported — use online repos |
| `controller_id` | ❌ Removed | Auto-generated |
| `modulepath` / `datadir` | ❌ Removed | Use Puppet defaults |
| `disable_firewall` | ✅ Kept | Same behavior |
| `disable_os_sec_module` | 🔄 Renamed → `disable_selinux` | More explicit |

## Version Management

The module supports three patterns for managing the ClusterControl version installed and upgraded over time. Pick the one that matches your operational policy.

### Pattern 1 — Always Install Latest (Default)

For development or when you always want the newest ClusterControl:

```
node 'clustercontrol.local' {
    class { 'clustercontrol':
        mysql_root_password => 'R00tP@55',
        cmon_mysql_password => 'R00tP@55',
    }
}
```

- Installs the latest available version on first run.
- **Every subsequent Puppet run** automatically upgrades to the newest version published in the Severalnines repo.
- Simple, but you have no control over when upgrades happen.

### Pattern 2 — Pin to a Specific Version (Recommended for Production)

For production or staging where you want a known, tested version:

```
node 'clustercontrol.local' {
    class { 'clustercontrol':
        mysql_root_password    => 'R00tP@55',
        cmon_mysql_password    => 'R00tP@55',
        clustercontrol_version => '2.4.0',
    }
}
```

- All ClusterControl packages installed at version `2.4.0`.
- Within that version, the latest available **build** is selected (e.g. `2.4.0-19927`) — so you still get bug-fix builds within the version.
- Will **NOT** auto-upgrade to a different version (e.g. `2.4.1` or `2.5.0`).
- Re-running Puppet is idempotent: no changes if already at the pinned version.

**Note about builds:** Each ClusterControl package has its own independent build counter (e.g. `controller-2.4.0-19927`, `mcc-2.4.0-857`, `proxy-2.4.0-1234`). When you pin to `'2.4.0'`, each package gets its own latest build matching that version. `s9s-tools` (the CLI) is always `latest` because it tracks an independent version stream.

### Pattern 3 — Controlled Upgrade Workflow

To upgrade in a controlled way when Severalnines releases a new version, change the value and re-apply the manifest:

```
# Step 1 — currently deployed:
clustercontrol_version => '2.4.0',

# Step 2 — Severalnines releases 2.4.1. Update the manifest:
clustercontrol_version => '2.4.1',

# Step 3 — Re-run Puppet on the agent
$ puppet agent -t
# → Module upgrades all CC packages from 2.4.0 to 2.4.1.
```

This is the **safest production pattern**: you choose when to upgrade, you test the new version first, and you roll forward (or backward) deliberately.

### Installing an Older Version

If you need to install a non-latest version (for compatibility testing, rollback, etc.), pin to it:

```
node 'clustercontrol.local' {
    class { 'clustercontrol':
        mysql_root_password    => 'R00tP@55',
        cmon_mysql_password    => 'R00tP@55',
        clustercontrol_version => '2.3.1',
    }
}
```

The older version must still be available in the Severalnines repository. Verify with:

```
# RHEL/Rocky/AlmaLinux
dnf --showduplicates list clustercontrol-mcc

# Ubuntu/Debian
apt-cache madison clustercontrol-mcc
```

### Disable Auto-Upgrade Without Pinning a Version

If you want to **freeze the current state** without specifying an exact version:

```
class { 'clustercontrol':
    mysql_root_password => 'R00tP@55',
    cmon_mysql_password => 'R00tP@55',
    cc_package_state    => 'present',
}
```

`present` means *"install if missing; do not upgrade if already installed."*

## Idempotency & Upgrades

This module is fully idempotent and supports controlled ClusterControl upgrades. To ensure safe and consistent execution, the process follows these rules:

- **MySQL initialization runs only once** during the first installation. The root password is set once; subsequent runs detect the existing password and skip the bootstrap step.
- **CMON initialization is marker-guarded.** `cmon --init` runs exactly once, tracked by `/var/lib/cmon/.puppet-cmon-initialized`.
- **MCC initialization is marker-guarded.** `ccmgradm init` runs exactly once, tracked by `/var/lib/cmon/.puppet-mcc-initialized`. A wrapper script treats "Controller already exists" as success for re-run safety.
- **Safe to re-run the manifest.** Repeated `puppet agent -t` runs are no-ops after a successful deployment (typical re-run time: under 2 seconds).
- **Safe to upgrade by changing `clustercontrol_version`.** Change the value and re-apply the manifest to perform a controlled upgrade. See [Version Management](#version-management) above.

State markers stored in `/var/lib/cmon`:

| Marker | Purpose |
|---|---|
| `.puppet-cmon-initialized` | `cmon --init` completed |
| `.puppet-mcc-initialized` | `ccmgradm init` completed |
| `.puppet-services-restarted` | First post-init service restart cycle done |
| `.puppet-cmon-password-synced` | Admin password sync between `/etc/s9s.conf` and the `cmon` DB done |

## Limitations

ClusterControl Module for Puppet supports only Debian/Ubuntu and RHEL/CentOS/Alma/Oracle/Rocky Linux. From these supported distros, all versions that have passed their EOL or are nearly EOL are no longer supported. Below are the supported versions:

- Debian 9.x (Stretch)
- Debian 10.x (Buster)
- Debian 11.x (Bullseye)
- Debian 12.x (Bookworm)
- Ubuntu 18.04 LTS (Bionic Beaver)
- Ubuntu 20.04 LTS (Focal Fossa)
- Ubuntu 22.04 LTS (Jammy Jellyfish)
- Ubuntu 24.04 LTS (Noble Numbat)
- AlmaLinux / Oracle Linux / Rocky Linux / RHEL / CentOS 7.x / 8.x / 9.x

**Real-VM validation status (as of this release):**

| OS | Catalog Compile | Real-VM End-to-End |
|---|---|---|
| Rocky Linux 9 | ✅ | ✅ |
| AlmaLinux 9 | ✅ | ✅ |
| Ubuntu 22.04 | ✅ | ✅ |
| RHEL 9 | ✅ | ⏳ Pending |
| Rocky Linux 8 | ✅ | ⏳ Pending |
| Debian 12 | ✅ | ⏳ Pending |
| Ubuntu 24.04 | ✅ | — Removed from active testing (upstream Puppet 8 packaging gap on `noble`) |

**SLES support:** v3.0.0 does not yet support SUSE/SLES. If you need it, please open an issue.

**ClusterControl UI version 1 (CCv1) is no longer supported by this module.** CCv1 is end-of-life upstream. If you need CCv1, use the older v2.0.0 of this module (which itself is no longer maintained).

This module only supports bootstrapping the ClusterControl host itself. It does **not** SSH out to manage database nodes — passwordless SSH from the ClusterControl host to your database nodes must be configured separately (typically through the ClusterControl GUI after deployment).

This module configures MariaDB with `skip-name-resolve` enabled, so the `cmon` user is granted only on `localhost`, `127.0.0.1`, and the controller's IP address (not hostnames).

[ClusterControl known issues and limitations](http://www.severalnines.com/docs/troubleshooting.html#known-issues-and-limitations).

## Development

This module is structured into focused classes that handle each phase of the install. Re-runs are idempotent.

| Class | Responsibility |
|---|---|
| `clustercontrol::params` | OS detection, package/repo definitions |
| `clustercontrol::install::redhat` | RHEL-family package + repo setup |
| `clustercontrol::install::debian` | Debian/Ubuntu package + repo setup |
| `clustercontrol::configure_mysql` | MariaDB config + `cmon` user grants |
| `clustercontrol::configure_mcc` | `cmon --init` + `ccmgradm init` (marker-guarded) |
| `clustercontrol::mcc` | Service management + `ccsetup` bootstrap user |

Tests:
- Run rspec-puppet locally: `bundle exec rspec spec/`
- Multi-OS catalog tests run automatically via GitHub Actions on every push/PR.

Please report bugs or suggestions via our support channel: <https://support.severalnines.com>
