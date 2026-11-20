#!/usr/bin/env bash

# workspace-name: Keycloak (a sign-in server in a container, with a test app)

# Installed by the Keycloak plugin (plugins.sh --install keycloak); __WORKSPACE__ is the workspace it was installed into.
#
# Build a Keycloak sign-in server in a container: the official image at its current release in development mode,
# behind the project's web server under /auth, with a small test app at https://<name>.ddev.site that signs in
# through it, and the project's mail catcher for its mail. With --install the realm is imported (the plugin's
# test realm, or --realm <file>) and the workspace account becomes the admin of the master realm; with
# --add-users the realm also gets the default accounts.

# Bootstrap.
# Find the workspace tooling from this script, so a fresh clone needs no setup.
WORKSPACE_SCRIPTS="${WORKSPACE_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../core/scripts" && pwd)}";
source ${WORKSPACE_SCRIPTS}/bootstrap.sh || exit 1 ;

# Load workspace settings.
eval $(parse_yaml ${WORKSPACE_CONFIG}/workspace.__WORKSPACE__.settings.yml);

# Distribution.
distribution_name="keycloak";
distribution_title="Keycloak";
distribution_webroot="app";

ARGPARSE_DESCRIPTION="Build a ${distribution_title} project in __WORKSPACE__"
# The args file comes with the plugin: core/scripts/plugins/keycloak/ is where plugins.sh --install puts it.
source ${WORKSPACE_SCRIPTS}/plugins/keycloak/args/arg-keycloak.sh || exit 1 ;

shift $#;

keycloak_build ;
