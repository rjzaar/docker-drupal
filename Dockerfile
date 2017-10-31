FROM debian:stretch
MAINTAINER Wouter Admiraal <wad@wadmiraal.net>
ENV DEBIAN_FRONTEND noninteractive
ENV DRUPAL_VERSION 8.3.6

# Install packages.
RUN apt-get update
RUN apt-get install -y \
	vim \
	git \
	apache2 \
	php-cli \
	php-mysql \
	php-gd \
	php-curl \
	php-xdebug \
	php7.0-sqlite3 \
	libapache2-mod-php \
	curl \
	mysql-server \
	mysql-client \
	openssh-server \
	phpmyadmin \
	wget \
	unzip \
	cron \
        gnupg \
	supervisor
RUN apt-get clean

# Setup PHP.
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/apache2/php.ini
RUN sed -i 's/display_errors = Off/display_errors = On/' /etc/php/7.0/cli/php.ini

# Setup Blackfire.
# Get the sources and install the Debian packages.
# We create our own start script. If the environment variables are set, we
# simply start Blackfire in the foreground. If not, we create a dummy daemon
# script that simply loops indefinitely. This is to trick Supervisor into
# thinking the program is running and avoid unnecessary error messages.
RUN wget -O - https://packagecloud.io/gpg.key | apt-key add -
RUN echo "deb http://packages.blackfire.io/debian any main" > /etc/apt/sources.list.d/blackfire.list
RUN apt-get update
RUN apt-get install -y blackfire-agent blackfire-php
RUN echo '#!/bin/bash\n\
if [[ -z "$BLACKFIREIO_SERVER_ID" || -z "$BLACKFIREIO_SERVER_TOKEN" ]]; then\n\
    while true; do\n\
        sleep 1000\n\
    done\n\
else\n\
    /usr/bin/blackfire-agent -server-id="$BLACKFIREIO_SERVER_ID" -server-token="$BLACKFIREIO_SERVER_TOKEN"\n\
fi\n\
' > /usr/local/bin/launch-blackfire
RUN chmod +x /usr/local/bin/launch-blackfire
RUN mkdir -p /var/run/blackfire

# Setup Apache.
# In order to run our Simpletest tests, we need to make Apache
# listen on the same port as the one we forwarded. Because we use
# 8080 by default, we set it up for that port.
RUN sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/DocumentRoot \/var\/www\/html/DocumentRoot \/var\/www/' /etc/apache2/sites-available/default-ssl.conf
RUN echo "Listen 8080" >> /etc/apache2/ports.conf
RUN echo "Listen 8081" >> /etc/apache2/ports.conf
RUN echo "Listen 8443" >> /etc/apache2/ports.conf
RUN sed -i 's/VirtualHost \*:80/VirtualHost \*:\*/' /etc/apache2/sites-available/000-default.conf
RUN sed -i 's/VirtualHost __default__:443/VirtualHost _default_:443 _default_:8443/' /etc/apache2/sites-available/default-ssl.conf
RUN a2enmod rewrite
RUN a2enmod ssl
RUN a2ensite default-ssl.conf

# Setup PHPMyAdmin
RUN echo "\n# Include PHPMyAdmin configuration\nInclude /etc/phpmyadmin/apache.conf\n" >> /etc/apache2/apache2.conf
RUN sed -i -e "s/\/\/ \$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/\$cfg\['Servers'\]\[\$i\]\['AllowNoPassword'\]/g" /etc/phpmyadmin/config.inc.php
RUN sed -i -e "s/\$cfg\['Servers'\]\[\$i\]\['\(table_uiprefs\|history\)'\].*/\$cfg\['Servers'\]\[\$i\]\['\1'\] = false;/g" /etc/phpmyadmin/config.inc.php

# Setup MySQL, bind on all addresses.
RUN sed -i -e 's/^bind-address\s*=\s*127.0.0.1/#bind-address = 127.0.0.1/' /etc/mysql/my.cnf
RUN /etc/init.d/mysql start && \
	mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO drupal@localhost IDENTIFIED BY 'drupal'"

# Setup SSH.
RUN echo 'root:root' | chpasswd
RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN mkdir /var/run/sshd && chmod 0755 /var/run/sshd
RUN mkdir -p /root/.ssh/ && touch /root/.ssh/authorized_keys
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Setup Supervisor.
RUN echo '[program:apache2]\ncommand=/bin/bash -c "source /etc/apache2/envvars && exec /usr/sbin/apache2 -DFOREGROUND"\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:mysql]\ncommand=/usr/bin/pidproxy /var/run/mysqld/mysqld.pid /usr/sbin/mysqld\nautorestart=true\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:sshd]\ncommand=/usr/sbin/sshd -D\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:blackfire]\ncommand=/usr/local/bin/launch-blackfire\n\n' >> /etc/supervisor/supervisord.conf
RUN echo '[program:cron]\ncommand=cron -f\nautorestart=false \n\n' >> /etc/supervisor/supervisord.conf

