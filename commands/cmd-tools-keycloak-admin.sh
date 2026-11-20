#!/usr/bin/env bash

# Installed by the Keycloak plugin (plugins.sh --install keycloak); __WORKSPACE__ is the workspace it was installed into.
#
# The admin CLI (kcadm.sh) of one Keycloak site of this workspace, in the server's container, logged in as the
# admin of the master realm (the workspace account): say what the server is, run a command of the admin CLI,
# start the server again, add or cancel the default accounts. Nothing here runs on the host.

# Bootstrap.
# Find the workspace tooling from this script, so a fresh clone needs no setup.
WORKSPACE_SCRIPTS="${WORKSPACE_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../core/scripts" && pwd)}";
source ${WORKSPACE_SCRIPTS}/bootstrap.sh || exit 1 ;

# Load workspace settings.
eval $(parse_yaml ${WORKSPACE_CONFIG}/workspace.__WORKSPACE__.settings.yml);

# Distribution.
distribution_name="keycloak";

ARGPARSE_DESCRIPTION="Run the admin CLI of a Keycloak site of __WORKSPACE__: status, a kcadm.sh command, a restart, the default accounts"
# The args file comes with the plugin: core/scripts/plugins/keycloak/ is where plugins.sh --install puts it.
source ${WORKSPACE_SCRIPTS}/plugins/keycloak/args/arg-keycloak-admin.sh || exit 1 ;

shift $#;

keycloak_admin_tool ;
