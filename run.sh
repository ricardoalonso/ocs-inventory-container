#!/bin/bash
# php-fpm and httpd in one container. If either one exits, stop the other and
# exit too, so Kubernetes restarts the pod. Before, a dead php-fpm left httpd
# up, answering 503 for the console while the TCP probe stayed green.
/usr/sbin/php-fpm --nodaemonize &
fpm=$!
/usr/sbin/httpd -D FOREGROUND &
httpd=$!
trap 'kill -TERM "$fpm" "$httpd" 2>/dev/null' TERM INT
wait -n
rc=$?
kill -TERM "$fpm" "$httpd" 2>/dev/null
wait
exit "$rc"
