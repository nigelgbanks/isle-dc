#!/usr/bin/with-contenv bash
set -e

source /opt/islandora/utilities.sh

function main {
    # Creates database if does not already exist.
    create_database "default"
    # Needs to be set to do an install from existing configuration.
    drush islandora:settings:create-settings-if-missing
    drush islandora:settings:set-config-sync-directory "${DRUPAL_DEFAULT_CONFIGDIR}"
    install_site "default"
    # Settings like the hash / flystem can be affected by environment variables at runtime.
    update_settings_php "default"
    # Ensure that settings which depend on environment variables like service urls are set dynamically on startup.
    configure_islandora_module "default"
    configure_matomo_module "default"
    configure_openseadragon "default"
    configure_islandora_default_module "default"
    # The following commands require several services
    # to be up and running before they can complete.
    wait_for_required_services "default"
    # Create missing solr cores.
    create_solr_core_with_default_config "default"
    # Create namespace assumed one per site.
    create_blazegraph_namespace_with_default_properties "default"
    # Need to run migration to get expected default content.
    import_islandora_migrations "default"
    # Workaround for this issue (only seems to apply to islandora_fits):
    # https://www.drupal.org/project/drupal/issues/2914213
    cat << EOF > /tmp/fix.php
<?php
use Drupal\taxonomy\Entity\Term;
\$term = array_pop(taxonomy_term_load_multiple_by_name('FITS File'));
\$default = ['uri' => 'https://projects.iq.harvard.edu/fits'];
\$term->set('field_external_uri', \$default);
\$term->save();
EOF
    drush php:script /tmp/fix.php
}
main