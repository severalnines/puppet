## 3.0.0 (2025-05-16)

### Breaking Changes
- Package `clustercontrol2` renamed to `clustercontrol-mcc` (CC 2.x package rename).
  Update any `cc_packages_path` hashes in offline deployments accordingly.
- `$cc_v2_config_ui_file` path changed from `/var/www/html/clustercontrol2/config.js`
  to `/var/www/html/clustercontrol-mcc/config.js`.

### New Features
- **ClusterControl 2.4.x support** – aligned with the current stable release.
- **Ubuntu 24.04 LTS (Noble Numbat)** support added.
- **Debian 12 (Bookworm)** support added.
- **AlmaLinux / Rocky Linux 8 & 9** explicitly listed in `metadata.json`.
- **OracleLinux 7, 8, 9** explicitly listed in `metadata.json`.
- New packages `clustercontrol-proxy` and `clustercontrol-kuber-proxy` are now
  installed and managed as services (`cmon-proxy`, `kuber-proxy`).
- CMON initialisation now uses `cmon --init` (matches the official manual
  installation procedure) instead of writing `/etc/cmon.cnf` directly via template.
- `ccmgradm init` is called to initialise the CCv2 web application.
- `/etc/default/cmon` is now created automatically with `EVENTS_CLIENT` and
  `CLOUD_SERVICE` endpoints.
- APT repository setup uses the modern `/etc/apt/keyrings/` method (replaces
  deprecated `apt-key`), compatible with Ubuntu 22+ and Debian 12+.
- Ubuntu 24.04: uses `mariadb-server` / `mariadb-client` instead of the
  snap-packaged `mysql-server`.
- New `$cc_packages_path` keys for offline install: `clustercontrol-mcc`,
  `clustercontrol-proxy`, `clustercontrol-kuber-proxy`.

### Fixes
- Version ceiling for Debian raised from `>= 11` to `>= 14` (future-proof).
- Version ceiling for Ubuntu raised from `>= 23` to `>= 26` (future-proof).
- `CREATE USER IF NOT EXISTS` used for cmon DB grants to avoid duplicate-user
  errors on re-runs.
- Removed Apache port 19501 proxy listener from `cc-proxy.conf` template
  (handled internally by `cmon-proxy` service in CC 2.x).

---

## 2.0.0 (2024-04-29)

- Deploys ClusterControl 1.9.8.
- CCv1 + CCv2 or CCv2-only (`only_cc_v2` parameter).
- CCv2 no longer depends on PHP.
- Automates PHP 7.4 setup for RHEL 9 and Ubuntu 22.04 when CCv1 is required.
- Fixes `controller_id` handling in `/etc/cmon.cnf`.
- Tested: EL 9, Debian 11, Ubuntu 22.04, SLES 15.x.

## 1.0.0 (2021-04-29)

- ClusterControl 1.8.2 support (LDAP, PgBouncer, new User Management).
- Offline installation support.

## 0.1.10 (2020-11-17)

- Conditional handling for `disable_firewall` / `disable_os_sec_module`.

## 0.1.9 (2020-11-17)

- RHEL 8 firewalld HTTP/HTTPS fix.
- `controller_id` UUID format fix for CC 1.8.x.

## 0.1.8 (2020-11-04)

- Bug fix: GitHub issue #6.

## 0.1.7 (2020-10-23)

- Ubuntu 20.04 (Focal Fossa) fixes.
- Added RHEL/CentOS 8, Debian 9/10, Ubuntu 18.04/20.04.

## 0.1.6 (2020-10-23)

- ClusterControl v1.8.0 compatibility.

## 0.1.5 (2016-05-04)

- ClusterControl v1.3.0. Added `rpc_key` / `RPC_TOKEN` configuration.

## 0.1.4 (2015-11-26)

- RHEL/CentOS 7, Debian 8, PostgreSQL support.

## 0.1.3 (2014-09-04)

- Initial public release (ClusterControl v1.2.8).
