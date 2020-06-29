# Allows for customization of the behavior of the Makefile as well as Docker Compose.
# If it does not exist create it from sample.env.
ENV_FILE=$(shell \
	if [ ! -f .env ]; then \
		cp sample.env .env; \
	fi; \
	echo .env)
include $(ENV_FILE)

# Make sure all docker-compose commands use the given project 
# name by setting the appropriate environment variables.
export

# Services that are not produced by isle-buildkit.
EXTERNAL_SERVICES := etcd watchtower traefik

# The minimal set of docker-compose files required to be able to run anything.
REQUIRED_SERIVCES := activemq alpaca blazegraph cantaloupe crayfish crayfits drupal fcrepo mariadb matomo solr

# Set of docker-compose files that are helpful when doing development locally.
ifeq ($(INCLUDE_WATCHTOWER_SERVICE), true)
	WATCHTOWER_SERVICE := watchtower
endif

# The service traefik may be optional if we are sharing one from another project.
# Set of docker-compose files that are helpful when doing development locally.
ifeq ($(INCLUDE_TRAEFIK_SERVICE), true)
	TRAEFIK_SERVICE := traefik
endif

# Allows for customization of the environment variables inside of the containers.
# If it does not exist create it from docker-compose.sample.env.yml.
OVERRIDE_SERVICE_ENVIRONMENT_VARIABLES=$(shell \
	if [ ! -f docker-compose.env.yml ]; then \
		cp docker-compose.sample.env.yml docker-compose.env.yml; \
	fi; \
	echo env)

# The services to be run (order is important), as services can override one
# another. Traefik must be last if included as otherwise its network 
# definition for `gateway` will be overriden.
SERVICES := $(REQUIRED_SERIVCES) $(WATCHTOWER_SERVICE) $(ENVIRONMENT) $(TRAEFIK_SERVICE) $(OVERRIDE_SERVICE_ENVIRONMENT_VARIABLES)

# Local environment requires that we have a working codebase 
# before starting as it needs to be bind mounted.
ifeq ($(ENVIRONMENT), local)
	UP_PREREQUISITES := codebase composer-cache
endif

# Custom environment requires that we have a working codebase
# as well as an exported configuration, in the codebase directory
# In addition to the docker image produced by build.
ifeq ($(ENVIRONMENT), custom)
	UP_PREREQUISITES := codebase build
endif

default: up

.SILENT: docker-compose.yml
docker-compose.yml: $(SERVICES:%=docker-compose.%.yml) .env
	docker-compose $(SERVICES:%=-f docker-compose.%.yml) config > docker-compose.yml

.PHONY: pull
pull: docker-compose.yml
ifeq ($(REPOSITORY), local)
	# Only need to pull external services if using local images.
	docker-compose pull $(filter $(EXTERNAL_SERVICES), $(SERVICES))
else
	docker-compose pull
endif

.PHONY: up 
up: docker-compose.yml $(UP_PREREQUISITES)
	docker-compose up --remove-orphans --detach

.PHONY: build
build: docker-compose.yml
	$(shell if [ ! -f $(PROJECT_DRUPAL_DOCKERFILE) ]; then cp $(CURDIR)/sample.Dockerfile $(PROJECT_DRUPAL_DOCKERFILE); fi)
	docker build -f $(PROJECT_DRUPAL_DOCKERFILE) -t isle-dc_drupal --build-arg REPOSITORY=$(REPOSITORY) --build-arg TAG=$(TAG) .

# Delete volumes that do not have the prune=false label.
# This allows use to keep cache volumes used for building.
.PHONY: prune-volumes
prune-volumes:
	docker volume prune --filter label!=prune=false

# Mount the codebase folder for using composer etc.
CODEBASE_CMD = docker run --rm -ti \
	-e COMPOSER_HOME=/composer \
	-v isle-dc-composer-cache:/composer \
	-v $(CURDIR)/codebase:/codebase \
	-w /codebase  \
	--entrypoint bash \
	$(REPOSITORY)/drupal:$(TAG) -c

# Checks if the `codebase` directory is empty only allows the subsquent command
# to run if it is empty.
IF_CODEBASE_EMPTY = $(CODEBASE_CMD) 'test "$$(ls -A)"' && echo "codebase already exists" ||

# Create a cache for composer, avoids potential perm/issues with bind mounts.
.SILENT: composer-cache
composer-cache:
	docker volume create --label prune=false isle-dc-composer-cache > /dev/null

.SILENT: codebase
codebase: docker-compose.yml composer-cache
ifneq ($(REPOSITORY), local)
	@docker-compose pull drupal
endif
	-mkdir -p $(CURDIR)/codebase
	# Make sure that nginx can write to the folder as well (chmod/chown).
	# A gid of `101` is used here to match the `nginx` user.
	# The user is set to the current users so they can
	# read/write the files in the codebase directory.
	#
	# Drush is added as an additional requirement as subsequent commands
	# for installing a site, etc depend on it.
	$(IF_CODEBASE_EMPTY) $(CODEBASE_CMD) " \
		chown $(shell id -u):101 /codebase && \
		chmod u+s,g+s,a+rwx /codebase && \
		composer create-project --ignore-platform-reqs --no-interaction --no-install $(COMPOSER_PROJECT) /codebase && \
		composer require -- drush/drush && \
		composer install && \
		chown -R $(shell id -u):101 /codebase"