# Setup XDebug.
RUN echo "xdebug.max_nesting_level = 300" >> /etc/php/7.0/apache2/conf.d/20-xdebug.ini
RUN echo "xdebug.max_nesting_level = 300" >> /etc/php/7.0/cli/conf.d/20-xdebug.ini

# Install Composer.
RUN curl -sS https://getcomposer.org/installer | php
RUN mv composer.phar /usr/local/bin/composer

# Install Drush 8.
RUN composer global require drush/drush:8.*
RUN composer global update
# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /root/.composer/vendor/bin/drush /usr/local/bin/drush

# Install Drupal Console. There are no stable releases yet, so set the minimum 
# stability to dev.
RUN curl https://drupalconsole.com/installer -L -o drupal.phar && \
	mv drupal.phar /usr/local/bin/drupal && \
	chmod +x /usr/local/bin/drupal
RUN drupal init

# From opensocial
# Install Open Social via composer.
RUN rm -f /var/www/composer.lock
RUN rm -rf /root/.composer

ADD composer.json /var/www/composer.json
WORKDIR /var/www/
RUN composer install --prefer-dist --no-interaction --no-dev

WORKDIR /var/www/html/
RUN chown -R www-data:www-data *

# Unfortunately, adding the composer vendor dir to the PATH doesn't seem to work. So:
RUN ln -s /var/www/vendor/bin/drush /usr/local/bin/drush

RUN php -r 'opcache_reset();'

# Fix shell.
RUN echo "export TERM=xterm" >> ~/.bashrc
#end from opensocial

# Prep Drupal install.
# Patch .htaccess
RUN sed -i '4iOptions +FollowSymLinks' /var/www/html/.htaccess

# Create database
RUN mysql -u drupal -pdrupal -e "CREATE DATABASE drupal CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci";

# Set up settings.local.php so drush won't add database connections to settings.php
RUN cd /var/www/html/sites/default

# Create settings.local.php
RUN echo "<?php

\$settings['install_profile'] = 'social';
\$settings['file_private_path'] =  '/var/www/files_private';
\$databases['default']['default'] = array (
  'database' => 'drupal',
  'username' => 'drupal',
  'password' => 'drupal',
  'prefix' => '',
  'host' => 'localhost',
  'port' => '3306',
  'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
  'driver' => 'mysql',
);
" > settings.local.php


# Install drupal site
RUN cd /var/www/html
# drupal site:install  social --langcode="en" --db-type="mysql" --db-host="127.0.0.1" --db-name="$dir" --db-user="$dir" --db-pass="$dir" --db-port="3306" --site-name="$dir" --site-mail="admin@example.com" --account-name="admin" --account-mail="admin@example.com" --account-pass="admin" --no-interaction
RUN drush -y site-install social  --account-name=admin --account-pass=admin --account-mail=admin@example.com --site-name="Opencourse"
# You don't need --db-url=mysql://$dir:$dir@localhost:3306/$dir in drush because the settings.local.php has it.

# Create private files directory.
RUN mkdir /var/www/files_private
RUN chmod 770 -R /var/www/files_private
RUN chown www-data:www-data -R /var/www/files_private

# Install all required modules
# ocdev is a wrapper for all the dev modules and installs all the production modules. The wrappers are then uninstalled so it is easy to uninstall individual modules.
RUN drush en -y ocdev

# Uninstall the wrapper. Will leave all dependencies installed.
RUN sudo -u rob drush pm-uninstall -y ocdev
RUN sudo -u rob drush pm-uninstall -y ocprod

# give write access to custom so we can export features.
RUN chmod g+w -R $dir/html/modules/custom


RUN chmod ug+w /var/www/sites/default -R && \
	cp /var/www/sites/default/default.settings.php /var/www/sites/default/settings.php && \
	cp /var/www/sites/default/default.services.yml /var/www/sites/default/services.yml && \
	chmod 0660 /var/www/sites/default/settings.php && \
	chmod 0660 /var/www/sites/default/services.yml && \
	chown -R www-data:www-data /var/www/
	
# Changing permissions of all directories to "rwxr-x---"
# find . -type d -exec chmod u=rwx,g=rx,o= '{}' \;

# Changing permissions of all files to "rw-r-----"
#find . -type f -exec chmod u=rw,g=r,o= '{}' \;

# Changing permissions of "files" directories in "sites" to "rwxrwx---"
#cd /var/www/html/sites
#find . -type d -name files -exec chmod ug=rwx,o= '{}' \;

# Changing permissions of all files inside all "files" directories in "/sites" to "rw-rw----"
# Changing permissions of all directories inside all "files" directories in "/sites" to "rwxrwx---"
RUN for x in ./*/files; do && \
	  find ${x} -type d -exec chmod ug=rwx,o= '{}' \;  && \
	  find ${x} -type f -exec chmod ug=rw,o= '{}' \;  && \
	done

# Allow Kernel and Browser tests to be run via PHPUnit.	
RUN sed -i 's/name="SIMPLETEST_DB" value=""/name="SIMPLETEST_DB" value="sqlite:\/\/localhost\/tmp\/db.sqlite"/' /var/www/core/phpunit.xml.dist

EXPOSE 80 3306 22 443
CMD exec supervisord -n
