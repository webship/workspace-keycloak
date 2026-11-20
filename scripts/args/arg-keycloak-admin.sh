#!/usr/bin/env bash

argparse "$@" <<ARGEOF || exit 1
parser.add_argument('PROJECT_NAME',
                    help='The Keycloak project in this workspace.')
parser.add_argument('-k', '--kcadm',
                    default="_none_",
                    help='A command of the server\'s admin CLI (kcadm.sh), with its arguments, run as the admin of the master realm. Example: --kcadm "get users -r webship --fields username"')
parser.add_argument('--restart',
                    action='store_true',
                    default=False,
                    help='Start the server again (its container), and wait for it.')
parser.add_argument('-a', '--add-users',
                    action='store_true',
                    default=False,
                    help='Add the default accounts to the realm. An account that is already there gets its email, names, password, roles and one-time code back.')
parser.add_argument('-c', '--cancel-users',
                    action='store_true',
                    default=False,
                    help='Delete the default accounts from the realm (never the admin of the master realm).')
ARGEOF
