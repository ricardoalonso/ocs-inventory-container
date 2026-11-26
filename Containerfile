FROM quay.io/rockylinux/rockylinux:9-ubi

# OCS Inventory NG server (communication server, ocsreports console, REST API)
# for OpenShift: httpd on 8080, runs as any UID in group 0 (restricted-v2 SCC).
#
# To update OCS: bump OCS_VERSION and OCS_SHA256 (the release asset's sha256,
# GitHub shows it as the asset "digest"), sync conf/ and docker-entrypoint.d/
# with upstream's OCSInventory-Docker-Image/<version>/, then build.sh and
# test/smoketest.sh.
ARG OCS_VERSION=2.12.6
ARG OCS_SHA256=57216f5e20436ed07226bf014deda1c978b3c030a650a02bd57b020f51c954c2
# EPEL's perl-Plack leaves out the mod_perl handlers, and the REST API runs on
# Plack::Handler::Apache2. Take them from the same Plack release EPEL ships;
# the build fails if `rpm -q perl-Plack` moves to another version.
ARG PLACK_VERSION=1.0057
ARG PLACK_SHA256=01cfe036276703f62cf6c1cec7c7e630420677498dfa7bc333ad88eca9d7a765

LABEL maintainer="Ricardo Alonso <ricardoalonsos@gmail.com>" \
      summary="OCS Inventory - Open computers and software inventory is an asset management solution." \
      description="It is an open source software. It allows you to scan and inventory all your devices in your IT Department. Once you know everything about your machines, on hardware and software sides, you can deploy packages to keep your environment safe. Many plugins are available and give high flexibility to fit OCS Inventory to your own system. FactorFX is the main contributor and daily edit the software. This french society guides companies in integrating and supporting OCS Inventory." \
      org.opencontainers.image.version="${OCS_VERSION}" \
      org.opencontainers.image.source="https://github.com/OCSInventory-NG/OCSInventory-ocsreports"

ARG PERMISSION_CHANGE="/etc/httpd /var/log/httpd /run/httpd /var/www/html /run/php-fpm /etc/php.ini /etc/php* /usr/share/ocsinventory-reports /var/lib/ocsinventory-reports /etc/ocsinventory-server /var/log/ocsinventory-server /ocsinventory /var/lib/php/"
ENV OCS_VERSION=${OCS_VERSION} \
    APACHE_LOG_DIR=/var/log/httpd \
    APACHE_RUN_USER=apache \
    APACHE_RUN_GROUP=apache \
    APACHE_RUN_DIR=/var/run/httpd \
    APACHE_SERVER_NAME=localhost \
    OCS_DB_SERVER=mysql \
    OCS_DB_PORT=3306 \
    OCS_DB_USER=ocs \
    OCS_DB_PASS=ocs \
    OCS_DB_NAME=ocsweb \
    OCS_DBI_PRINT_ERROR=0 \
    OCS_LOG_DIR=/ocsinventory/log \
    OCS_VARLIB_DIR=/ocsinventory/lib \
    OCS_WEBCONSOLE_DIR=/usr/share/ocsinventory-reports \
    OCS_PERLEXT_DIR=/ocsinventory/etc/perl/ \
    OCS_PLUGINSEXT_DIR=/ocsinventory/plugins/ \
    OCS_SSL_ENABLED=0 \
    OCS_SSL_WEB_MODE=DISABLED \
    OCS_SSL_COM_MODE=DISABLED \
    OCS_SSL_KEY=/path/to/key \
    OCS_SSL_CERT=/path/to/cert \
    OCS_SSL_CA=/path/to/ca \
    TZ=America/Sao_Paulo

# PHP 8.3: the EL9 default stream is 8.0 (upstream EOL 2023); upstream's own
# 2.12.6 image runs 8.3 (Ubuntu 24.04).
RUN dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb && \
    dnf update -y --nodocs && \
    dnf install -y --nodocs epel-release && \
    dnf module enable -y php:8.3 && \
    dnf install -y --nodocs wget mysql mod_perl make gcc httpd php php-mysqlnd php-gd php-xml php-mbstring php-curl perl-XML-Simple perl-DBI perl-DBD-MySQL perl-Apache-DBI perl-Net-IP perl-Archive-Zip php-pecl-zip perl-Mojolicious perl-Switch perl-Plack perl-Plack-Handler-FCGI perl-SOAP-Lite perl-IO-Compress perl-XML-Entities && \
    dnf clean all

