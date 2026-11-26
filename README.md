# ocs-inventory — OCS Inventory NG server image for OpenShift

`quay.io/ricardoalonsos/ocs-inventory`: OCS Inventory NG server (communication
server for the agents, ocsreports console, REST API) on Rocky Linux 9 + EPEL,
httpd (mod_perl) + php-fpm 8.3, port 8080. It runs as any UID in group 0, so it
works under OpenShift's `restricted-v2` SCC. Deployed on OKD by
`~/git/pdcase/okd/ocs/` (project `pdcase-ocs-inventory`).

Entrypoint scripts (`docker-entrypoint.d/`) and conf templates (`conf/`) come
from upstream's [OCSInventory-Docker-Image](https://github.com/OCSInventory-NG/OCSInventory-Docker-Image)
for the same version, adapted to the EL layout (`/etc/httpd/conf.d`, no
`a2enconf`). They regenerate the Apache config from environment variables on
every start.

## Build and test

```bash
./build.sh                                                   # tags <version>-<release> and <version>
test/smoketest.sh quay.io/ricardoalonsos/ocs-inventory:2.12.6-1
podman push quay.io/ricardoalonsos/ocs-inventory:2.12.6-1    # then deploy by digest
```

`test/smoketest.sh` needs only podman and python3. It starts MariaDB 11.8 with
the image's base schema, runs the image as a random UID, and checks the
console's schema update and login, an agent PROLOG + INVENTORY (zlib, like the
Windows agent), the REST API, and the log.

## Upgrading OCS

1. In the `Containerfile`, set `OCS_VERSION` and `OCS_SHA256` (the sha256 of
   `OCSNG_UNIX_SERVER-<version>.tar.gz`; GitHub shows it as the release asset's
   digest).
2. Diff upstream's `OCSInventory-Docker-Image/<version>/conf` and
   `docker-entrypoint.d` against the previous version, and port the changes.
   For 2.12.1 → 2.12.6, that was 4 new options in `ocsinventory-server.conf`
   and the `OCS_OPT_DBI_PRINT_ERROR` line in `10-com-server.sh`.
3. In `build.sh`, set `VERSION` and reset `RELEASE=1`. Build, then smoke test.
4. After deploying, open `/ocsreports/` as an admin. If the schema changed, it
   offers an *Update* button (`update.php`), which applies
   `files/update/<n>.sql`. Dump the database first.

Rebuild with `RELEASE+1` now and then even without a new OCS version, to pick
up OS and PHP security updates.

## Things to know

- **Database password:** letters and digits only. The entrypoint writes it into
  config files with `sed`, so `/`, `&` and `\` break them.
- **REST API (`/ocsapi`):** it has no authentication of its own. Upstream's
  Apache config doesn't restrict it, and neither does this image. On OKD it's
  only reachable through the nginx proxy, which requires basic auth, and only
  on the internal route. The Plack `Apache2` handler it needs isn't in EPEL's
  `perl-Plack`, so the `Containerfile` adds it from the matching CPAN release.
  The build fails if EPEL moves to another Plack version.
- **Uploads:** 100M (`php.ini`). Settings in `/etc/php.d/*.ini` also apply, if
  mounted as files.
- **Logs:** httpd and php-fpm log to stdout/stderr. The communication server
  logs to `/ocsinventory/log/` (on the volume, not rotated).
- **`run.sh`:** runs php-fpm and httpd. If either one exits, the container
  exits, so the pod restarts instead of serving 503s.
- **`agent-install.sh`:** installs and configures the Linux agent (Fedora,
  Debian/Ubuntu). It contains the agents' basic-auth credentials, which every
  agent has anyway. Keep this repo private.
