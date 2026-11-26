#!/usr/bin/env bash
# Smoke test of a built image, with podman, nothing outside this machine.
#
#   test/smoketest.sh <image> [mariadb-image]
#
# Starts MariaDB (the version OKD runs) with the image's own base schema, runs
# the image as an arbitrary UID in group 0 (like OpenShift's restricted-v2),
# then checks:
#   - the console's schema update (base schema -> this version) and login
#   - an agent PROLOG and INVENTORY, zlib-compressed like the Windows agent
#   - the REST API
#   - errors in the container log
# Exits non-zero if a check fails. Containers and network are removed at the end
# (KEEP=1 keeps them; the app is then on http://127.0.0.1:18080/ocsreports/).
set -uo pipefail

IMG=${1:?usage: $0 <image> [mariadb-image]}
DB_IMG=${2:-docker.io/library/mariadb:11.8.9}
NET=ocs-smoke
PORT=${PORT:-18080}
URL=http://127.0.0.1:$PORT
tmp=$(mktemp -d)
fail=0

cleanup() {
  [[ "${KEEP:-0}" == 1 ]] && { echo "kept: containers ocs-smoke-db/ocs-smoke-app, $URL/ocsreports/"; return; }
  podman rm -f ocs-smoke-app ocs-smoke-db >/dev/null 2>&1
  podman network rm $NET >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT
check() {  # check <description> <command...>
  local d=$1; shift
  if "$@"; then echo "ok   $d"; else echo "FAIL $d"; fail=1; fi
}
db() { podman exec -i ocs-smoke-db mariadb -uroot -prootpw "$@"; }
z() { python3 -I -c 'import sys,zlib; sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))'; }
unz() { python3 -I -c 'import sys,zlib; print(zlib.decompress(sys.stdin.buffer.read()).decode())'; }

podman rm -f ocs-smoke-app ocs-smoke-db >/dev/null 2>&1
podman network exists $NET || podman network create $NET >/dev/null

# --- database, same settings as manifests/20-mariadb.yaml in the okd repo
podman run -d --name ocs-smoke-db --network $NET \
  -e MARIADB_ROOT_PASSWORD=rootpw -e MARIADB_DATABASE=ocsweb -e MARIADB_USER=ocs -e MARIADB_PASSWORD=ocspw \
  "$DB_IMG" --character-set-server=utf8mb3 --collation-server=utf8mb3_general_ci \
  --character-set-collations=utf8mb3=utf8mb3_general_ci,utf8mb4=utf8mb4_general_ci >/dev/null
for _ in $(seq 1 60); do db -e 'select 1' >/dev/null 2>&1 && break; sleep 2; done
podman run --rm --entrypoint cat "$IMG" /usr/share/ocsinventory-reports/ocsreports/files/ocsbase.sql | db ocsweb
base=$(db ocsweb -N -e "SELECT tvalue FROM config WHERE name='GUI_VERSION'")
want=$(podman run --rm --entrypoint grep "$IMG" -oP "define\('GUI_VER', '\K[0-9]+" /usr/share/ocsinventory-reports/ocsreports/var.php)
echo "schema: base $base, image expects $want"

# --- app, as OpenShift runs it
podman run -d --name ocs-smoke-app --network $NET --user 54321:0 \
  --mount type=tmpfs,destination=/ocsinventory,tmpfs-mode=1777 -p "$PORT:8080" \
  -e OCS_DB_SERVER=ocs-smoke-db -e OCS_DB_USER=ocs -e OCS_DB_PASS=ocspw -e OCS_DB_NAME=ocsweb \
  -e OCS_SSL_ENABLED=0 -e OCS_DBI_PRINT_ERROR=0 "$IMG" >/dev/null
for _ in $(seq 1 30); do curl -s -o /dev/null "$URL/ocsreports/" && break; sleep 2; done
podman exec ocs-smoke-app bash -c 'echo "image: $(grep PRETTY /etc/os-release | cut -d\" -f2), $(php -v | head -1 | cut -d" " -f1-2), OCS $OCS_VERSION"'

# --- console: schema update, then login as the default admin
# (Responses go to files before grep: with pipefail, `curl | grep -q` fails
# whenever grep stops reading early, even on a match.)
curl -s -c "$tmp/ck" -b "$tmp/ck" -o "$tmp/upd.html" "$URL/ocsreports/"
check "console offers schema update $base -> $want" grep -q "Expected version:$want" "$tmp/upd.html"
curl -s -c "$tmp/ck" -b "$tmp/ck" -X POST -d 'update=Update' "$URL/ocsreports/" >/dev/null
check "schema at $want after update" test "$(db ocsweb -N -e "SELECT tvalue FROM config WHERE name='GUI_VERSION'")" = "$want"
curl -s -c "$tmp/ck2" -b "$tmp/ck2" -o "$tmp/login-form.html" "$URL/ocsreports/"
tok=$(grep -oP "name='CSRF_0' id='CSRF_0' value='\K[0-9a-f]+" "$tmp/login-form.html")
curl -s -c "$tmp/ck2" -b "$tmp/ck2" -o "$tmp/login.html" \
  -d "LOGIN=admin&PASSWD=admin&Valid_CNX=Send&CSRF_0=$tok" "$URL/ocsreports/index.php"
check "console login" grep -q Logout "$tmp/login.html"

# --- agent protocol
dev=smoketest-2026-01-01-00-00-00
printf '<?xml version="1.0" encoding="UTF-8" ?>\n<REQUEST><DEVICEID>%s</DEVICEID><QUERY>PROLOG</QUERY></REQUEST>' $dev | z > "$tmp/prolog"
r=$(curl -s -H 'Content-Type: application/x-compress' -A 'OCS-NG_WINDOWS_AGENT_v2.10.1.0' --data-binary @"$tmp/prolog" "$URL/ocsinventory" | unz 2>/dev/null)
check "agent PROLOG answered SEND" grep -q '<RESPONSE>SEND</RESPONSE>' <<<"$r"
printf '<?xml version="1.0" encoding="UTF-8" ?>\n<REQUEST><CONTENT><HARDWARE><NAME>SMOKETEST</NAME><OSNAME>Microsoft Windows 11 Pro</OSNAME><MEMORY>16000</MEMORY><WORKGROUP>TEST</WORKGROUP></HARDWARE><BIOS><SSN>ABC123</SSN></BIOS><BATTERIES><NAME>BAT0</NAME><MANUFACTURER>ACME</MANUFACTURER><CHEMISTRY>LION</CHEMISTRY></BATTERIES><SOFTWARES><NAME>Firefox</NAME><VERSION>140.0</VERSION><PUBLISHER>Mozilla</PUBLISHER></SOFTWARES></CONTENT><DEVICEID>%s</DEVICEID><QUERY>INVENTORY</QUERY></REQUEST>' $dev | z > "$tmp/inv"
r=$(curl -s -H 'Content-Type: application/x-compress' -A 'OCS-NG_WINDOWS_AGENT_v2.10.1.0' --data-binary @"$tmp/inv" "$URL/ocsinventory" | unz 2>/dev/null)
check "agent INVENTORY accepted" grep -q 'NO_ACCOUNT_UPDATE' <<<"$r"
check "inventory stored (hardware, battery, software)" test "$(db ocsweb -N -e "SELECT CONCAT((SELECT COUNT(*) FROM hardware WHERE NAME='SMOKETEST'),(SELECT COUNT(*) FROM batteries),(SELECT COUNT(*) FROM software))")" = 111
code=$(curl -s -o /dev/null -w '%{http_code}' -b "$tmp/ck2" "$URL/ocsreports/index.php?function=visu_computers")
check "console computers page (HTTP $code)" test "$code" = 200

# --- REST API
r=$(curl -s -w '\n%{http_code}' "$URL/ocsapi/v1/computers/listID")
check "REST API listID (HTTP ${r##*$'\n'})" test "${r##*$'\n'}" = 200
id=$(db ocsweb -N -e "SELECT ID FROM hardware WHERE NAME='SMOKETEST'")
r=$(curl -s "$URL/ocsapi/v1/computer/$id/hardware")
check "REST API computer detail has its name" grep -q SMOKETEST <<<"$r"

# --- log
errs=$(podman logs ocs-smoke-app 2>&1 | grep -iE "PHP (Fatal|Warning|Parse)|\[perl:error\]|Cannot find|Can't locate|segfault" | grep -v SNMP_LINK_TAG)
check "no PHP/perl errors in the log" test -z "$errs"
[[ -n "$errs" ]] && echo "$errs" | sed 's/^/     /' | sort | uniq -c | head -10

exit $fail
