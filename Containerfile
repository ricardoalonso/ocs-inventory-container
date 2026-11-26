FROM quay.io/rockylinux/rockylinux:9-ubi
MAINTAINER Ricardo Alonso <ricardoalonsos@gmail.com>
LABEL summary="OCS Inventory - Open computers and software inventory is an asset management solution." \
      description="It is an open source software. It allows you to scan and inventory all your devices in your IT Department. Once you know everything about your machines, on hardware and software sides, you can deploy packages to keep your environment safe. Many plugins are available and give high flexibility to fit OCS Inventory to your own system. FactorFX is the main contributor and daily edit the software. This french society guides companies in integrating and supporting OCS Inventory."
ARG PERMISSION_CHANGE="/etc/httpd /var/log/httpd /run/httpd /var/www/html /run/php-fpm /etc/php.ini /etc/php* /usr/share/ocsinventory-reports /var/lib/ocsinventory-reports /etc/ocsinventory-server /var/log/ocsinventory-server /ocsinventory /var/lib/php/" 
ENV OCS_VERSION=2.12.1 \
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


RUN dnf install -y 'dnf-command(config-manager)' && \
    dnf config-manager --set-enabled crb && \
    dnf update -y --nodocs && \
    dnf install -y --nodocs epel-release && \
    dnf install -y --nodocs wget mysql mod_perl make gcc httpd php php-mysqlnd php-gd php-xml php-mbstring php-curl perl-XML-Simple perl-DBI perl-DBD-MySQL perl-Apache-DBI perl-Net-IP perl-Archive-Zip php-pecl-zip perl-Mojolicious perl-Switch perl-Plack-Handler-FCGI perl-SOAP-Lite perl-IO-Compress && \
    dnf clean all 

RUN sed -i 's/^Listen.*/Listen 8080/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^[[:blank:]]*ErrorLog.*/ErrorLog \/dev\/stderr/' /etc/httpd/conf/httpd.conf && \
    sed -i 's/^[[:blank:]]*CustomLog.*/CustomLog \/dev\/stdout combined /' /etc/httpd/conf/httpd.conf && \
    sed -i 's/.*mysqli.allow_persistent =.*/mysqli.allow_persistent = On/' /etc/php.ini && \
    sed -i 's/^daemonize.*/daemonize = no/' /etc/php-fpm.conf && \
    sed -i 's/^error_log.*/error_log = \/dev\/stderr/' /etc/php-fpm.conf && \
    sed -i 's/^slowlog.*/slowlog = \/dev\/stderr/' /etc/php-fpm.d/www.conf && \
    sed -i 's/^php_admin_value\[error_log\].*/php_admin_value\[error_log\] = \/dev\/stderr/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.status_path =.*/pm.status_path = \/php-status/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.max_children =.*/pm.max_children = 150/' /etc/php-fpm.d/www.conf && \
    sed -i 's/.*pm.max_requests =.*/pm.max_requests = 100/' /etc/php-fpm.d/www.conf && \
    sed -i "s/^upload_max_filesize.*/upload_max_filesize = 4M/" /etc/php.ini && \
    sed -i "s/^post_max_size.*/post_max_size = 4M/" /etc/php.ini && \
    mkdir /run/php-fpm  /ocsinventory

WORKDIR /tmp

RUN wget -qO- https://github.com/OCSInventory-NG/OCSInventory-ocsreports/releases/download/${OCS_VERSION}/OCSNG_UNIX_SERVER-${OCS_VERSION}.tar.gz | tar xz && \
    cd OCSNG_UNIX_SERVER-${OCS_VERSION} && \
    /bin/bash ./setup.sh && \
    ln -sf /ocsinventory/log /var/log/ocsinventory-server && \
    ln -sf /ocsinventory/etc /etc/ocsinventory-server && \
    ln -sf /ocsinventory/lib /var/lib/ocsinventory-reports && \
    ln -sf /ocsinventory/extensions /usr/share/ocsinventory-reports/ocsreports/extensions && \
    cd /tmp && rm -rf OCSNG_UNIX_SERVER-${OCS_VERSION}

ADD run.sh /usr/local/bin/
ADD index.html /var/www/html/
ADD conf/ /tmp/conf
ADD docker-entrypoint.sh /docker-entrypoint.sh
ADD docker-entrypoint.d /docker-entrypoint.d

RUN chown -R apache.0 $PERMISSION_CHANGE && \
    chmod -R g=u $PERMISSION_CHANGE 

VOLUME /ocsinventory

USER apache
EXPOSE 8080
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["run.sh"]