# php-fpm: 20 workers fit in the pod's 512Mi (128M memory_limit each, most use
# far less). The spare-server counts must stay below max_children, or php-fpm
# refuses to start. Uploads (deployment packages in the console): 100M, the
# value upstream's Apache config sets for mod_php, which php-fpm ignores.
RUN sed -i 's/^Listen.*/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^[[:blank:]]*ErrorLog.*/ErrorLog \/dev\/stderr/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^[[:blank:]]*CustomLog.*/CustomLog \/dev\/stdout combined /' /etc/httpd/conf/httpd.conf && \
    sed -i 's/.*mysqli.allow_persistent =.*/mysqli.allow_persistent = On/' /etc/php.ini && \
    sed -i 's/^daemonize.*/daemonize = no/' /etc/php-fpm.conf && \
    sed -i 's/^error_log.*/error_log = \/dev\/stderr/' /etc/php-fpm.conf && \
    sed -i 's/^slowlog.*/slowlog = \/dev\/stderr/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^php_admin_value\[error_log\].*/php_admin_value\[error_log\] = \/dev\/stderr/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.status_path =.*/pm.status_path = \/php-status/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.max_children =.*/pm.max_children = 20/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.start_servers =.*/pm.start_servers = 2/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.min_spare_servers =.*/pm.min_spare_servers = 2/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.max_spare_servers =.*/pm.max_spare_servers = 5/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.max_requests =.*/pm.max_requests = 100/' /etc/php-fpm.d/www.conf && \
    sed -i "s/^upload_max_filesize.*/upload_max_filesize = 100M/" /etc/php.ini && \
    sed -i "s/^post_max_size.*/post_max_size = 101M/" /etc/php.ini && \
    mkdir /run/php-fpm  /ocsinventory

WORKDIR /tmp

RUN wget -q https://github.com/OCSInventory-NG/OCSInventory-ocsreports/releases/download/${OCS_VERSION}/OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz && \
    echo "${OCS_SHA256}  OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz" | sha256sum -c - && \
    tar xzf OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz && \
    cd OCSNG_UNIX_SERVER-${OCS_VERSION} && \
    /bin/bash ./setup.sh && \
    ln -sf /ocsinventory/log /var/log/ocsinventory-server && \
    ln -sf /ocsinventory/etc /etc/ocsinventory-server && \
    ln -sf /ocsinventory/lib /var/lib/ocsinventory-reports && \
    ln -sf /ocsinventory/extensions /usr/share/ocsinventory-reports/ocsreports/extensions && \
    cd /tmp && rm -rf OCSNG_UNIX_SERVER-${OCS_VERSION} OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz

RUN wget -q https://cpan.metacpan.org/authors/id/M/MI/MIYAGAWA/Plack-${PLACK_VERSION}.tar.gz && \
    echo "${PLACK_SHA256}  Plack-${PLACK_VERSION}.tar.gz" | sha256sum -c - && \
    test "$(rpm -q --qf '%{VERSION}' perl-Plack)" = "${PLACK_VERSION}" && \
    tar xzf Plack-${PLACK_VERSION}.tar.gz && \
    mkdir -p /usr/local/share/perl5/5.32/Plack/Handler && \
    cp -r Plack-${PLACK_VERSION}/lib/Plack/Handler/Apache2.pm Plack-${PLACK_VERSION}/lib/Plack/Handler/Apache2 \
          /usr/local/share/perl5/5.32/Plack/Handler/ && \
    rm -rf Plack-${PLACK_VERSION} Plack-${PLACK_VERSION}.tar.gz

COPY run.sh /usr/local/bin/
COPY index.html /var/www/html/
COPY conf/ /tmp/conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY docker-entrypoint.d /docker-entrypoint.d

RUN chown -R apache:0 $PERMISSION_CHANGE && \
    chmod -R g=u $PERMISSION_CHANGE

VOLUME /ocsinventory

USER apache
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["run.sh"]
