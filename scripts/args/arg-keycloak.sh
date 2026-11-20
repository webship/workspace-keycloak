#!/usr/bin/env bash

argparse "$@" <<ARGEOF || exit 1
parser.add_argument('PROJECT_NAME',
                    help='The name of the project: its folder, its DDEV project and its host name.')
parser.add_argument('-i', '--install',
                    action='store_true',
                    default=False,
                    help='Import the realm (the plugin\'s test realm, or --realm) and make the workspace account the admin of the master realm.')
parser.add_argument('-a', '--add-users',
                    action='store_true',
                    default=False,
                    help='With --install, add the default accounts (administrator, editor, user, otpuser): the ones the test scenarios log in as.')
parser.add_argument('-r', '--realm',
                    dest='realm_file',
                    default="",
                    help='With --install, import this realm file (JSON) instead of the plugin\'s test realm. Example: --realm ~/realms/my-realm.json')
parser.add_argument('-v', '--keycloak-version',
                    default="",
                    help='The release of the server (a tag of quay.io/keycloak/keycloak), 26.8.2 by default. Example: --keycloak-version 26.8.2')
parser.add_argument('-t', '--login-theme',
                    default="",
                    help='With --install, the login theme of the realm: keycloak.v2 (the server\'s default) or keycloak. Example: --login-theme keycloak')
parser.add_argument('-l', '--launch',
                    action='store_true',
                    default=False,
                    help='Open the test app in a browser when it is ready.')
ARGEOF
