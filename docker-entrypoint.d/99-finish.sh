#!/bin/bash

echo "+----------------------------------------------------------+"
echo "|   Setting Apache Server Name to '${APACHE_SERVER_NAME:-localhost}'"
echo "+----------------------------------------------------------+"
echo

sed -ri -e "s!^#(ServerName)\s+\S+!\1 ${APACHE_SERVER_NAME:-localhost}:80!g" \
    "/etc/httpd/conf/httpd.conf"

echo "+----------------------------------------------------------+"
echo "|                 OK, prepare finshed ;-)                  |"
echo "|                                                          |"
echo "|      Starting OCS Inventory NG Management Docker...      |"
echo "+----------------------------------------------------------+"
echo
