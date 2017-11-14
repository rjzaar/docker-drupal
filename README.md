Opencourse
==============================

[![](https://images.microbadger.com/badges/image/wadmiraal/drupal.svg)](https://microbadger.com/images/wadmiraal/drupal "Get your own image badge on microbadger.com") [![Build Status](https://travis-ci.org/wadmiraal/docker-drupal.svg?branch=master)](https://travis-ci.org/wadmiraal/docker-drupal)

Opencourse modules built on [varbase](https://www.drupal.org/project/varbase) This is a merge of opensocial and wadmiraal/docker-drupal. It contains a LAMP stack and an SSH server, along with an up to date version of Drush. It is based on [Debian Stretch](https://wiki.debian.org/DebianStretch). It then installs opencourse with composer.

Summary
-------

This image contains:

* Apache 2.4
* MariaDB 10.1
* PHP 7.0
* Drush 8
* The latest release of Drupal Console (for `8` and `8.*.*` tags)
* Drupal 7 or 8 (depending on tag)
* Composer
* PHPMyAdmin
* Blackfire

When launching, the container will contain a fully-installed, ready to use Drupal site.

### Passwords

* Drupal: `admin:admin`
* MySQL: `root:` (no password); `drupal:drupal`
* SSH: `root:root`

### Exposed ports

* 80 and 443 (Apache)
* 22 (SSH)
* 3306 (MySQL)

### Environment variables

If you wish to enable [Blackfire](https://blackfire.io) for profiling, set the following environment variables:

* `BLACKFIREIO_SERVER_ID`: Your Blackfire server ID
* `BLACKFIREIO_SERVER_TOKEN`: Your Blackfire server token

Tutorial
--------

You can read more about this image [here](http://wadmiraal.net/lore/2015/03/27/use-docker-to-kickstart-your-drupal-development/).

Installation
------------

### Github

Clone the repository locally and build it:

	git clone git@github.com:rjzaar/opencourse.git
	cd docker-drupal
	docker build -t yourname/drupal .

Notice that there are several branches. The `master` branch always refers to the current recommended major Drupal version (version 8 at the time of writing). Other branches, like `7.x`, reflect prior versions.

### Docker repository

Get the image:

	docker pull rjzaar/docker-opencourse

#### Tags

You can specify the specific Drupal version you want, like `8.0.0`. For example:

	docker pull rjzaar/docker-opencourse:8.0.0

You can also use the latest Drupal version of any major release branch by omitting the minor (and patch) version information:

	docker pull rjzaar/docker-opencourse:8

Running it
----------

For optimum usage, map some local directories to the container for easier development. I personally create at least a `modules/` directory which will contain my custom modules. You can do the same for your themes.

The container exposes its `80` and `443` ports (Apache), its `3306` port (MySQL) and its `22` port (SSH). Make good use of this by forwarding your local ports. You should at least forward to port `80` (using `-p local_port:80`, like `-p 8080:80`). A good idea is to also forward port `22`, so you can use Drush from your local machine using aliases, and directly execute commands inside the container, without attaching to it.

Here's an example just running the container and forwarding `localhost:8080` and `localhost:8022` to the container:

	docker run -d -p 8080:80 -p 8022:22 -t rjzaar/docker-opencourse

If you want to run in HTTPS, you can use:

        docker run -d -p 8443:443 -p 8022:22 -t rjzaar/docker-opencourse

### Writing code locally

Here's an example running the container, forwarding port `8080` like before, but also mounting Drupal's `sites/all/modules/custom/` folder to my local `modules/` folder. I can then start writing code on my local machine, directly in this folder, and it will be available inside the container:

	docker run -d -p 8080:80 -v `pwd`/modules:/var/www/sites/all/modules/custom -t rjzaar/docker-opencourse

### Using Drush

Using Drush aliases, you can directly execute Drush commands locally and have them be executed inside the container. Create a new aliases file in your home directory and add the following:

	# ~/.drush/docker.aliases.drushrc.php
	<?php
	$aliases['opencourse'] = array(
	  'root' => '/var/www',
	  'remote-user' => 'root',
	  'remote-host' => 'localhost',
	  'ssh-options' => '-p 8022', // Or any other port you specify when running the container
	);

Next, if you do not wish to type the root password everytime you run a Drush command, copy the content of your local SSH public key (usually `~/.ssh/id_rsa.pub`; read [here](https://help.github.com/articles/generating-ssh-keys/) on how to generate one if you don't have it). SSH into the running container:

	# If you forwarded another port than 8022, change accordingly.
	# Password is "root".
	ssh root@localhost -p 8022

Once you're logged in, add the contents of your `id_rsa.pub` file to `/root/.ssh/authorized_keys`. Exit.

You should now be able to call:

	drush @docker.opencourse cc all

This will clear the cache of your Drupal site. All other commands will function as well.

### Using Drupal Console

Similarly to Drush, Drupal Console can also be run locally, and execute commands remotely. Create a new file called `~/.console/sites/docker.yml` and add the following contents:

	# ~/.console/sites/docker.yml
	opencourse:
		root: /var/www
		host: localhost
		port: 8022 # Or any other port you specify when running the container
		user: root
		console: drupal

You can now call something like:

	drupal --target=docker.opencourse module:download ctools 8.x-3.0-alpha19

You can find more information about Drupal Console [in the official documentation](https://hechoendrupal.gitbooks.io/drupal-console/content/en/using/how-to-use-drupal-console-in-a-remote-installation.html).

### Running tests

*Note: did you know you can now run tests very quickly without having to maintain a local Drupal instance? Check [drupal-run-tests.sh](https://github.com/wadmiraal/drupal-run-tests) for more information.*

If you want to run tests, you may need to take some additional steps. Drupal's Simpletest will use cURL to simulate user interactions with a freshly installed site when running tests. This "virtual" site resides under `http://localhost:[forwarded ip]`. This gives issues, though, as the *container* uses port `80`. By default, the container's virtual host will actually listen to *any* port, but you still need to tell Apache on which ports it should bind. By default, it will bind on `80` *and* `8080`, so if you use the above examples, you can start running your tests straight away. But, if you choose to forward to a different port, you must add it to Apache's configuration and restart Apache. You can simply do the following:

	# If you forwarded to another port than 8022, change accordingly.
	# Password is "root".
	ssh root@localhost -p 8022
	# Change the port number accordingly. This example is if you forward
	# to port 8081.
	echo "Listen 8081" >> /etc/apache2/ports.conf
	/etc/init.d/apache2 restart

Or, shorthand:

	ssh root@localhost -p 8022 -C 'echo "Listen 8081" >> /etc/apache2/ports.conf && /etc/init.d/apache2 restart'

If you want to run tests from HTTPS, though, you will need to edit the VHost file `/etc/apache2/sites-available/default-ssl.conf` as well, and add your port to the list.

### MySQL and PHPMyAdmin

PHPMyAdmin is available at `/phpmyadmin`. The MySQL port `3306` is exposed. The root account for MySQL is `root` (no password).

### Blackfire

[Blackfire](https://blackfire.io) is a free PHP profiling tool. It offers very detailed and comprehensive insight into your code. To use Blackfire, you must first register on the site. Once registered, you will get a *server ID* and a *server token*. You pass these to the container, and it will fire up Blackfire automatically.

Example:

	docker run -it --rm -e BLACKFIREIO_SERVER_ID="[your id here]" -e BLACKFIREIO_SERVER_TOKEN="[your token here]" -p 8022:22 -p 8080:80 rjzaar/docker-opencourse

You can now start profiling your application.

