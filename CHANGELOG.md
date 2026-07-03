# Changelog

## v3.0.0

Initial production release of the ClusterControl Puppet module for
ClusterControl 2.4.x (MCC architecture).

### Features

- Installs ClusterControl in MCC mode (cmon-proxy based, no Apache/httpd)
- Uses MySQL Community Server 8.4 LTS as the database backend, matching
  Severalnines' official `cc-ansible` reference implementation
- Installs all 9 ClusterControl packages and `s9s-tools` CLI
- `clustercontrol_version` parameter — `'latest'` by default, or pin to
  a specific version (e.g. `'2.3.3'`)
- Marker-guarded idempotency for `cmon-init`, `mcc-init`, and service
  restarts — re-runs complete in 1–2 seconds with zero corrective notices
- Bootstraps `ccsetup` user for GUI registration
- `mysql_native_password` authentication for ClusterControl compatibility
- Automatic SELinux / firewalld disable on RHEL family
- Idempotent cmon user creation across `localhost`, `127.0.0.1`, and
  the controller's primary IP

### Supported operating systems

| Family | Versions |
|---|---|
| RHEL family | RHEL 8 / 9, Rocky Linux 8 / 9, AlmaLinux 8 / 9, Oracle Linux 8 / 9 |
| Ubuntu | 20.04 LTS, 22.04 LTS |
| Debian | 11 (Bullseye), 12 (Bookworm) |

### MySQL Community 8.4 setup

On RHEL family:
- Disables RHEL AppStream `mysql` module
- Imports MySQL 2023 GPG key
- Installs MySQL 8.4 LTS community repo RPM
- Enables `mysql-8.4-lts-community` repo, disables 5.7 / 8.0 streams
- Removes `mariadb-server`, `mariadb`, `mariadb-libs` if present
- Installs `mysql-community-server`, `-client`, `-common`, `-libs`
- Runs `mysqld --initialize-insecure` once on first install

On Debian family:
- Removes `mariadb-server`, `mariadb-client`, `mariadb-common` if present
- Installs `mysql-apt-config.deb` from `repo.mysql.com`
- Pins MySQL packages to `repo.mysql.com` with priority 1001
- Installs `mysql-common` first (must precede `mysql-server`)
- Installs `mysql-common`, `mysql-server`, `mysql-client`

### Files

- `manifests/params.pp` — OS detection, package lists, repo URLs
- `manifests/init.pp` — main class entry point + parameter declarations
- `manifests/install/redhat.pp` — RHEL-family install logic
- `manifests/install/debian.pp` — Debian-family install logic
- `manifests/configure_mysql.pp` — MySQL config + cmon user setup
- `manifests/configure_mcc.pp` — `cmon-init` + `mcc-init` (idempotent)
- `manifests/mcc.pp` — service management + ccsetup user bootstrap
- `templates/my.cnf.erb` — MySQL config with `mysql_native_password = ON`
- `files/ccmgradm_init_wrapper.sh` — wrapper for `mcc-init`
- `files/sync_cmon_admin.sh` — sync admin password helper

### Known limitations

- RHEL 7 / CentOS 7 are not supported: MySQL 8.4 community packages
  are not available for EL7.
- The module replaces any pre-existing MariaDB installation. Migrate
  data manually if upgrading from a MariaDB-based ClusterControl setup.
- Ubuntu 24.04 (Noble) is not yet validated: Puppet 8 agent support
  on Noble has open compatibility issues. Use Ubuntu 22.04 LTS instead.
- LXC containers may exhibit systemd cgroup tracking quirks that are
  outside the module's control. Use real VMs for production.
