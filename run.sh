#!/bin/bash
/usr/sbin/php-fpm &

exec /usr/sbin/httpd -D FOREGROUND
