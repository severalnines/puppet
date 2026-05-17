#!/bin/bash
# sync_cmon_admin.sh
# Syncs the cmon 'admin' user password in the cmon DB to match what's stored
# in /etc/s9s.conf, and unsuspends the user. This is needed because service
# restart cycles can desync the in-memory state from the DB.
#
# Usage: sync_cmon_admin.sh <mysql_root_password>

set -e

MYSQL_ROOT_PASS="$1"

if [ -z "$MYSQL_ROOT_PASS" ]; then
    echo "Usage: $0 <mysql_root_password>" >&2
    exit 1
fi

# Read admin password from /etc/s9s.conf
if [ ! -f /etc/s9s.conf ]; then
    echo "ERROR: /etc/s9s.conf not found - has cmon --init run yet?" >&2
    exit 1
fi

S9S_ADMIN_PASS=$(grep '^cmon_password' /etc/s9s.conf \
    | sed 's/^cmon_password[[:space:]]*=[[:space:]]*//' \
    | tr -d '"' | tr -d "'" | tr -d ' ')

if [ -z "$S9S_ADMIN_PASS" ]; then
    echo "ERROR: Could not read admin password from /etc/s9s.conf" >&2
    exit 1
fi

# Get admin's salt from cmon DB
ADMIN_SALT=$(mysql -u root -p"$MYSQL_ROOT_PASS" -N -B cmon \
    -e "SELECT JSON_UNQUOTE(JSON_EXTRACT(properties, '\$.password_salt')) FROM users WHERE username='admin';" 2>/dev/null)

if [ -z "$ADMIN_SALT" ] || [ "$ADMIN_SALT" = "NULL" ]; then
    echo "ERROR: Could not read admin password_salt from cmon DB" >&2
    exit 1
fi

# Compute the SHA256 hash that cmon expects
ADMIN_HASH=$(echo -n "${S9S_ADMIN_PASS}${ADMIN_SALT}" | sha256sum | awk '{print $1}')

# Update admin's password hash in cmon DB, unsuspend, reset failed counter
mysql -u root -p"$MYSQL_ROOT_PASS" cmon -e "
UPDATE users
SET properties = JSON_SET(
    properties,
    '\$.password_encrypted', '${ADMIN_HASH}',
    '\$.suspended', false,
    '\$.n_failed_logins', 0
)
WHERE username = 'admin';
" 2>/dev/null

echo "OK"
exit 0
