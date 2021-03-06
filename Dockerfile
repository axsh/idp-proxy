FROM docker.io/centos:7

# Install packages
COPY resources/tmp/remi-release-7.rpm /tmp/
RUN set -x \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 \
    && yum -y update \
    && yum -y install epel-release \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
    && yum -y install less which cronie logrotate \
    && systemctl enable crond \
    && yum -y install yum-utils \
    # Install nginx and php
    && yum -y install --enablerepo=epel nginx \
    && systemctl enable nginx \
    && rpm -Uvh /tmp/remi-release-7.rpm \ 
    && rm /tmp/remi-release-7.rpm \
    #&& yum -y install http://rpms.famillecollet.com/enterprise/remi-release-7.rpm \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-remi \
    && yum -y install --enablerepo=remi-php71 composer \
    && yum -y install --enablerepo=remi-php71 php php-fpm php-xml php-mcrypt php-gmp php-soap \
    && systemctl enable php-fpm \
    # Install simplesamlphp
    && cd /var/www \
    && curl -Lo downloaded-simplesamlphp.tar.gz https://github.com/simplesamlphp/simplesamlphp/releases/download/v1.14.14/simplesamlphp-1.14.14.tar.gz \
    && tar xvfz downloaded-simplesamlphp.tar.gz \
    && mv $( ls | grep simplesaml | grep -v *tar.gz ) simplesamlphp \
    && rm /var/www/downloaded-simplesamlphp.tar.gz 

RUN set -x \
    # Install simplesamlphp-module-attributeaggregator 
    && cd /var/www/simplesamlphp \
    && composer require niif/simplesamlphp-module-attributeaggregator:1.*

# Setup nginx
# Copy the nginx configuration files
COPY resources/nginx/nginx.conf /etc/nginx/
COPY resources/nginx/idp-proxy.conf /etc/nginx/conf.d/
# Setup the keys for nginx
COPY resources/keys/idp-proxy.chained.cer /etc/pki/nginx/
COPY resources/keys/idp-proxy.key /etc/pki/nginx/private/

# Setup php-fpm
COPY resources/php-fpm/www.conf /etc/php-fpm.d/
RUN chgrp nginx /var/lib/php/session

# Apply the simplesamlphp patch
ARG SOAP_CLIENT_PHP="simplesamlphp/vendor/simplesamlphp/saml2/src/SAML2/SOAPClient.php"
COPY resources/${SOAP_CLIENT_PHP} /var/www/${SOAP_CLIENT_PHP}

# Setup simplesamlphp
RUN set -x \
    && mkdir -p /var/www/simplesamlphp/metadata/xml \
    && chown -R nginx:nginx /var/www/simplesamlphp
COPY resources/simplesamlphp/config/config.php /var/www/simplesamlphp/config
COPY resources/simplesamlphp/config/authsources.php /var/www/simplesamlphp/config
COPY resources/simplesamlphp/bin/update_ds_metadata.sh /var/www/simplesamlphp/bin
COPY resources/simplesamlphp/bin/add_auth_proxy_metadata.php /var/www/simplesamlphp/bin
COPY resources/simplesamlphp/bin/remove_auth_proxy_metadata.php /var/www/simplesamlphp/bin
COPY resources/simplesamlphp/bin/auth_proxy_functions.php /var/www/simplesamlphp/bin
COPY resources/simplesamlphp/metadata/saml20-idp-hosted.php /var/www/simplesamlphp/metadata
COPY resources/simplesamlphp/metadata/xml/auth-proxies.xml /var/www/simplesamlphp/metadata/xml
     
# Setup the keys for simplesamlphp
COPY resources/keys/idp-proxy.cer /var/www/simplesamlphp/cert/
COPY resources/keys/idp-proxy.key /var/www/simplesamlphp/cert/

# Set cron for Gakunin metadata updating
RUN set -x \
    && echo "0 0 */10 * * /var/www/simplesamlphp/bin/update_ds_metadata.sh" > /var/spool/cron/root

