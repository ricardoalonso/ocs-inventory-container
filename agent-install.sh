#!/bin/bash

CONF_DIR_FEDORA=/etc/ocsinventory
CONF_DIR_DEBIAN=/etc/ocsinventory-agent
CONF_FILE=ocsinventory-agent.cfg
CERT_URL=https://letsencrypt.org/certs/isrgrootx1.pem
CERT_LOCATION=/var/lib/ocsinventory-agent/https:__www.pdcase.com_ocsinventory
LOG_FILE=/tmp/agent-config.log
FEDORA_PACKAGE_URL_PREFIX=https://www.pdcase.com/pub/.packages
OCS_VERSION=2.10.2-1

. /etc/os-release

function debian_config {
    apt install -y gpg
    echo Configuring Debian/Ubuntu....
    curl -fsSL http://deb.ocsinventory-ng.org/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/ocs-archive-keyring.gpg
    echo "deb http://deb.ocsinventory-ng.org/${ID}/ ${VERSION_CODENAME} main" | sudo tee /etc/apt/sources.list.d/ocsinventory.list
    apt update 
    DEBIAN_FRONTEND=noninteractive apt install -y ocsinventory-agent
}

function config_pdcase_repo {
    curl https://www.pdcase.com/pub/.packages/SIGNATURE_PUBLIC_KEY -o /etc/pki/rpm-gpg/pdcase.asc
    cat <<EOF > /etc/yum.repos.d/pdcase.repo
[pdcase]
name=pdcase
baseurl=https://www.pdcase.com/pub/.packages/fedora/\$releasever/
enable=1
skip_if_unavailable=1
metadata_expire=600
gpgkey="file:///etc/pki/rpm-gpg/pdcase.asc"
gpgcheck=1
type=rpm
EOF
}

function fedora_config {
    echo Configuring Fedora...
    config_pdcase_repo
    dnf install -y ocsinventory-agent
    sed -i 's/OCSMODE[0]=.*/OCSMODE[0]=cron/' /etc/sysconfig/ocsinventory-agent
}

function configure_agent {
    echo Configuring agent... 
    cat <<EOF > $CONF_FILE_FINAL
debug=
user=cGRjYXNl
password=c3FsVE9QQDg5MQ==
snmpretry=2
snmptimeout=3
snmp=1
nosoftware=0
logfile=/var/log/ocsinventory-agent.log
server=https://www.pdcase.com/ocsinventory
realm=OCS Protected area
ssl=1
tag=
basevardir=/var/lib/ocsinventory-agent
scan-homedirs=
EOF
    echo Agent configured. 
}

function import_cert {
    mkdir -p $CERT_LOCATION
    curl $CERT_URL -o $CERT_LOCATION/cacert.pem
    echo Certificate imported. 
}

function run() {
    echo "Running agente for the first time"
    ocsinventory-agent
}

function init {
    if [ $USER != "root" ]
    then
        echo "ERROR: This application must run as root."
        echo "You can use the command: sudo $0"
        exit 2
    fi

    case $ID in
    "fedora")
        CONF_FILE_FINAL=${CONF_DIR_FEDORA}/${CONF_FILE}
        fedora_config
        ;;
    "ubuntu"|"debian")
        CONF_FILE_FINAL=${CONF_DIR_DEBIAN}/${CONF_FILE}
        debian_config
        ;;
    *)
        echo "ERROR: System not supported! Contact the team" 
        exit 1
    esac
    import_cert
    configure_agent
    run
    exit 0
}

init