# Creates required databases for drupal site(s) using environment variables.
.PHONY: databases
.SILENT: databases
databases: up
	# Sleep required after up as the container takes a second to become responsive.
	sleep 3
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites create_database"

# Installs drupal site(s) using environment variables.
.PHONY: install
.SILENT: install
install: databases
	# Ensure the files directory is writable by nginx, as when it is a new volume it is owned by root.
	docker-compose exec drupal find /var/www/drupal/web/sites -type d -name files -mindepth 1 -maxdepth 2 -exec chown -R 100:101 {} \;
	docker-compose exec drupal find /var/www/drupal/web/sites -type d -name files -mindepth 1 -maxdepth 2 -exec chmod -R ug+rw {} \;
	# Allow changes to settings.php
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chmod a=rwx {} \;
	# Install all sites.
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites install_site"
	# Restrict changes to settings.php
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chmod a=,ug=r {} \;

# Exports site config to codebase folder where it resides will depend on the configuration of codebase.
.PHONY: export-config
.SILENT: export-config
export-config:
	# Export the configuration for all sites.
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites export_config"
	# Make sure the configuration directorys can be modified by the host user.
	docker-compose exec drupal with-contenv chown -R $(shell id -u):101 config

# Exports site config to codebase folder where it resides will depend on the configuration of codebase.
.PHONY: import-config
.SILENT: import-config
import-config:
	# Export the configuration for all sites.
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites import_config"

# Helper function to use a configuration from a different site.
# Changes the uuid for the site in the database to match the
# one in the codebase folders `config_sync_directory`.
.PHONY: set-site-uuid-from-config
.SILENT: set-site-uuid-from-config
set-site-uuid-from-config:
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites set_site_uuid"

# Updates settings.php according to the environment variables.
.PHONY: update-settings-php
.SILENT: update-settings-php
update-settings-php: #install
	# Copy UpdateSettingsCommands.php into the codebase so we can use it.
	docker run --rm -v $(CURDIR)/codebase/drush/Commands:/copy --entrypoint cp $(REPOSITORY)/drupal:$(TAG) /var/www/drupal/drush/Commands/UpdateSettingsCommands.php /copy
	# Allow changes to settings.php
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chmod a=rw {} \;
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chown 100:101 {} \;
	# Make sure we can modify it and updated it according to environment variables.
	docker-compose exec drupal with-contenv bash -c "source /opt/islandora/utilities.sh; for_all_sites update_settings_php"
	# Restrict changes to settings.php
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chmod a=,ug=r {} \;
	docker-compose exec drupal find /var/www/drupal/web/sites -name settings.php -exec chown $(shell id -u):101 {} \;

# Creates the codebase folder from a running drupal service.
# This can be used to generate the codebase from the islandora/demo image.
.PHONY: create-codebase-from-drupal-service
.SILENT: create-codebase-from-drupal-service
create-codebase-from-drupal-service:
ifneq ($(wildcard $(CURDIR)/codebase),)
	$(error codebase folder already exists)
endif
	$(MAKE) up
	# Wait for Drupal to become responsive (up to 5 minutes).
	docker-compose exec drupal timeout 300 wait-for-open-port.sh localhost 80
	$(MAKE) export-config
	# Need `default` folder to be writeable to copy it down to host.
	docker-compose exec drupal chmod 777 /var/www/drupal/web/sites/default
	docker cp $$(docker-compose ps -q drupal):/var/www/drupal/ codebase
	# Restore expected perms for `default`.
	docker-compose exec drupal chmod 555 /var/www/drupal/web/sites/default

# Helper function to generate keys for the user to use in their docker-compose.env.yml
.PHONY: generate-jwt-keys
.SILENT: generate-jwt-keys
generate-jwt-keys:
	docker run --rm -ti \
		--entrypoint bash \
		$(REPOSITORY)/drupal:$(TAG) -c \
		"openssl genrsa -out /tmp/private.key 2048 &> /dev/null; \
		openssl rsa -pubout -in /tmp/private.key -out /tmp/public.key &> /dev/null; \
		echo $$'\nPrivate Key:\n'; \
		cat /tmp/private.key; \
		echo $$'\nPublic Key:\n'; \
		cat /tmp/public.key; \
		echo $$'\nCopy and paste these keys into your docker-compose.env.yml file where appropriate.'"

# Helper to generate Matomo password, like so:
# make generate-matomo-password MATOMO_USER_PASS=my_new_password
.PHONY: generate-matomo-password
.SILENT: generate-matomo-password
generate-matomo-password:
ifndef MATOMO_USER_PASS
	$(error MATOMO_USER_PASS is not set)
endif
	docker run --rm -ti \
		--entrypoint php \
		$(REPOSITORY)/drupal:$(TAG) -r \
		'echo password_hash(md5("$(MATOMO_USER_PASS)"), PASSWORD_DEFAULT) . "\n";'

# use like this: make drupal_db_load dbfilepath=data/misc dbfilename=latest.sql
drupal_db_load:
	docker cp $(dbfilepath)/$(dbfilename) $(COMPOSE_PROJECT_NAME)_database_1:/tmp/$(dbfilename) && \
	docker-compose exec -T database bash -c "mysql -u root -ppassword drupal_default < /tmp/$(dbfilename)"
