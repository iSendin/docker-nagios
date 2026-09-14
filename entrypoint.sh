#!/bin/sh
set -e

NAGIOS_ETC=/usr/local/nagios/etc
HTPASSWD_FILE="${NAGIOS_ETC}/htpasswd.users"

if [ -n "${NAGIOSADMIN_PASSWORD:-}" ]; then
    htpasswd -b -c "${HTPASSWD_FILE}" "${NAGIOSADMIN_USER:-nagiosadmin}" "${NAGIOSADMIN_PASSWORD}"
elif [ ! -f "${HTPASSWD_FILE}" ]; then
    htpasswd -b -c "${HTPASSWD_FILE}" "${NAGIOSADMIN_USER:-nagiosadmin}" admin
    echo "WARNING: using default nagiosadmin password 'admin'. Set NAGIOSADMIN_PASSWORD to override."
fi

chown -R nagios:nagcmd /usr/local/nagios/var /usr/local/nagios/etc
chown nagios:nagcmd "${HTPASSWD_FILE}"

/usr/local/nagios/bin/nagios -v "${NAGIOS_ETC}/nagios.cfg"

exec "$@"
