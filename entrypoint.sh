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

NSCA_CFG="${NAGIOS_ETC}/nsca.cfg"
if [ ! -f "${NSCA_CFG}" ] && [ -f /usr/local/nagios/nsca.cfg.dist ]; then
    # Seeds nsca.cfg for volumes created before NSCA was added to this image.
    cp /usr/local/nagios/nsca.cfg.dist "${NSCA_CFG}"
fi
if [ -z "${NSCA_PASSWORD:-}" ]; then
    NSCA_PASSWORD="nsca"
    echo "WARNING: using default NSCA password 'nsca'. Set NSCA_PASSWORD to override."
fi
python3 - "${NSCA_CFG}" "${NSCA_PASSWORD}" "${NSCA_ENCRYPTION_METHOD:-14}" <<'PYEOF'
import re
import sys

path, password, method = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    lines = f.readlines()

out = []
for line in lines:
    if re.match(r'^#?password=', line):
        out.append(f"password={password}\n")
    elif re.match(r'^#?decryption_method=', line):
        out.append(f"decryption_method={method}\n")
    else:
        out.append(line)

with open(path, "w") as f:
    f.writelines(out)
PYEOF

NAGIOSGRAPH_OBJ="${NAGIOS_ETC}/objects/nagiosgraph.cfg"
if [ ! -f "${NAGIOSGRAPH_OBJ}" ] && [ -f /usr/local/nagios/nagiosgraph-command.cfg.dist ]; then
    # Seeds the nagiosgraph command definition for volumes created before it was added.
    cp /usr/local/nagios/nagiosgraph-command.cfg.dist "${NAGIOSGRAPH_OBJ}"
fi

python3 - "${NAGIOS_ETC}/nagios.cfg" <<'PYEOF'
import re
import sys

path = sys.argv[1]
directives = {
    "process_performance_data": "1",
    "service_perfdata_file": "/usr/local/nagios/var/perfdata.log",
    "service_perfdata_file_template": "$LASTSERVICECHECK$||$HOSTNAME$||$SERVICEDESC$||$SERVICEOUTPUT$||$SERVICEPERFDATA$",
    "service_perfdata_file_mode": "a",
    "service_perfdata_file_processing_interval": "30",
    "service_perfdata_file_processing_command": "process-service-perfdata-file",
}

with open(path) as f:
    lines = f.readlines()

seen = set()
out = []
for line in lines:
    m = re.match(r'^#?\s*([A-Za-z_]+)\s*=', line)
    key = m.group(1) if m else None
    if key in directives:
        out.append(f"{key}={directives[key]}\n")
        seen.add(key)
    else:
        out.append(line)

for key, value in directives.items():
    if key not in seen:
        out.append(f"{key}={value}\n")

nagiosgraph_cfg_line = "cfg_file=/usr/local/nagios/etc/objects/nagiosgraph.cfg"
if not any(l.strip() == nagiosgraph_cfg_line for l in out):
    out.append(nagiosgraph_cfg_line + "\n")

with open(path, "w") as f:
    f.writelines(out)
PYEOF

touch /usr/local/nagios/var/perfdata.log /usr/local/nagios/var/nagiosgraph.log /usr/local/nagios/var/nagiosgraph-cgi.log

chown -R nagios:nagcmd /usr/local/nagios/var /usr/local/nagios/etc
chown nagios:nagcmd "${HTPASSWD_FILE}"
chmod 640 "${NSCA_CFG}"
chmod 664 /usr/local/nagios/var/perfdata.log /usr/local/nagios/var/nagiosgraph.log /usr/local/nagios/var/nagiosgraph-cgi.log
chmod 775 /usr/local/nagios/var/rrd

/usr/local/nagios/bin/nagios -v "${NAGIOS_ETC}/nagios.cfg"

exec "$@"
