#!/usr/bin/env bash

# Keycloak for the Webship Workspace: build a sign-in server with a test app next to it, run its admin CLI,
# add its default accounts, and wire its step pack into the testing setup.
#
# Placed by `plugins.sh --install keycloak` in core/scripts/plugins/keycloak/functions/, where bootstrap
# sources it after the core's own functions. Everything runs in containers (DDEV by default), never on the
# host: the server is the official image (quay.io/keycloak/keycloak) in development mode, a service of the
# project behind the project's own web server under /auth, with its data in a volume of the project (removing
# the project removes it); the web server serves a small test app at the root that signs in through it; the
# project's mail catcher takes the server's mail. No public domain, no hosted service, no account anywhere.
#
# DDEV has no project type for Keycloak, so a site of this plugin is recognised by a file
# (.ddev/config.keycloak.yaml, written by the builder), and four names are the ones the core's tools look for:
#   set_keycloak_users          the default accounts                     (cmd-tools-add-users.sh <project> keycloak)
#   add_keycloak_users          create them with the server's admin CLI  (the same tool, and --add-users of the builder)
#   cancel_keycloak_users       delete them                              (cmd-tools-cancel-users.sh <project> keycloak)
#   testing_configure_keycloak  the step pack in the testing stack       (cmd-tools-testing.sh <project>)

# The step pack a Keycloak site is tested with, and the release line it is required at.
readonly KEYCLOAK_STEPS_PACKAGE='@webship-js/keycloak-steps';
readonly KEYCLOAK_STEPS_VERSION='^2.0.0';

# The server's release the builder installs when none is asked for (a tag of quay.io/keycloak/keycloak), and
# the official JavaScript adapter the test app uses (keycloak-js, from npm).
readonly KEYCLOAK_DEFAULT_VERSION='26.8.2';
readonly KEYCLOAK_JS_VERSION='26.2.5';

# The key of otpuser's one-time code, as the server keeps it (20 characters). An authenticator app gets it in
# base32: O5SWE43INFYHIZLTORXXI4DTMVRXEZLU (the users registry of the testing setup carries that form).
readonly KEYCLOAK_OTP_SECRET='webshiptestotpsecret';
readonly KEYCLOAK_OTP_KEY='O5SWE43INFYHIZLTORXXI4DTMVRXEZLU';

# The default accounts, the ones a scenario logs in as: the realm's admin, an editor (the realm role editor),
# a user with no role of its own, and a user with a one-time code set up. Accounts are configuration, created
# once in the realm; a test suite never creates or deletes one. The admin of the master realm the builder
# makes with --install is the workspace account and is not in this list.
function set_keycloak_users() {
  users=(administrator editor user otpuser);
  local user ;
  for user in "${users[@]}" ; do
    printf -v "user_${user}_name" '%s' "${user}" ;
    printf -v "user_${user}_mail" '%s' "${user}@example.com" ;
    printf -v "user_${user}_password" '%s' 'dD.123123ddd' ;
  done
  user_administrator_role='realm-admin' ;
  user_editor_role='editor' ;
  user_user_role='user' ;
  user_otpuser_role='otp' ;
}

# Is this folder a Keycloak site of this plugin? The builder leaves .ddev/config.keycloak.yaml in it.
function keycloak_is_project() {
  [ -f "$1/.ddev/config.keycloak.yaml" ] ;
}

# Go to the project a tool was asked about, or say why not.
function keycloak_enter_project() {
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}";
  if [ ! -d "${project_path}" ] ; then
    echo "No project ${PROJECT_NAME} in ${WORKSPACE_ROOT}/${doc_name}." ;
    return 1 ;
  fi
  if ! keycloak_is_project "${project_path}" ; then
    echo "${doc_name}/${PROJECT_NAME} is not a Keycloak project of this plugin (it has no .ddev/config.keycloak.yaml)." ;
    return 1 ;
  fi
  cd "${project_path}" || return 1 ;
}

# A value of the site's own settings file (.ddev/config.keycloak.yaml): KEYCLOAK_VERSION, KEYCLOAK_REALM.
function keycloak_setting() {
  sed -n "s/^  - $1=\\(.*\\)\$/\\1/p" "${2:-.}/.ddev/config.keycloak.yaml" 2>/dev/null | head -n 1 ;
}

# The name of the realm of a realm file (its "realm" key).
function keycloak_realm_of() {
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["realm"])' "$1" 2>/dev/null ;
}

# The payload of keycloak-site.sh: lines of KEY=base64(value), all of it in base64 again, from variables.
function keycloak_payload() {
  local line="" key ;
  for key in "$@" ; do
    line="${line}${key}=$(printf '%s' "${!key}" | base64 -w0)"$'\n' ;
  done
  printf '%s' "${line}" | base64 -w0 ;
}

# Run verbs of keycloak-site.sh with bash in the server's container, with the payload on its first line: no
# password on a command line, in a file of the project, or in what a failed run prints.
function keycloak_site() {
  local verbs="$1" ; shift ;
  local script="${WORKSPACE_SCRIPTS}/plugins/keycloak/keycloak-site.sh" ;
  if [ ! -f "${script}" ] ; then
    echo "keycloak-site.sh is not in ${WORKSPACE_SCRIPTS}/plugins/keycloak: install the plugin (plugins.sh --install keycloak)." ;
    return 1 ;
  fi
  { printf "SITE_PAYLOAD='%s'\n" "$(keycloak_payload "$@")"; cat "${script}"; } \
    | ddev exec -s keycloak "SITE_VERBS='${verbs}' bash -s" ;
}

# The partial import of the default accounts (the list set_keycloak_users loads) for a realm, with their
# passwords, their roles and otpuser's one-time code.
function keycloak_accounts_json() {
  local realm="$1" rows="" user name mail password role ;
  for user in "${users[@]}" ; do
    name="user_${user}_name"; mail="user_${user}_mail"; password="user_${user}_password"; role="user_${user}_role";
    rows="${rows}${!name}"$'\x1f'"${!mail}"$'\x1f'"${!password}"$'\x1f'"${!role}"$'\x1e' ;
  done
  KEYCLOAK_ROWS="${rows}" KEYCLOAK_REALM="${realm}" KEYCLOAK_OTP="${KEYCLOAK_OTP_SECRET}" python3 -c '
import json, os
realm = os.environ["KEYCLOAK_REALM"]
users = []
for row in os.environ["KEYCLOAK_ROWS"].split("\x1e"):
    if not row:
        continue
    name, email, password, role = row.split("\x1f")
    credentials = [{"type": "password", "value": password, "temporary": False}]
    user = {"username": name, "email": email, "firstName": name.capitalize(), "lastName": "Webship", "enabled": True,
            "emailVerified": True, "requiredActions": [], "credentials": credentials, "realmRoles": ["default-roles-" + realm]}
    if role == "realm-admin":
        user["clientRoles"] = {"realm-management": ["realm-admin"]}
    elif role == "otp":
        credentials.append({"type": "otp", "userLabel": "Test phone", "secretData": json.dumps({"value": os.environ["KEYCLOAK_OTP"]}),
                            "credentialData": json.dumps({"subType": "totp", "digits": 6, "counter": 0, "period": 30, "algorithm": "HmacSHA1"})})
    elif role and role != "user":
        user["realmRoles"].append(role)
    users.append(user)
print(json.dumps({"ifResourceExists": "OVERWRITE", "users": users}))' ;
}

# The realm roles the default accounts are given (beyond the realm's defaults), one per line.
function keycloak_account_roles() {
  local user role ;
  for user in "${users[@]}" ; do
    role="user_${user}_role" ;
    case "${!role}" in realm-admin|otp|user|'') ;; *) echo "${!role}" ;; esac
  done
}

# The partial import of the permanent admin of the master realm: the workspace account.
function keycloak_owner_json() {
  OWNER_NAME="${account_name}" OWNER_MAIL="${account_mail}" OWNER_PASS="${account_pass}" python3 -c '
import json, os
print(json.dumps({"ifResourceExists": "OVERWRITE", "users": [{
    "username": os.environ["OWNER_NAME"], "email": os.environ["OWNER_MAIL"], "firstName": os.environ["OWNER_NAME"], "lastName": "Workspace",
    "enabled": True, "emailVerified": True,
    "credentials": [{"type": "password", "value": os.environ["OWNER_PASS"], "temporary": False}],
    "realmRoles": ["admin", "default-roles-master"]}]}))' ;
}

# Write the project's files for the server: its service, the web server's /auth/ for it, the site's settings.
# `bootstrap` holds the environment lines of the temporary admin of the first start, or nothing.
function keycloak_write_config() {
  local project_path="$1" name="$2" version="$3" bootstrap="$4" realm="$5" ;
  local app_url="https://${name}.ddev.site" ;
  mkdir -p "${project_path}/.ddev/nginx" || return 1 ;
  cat > "${project_path}/.ddev/docker-compose.keycloak.yaml" <<YAMLEOF
## The sign-in server of this project (Keycloak ${version}, development mode), as a service. The project's web
## server sends /auth/ to it (.ddev/nginx/keycloak.conf). It imports the realm files of keycloak/import/ at its
## first start, and keeps its data in a volume of the project. Written by the Keycloak builder of the workspace;
## build again rather than editing by hand.
services:
  keycloak:
    container_name: ddev-\${DDEV_SITENAME}-keycloak
    image: quay.io/keycloak/keycloak:${version}
    command: ["start-dev", "--import-realm"]
    restart: "no"
    labels:
      com.ddev.site-name: \${DDEV_SITENAME}
      com.ddev.approot: \${DDEV_APPROOT}
    environment:
      - KC_HTTP_RELATIVE_PATH=/auth
      - KC_HOSTNAME=${app_url}/auth
      - KC_PROXY_HEADERS=xforwarded
      - KC_HTTP_ENABLED=true
      - KC_HEALTH_ENABLED=true
      - JAVA_OPTS_KC_HEAP=-Xms128m -Xmx768m
      - APP_URL=${app_url}
      - SMTP_HOST=web
      - SMTP_PORT=1025
${bootstrap}    expose:
      - "8080"
      - "9000"
    volumes:
      - \${DDEV_APPROOT}/keycloak/import:/opt/keycloak/data/import:ro
      - keycloak-data:/opt/keycloak/data
volumes:
  keycloak-data:
    name: ddev-\${DDEV_SITENAME}-keycloak-data
YAMLEOF
  cat > "${project_path}/.ddev/nginx/keycloak.conf" <<'NGINXEOF'
# The sign-in server under /auth/ of the site (the keycloak service); everything else is the test app of the
# docroot. ^~ keeps the static-file rules of the web server off the server's own files. Written by the
# Keycloak builder of the workspace.
location ^~ /auth/ {
    proxy_pass http://keycloak:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    proxy_set_header X-Forwarded-Port $http_x_forwarded_port;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffer_size 128k;
    proxy_buffers 4 256k;
    proxy_busy_buffers_size 256k;
}
NGINXEOF
  cat > "${project_path}/.ddev/config.keycloak.yaml" <<YAMLEOF
# Keycloak in this project: a service of its own (docker-compose.keycloak.yaml). Written by the Keycloak builder
# of the workspace; build again rather than editing by hand.
web_environment:
  - KEYCLOAK_VERSION=${version}
  - KEYCLOAK_REALM=${realm}
YAMLEOF
}

# The test app at the root of the docroot (app/): the plugin's page with the official JavaScript adapter
# (keycloak-js, from npm), as the client webship-app, and the same page at /partner/ as webship-partner.
function keycloak_write_app() {
  local project_path="$1" name="$2" realm="$3" ;
  local from="${WORKSPACE_SCRIPTS}/plugins/keycloak" app="${project_path}/app" ;
  mkdir -p "${app}/partner" || return 1 ;
  cp "${from}/keycloak-app.html" "${app}/index.html" && cp "${from}/keycloak-app.js" "${app}/app.js" \
    && cp "${from}/keycloak-app.css" "${app}/app.css" && cp "${from}/keycloak-silent-check-sso.html" "${app}/silent-check-sso.html" \
    && cp "${from}/keycloak-silent-check-sso.html" "${app}/partner/silent-check-sso.html" \
    && cp "${from}/keycloak-app-package.json" "${app}/package.json" || return 1 ;
  sed -e 's|data-client="webship-app" data-app-name="Webship test app"|data-client="webship-partner" data-app-name="Webship partner app"|' \
      -e 's|<title>Webship test app</title>|<title>Webship partner app</title>|' \
      -e 's|<h1>Webship test app</h1>|<h1>Webship partner app</h1>|' \
      -e 's|<p>A test app that signs people in through the site.s sign-in server.</p>|<p>An app of another party: a person grants it access to their account first.</p>|' \
      "${app}/index.html" > "${app}/partner/index.html" || return 1 ;
  printf '{\n  "url": "https://%s.ddev.site/auth",\n  "realm": "%s"\n}\n' "${name}" "${realm}" > "${app}/config.json" ;
}

# Wait until the server says it is ready (its health endpoint, on its management port).
function keycloak_wait() {
  local attempt ;
  for attempt in $(seq 1 120) ; do
    if ddev exec "curl -fsS http://keycloak:9000/auth/health/ready" < /dev/null > /dev/null 2>&1 ; then
      return 0 ;
    fi
    sleep 2 ;
  done
  echo "The sign-in server did not get ready; the end of its log:" ;
  ddev logs -s keycloak --tail 60 < /dev/null 2>/dev/null ;
  return 1 ;
}

# The release the server runs, as its image says it.
function keycloak_version() {
  # From the project's folder, wherever the caller stands (adding the accounts ends in the sites folder).
  ( cd "${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" 2>/dev/null && ddev exec -s keycloak "cat /opt/keycloak/version.txt" < /dev/null 2>/dev/null ) | tr -d '\r' | sed 's/^Keycloak - Version //' | head -n 1 ;
}

# Build a Keycloak site from nothing: the project, the server's service and the test app; with --install the
# realm (the plugin's, or --realm <file>) and the workspace account as the admin of the master realm; with
# --add-users the default accounts.
function keycloak_build() {
  trim_project_name ;
  local base_url="https://${PROJECT_NAME}.ddev.site" ;
  local version="${KEYCLOAK_VERSION:-${site_keycloak_version:-${KEYCLOAK_DEFAULT_VERSION}}}" ;
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" ;
  local realm_file="${REALM_FILE:-}" theme="${LOGIN_THEME:-}" realm="" ;

  if ! [[ "${version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$|^latest$|^nightly$ ]] ; then
    echo "--keycloak-version takes a release (26.8.2), latest or nightly, not ${version}. Nothing was changed." ;
    exit 1 ;
  fi
  if [ "${ADD_USERS}" == 'yes' ] && [ "${INSTALL}" != 'yes' ] ; then
    echo "--add-users needs --install: the default accounts go into the realm --install imports." ;
    exit 1 ;
  fi
  if [ -n "${realm_file}" ] && [ "${INSTALL}" != 'yes' ] ; then
    echo "--realm needs --install: the realm file is imported by the install." ;
    exit 1 ;
  fi
  if [ -n "${realm_file}" ] ; then
    realm_file="$(cd "$(dirname "${realm_file}")" 2>/dev/null && pwd)/$(basename "${realm_file}")" ;
    if [ ! -f "${realm_file}" ] || [ -z "$(keycloak_realm_of "${realm_file}")" ] ; then
      echo "--realm takes a realm file (JSON with a \"realm\" name), not ${REALM_FILE}. Nothing was changed." ;
      exit 1 ;
    fi
  fi
  if [ ${#PROJECT_NAME} -gt 40 ] || ! [[ "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] ; then
    echo "The project name ${PROJECT_NAME} must be small letters, digits and dashes (its address and its container take it). Nothing was changed." ;
    exit 1 ;
  fi
  if [ "${INSTALL}" == 'yes' ] && [ ${#account_pass} -lt 8 ] ; then
    echo "The workspace account's password is not set (core/config/settings.yml): --install makes it the server's admin. Nothing was changed." ;
    exit 1 ;
  fi

  cd ${WORKSPACE_ROOT}/${doc_name} || exit 1 ;

  # A project of the same name goes first, with its containers and its volumes.
  drop_database ;
  docker volume rm "ddev-${PROJECT_NAME}-keycloak-data" > /dev/null 2>&1 ;
  rm -rf "${PROJECT_NAME}" ;
  mkdir -p "${PROJECT_NAME}/keycloak/import" ;
  cd "${project_path}" || exit 1 ;

  # A generic project whose web server serves the test app from app/ and the server under /auth/: no database
  # of the container tool's own (the server keeps its data in its own file database), the Node.js of the
  # workspace for the app's packages and a test suite.
  ddev config --project-type=generic --webserver-type=nginx-fpm --docroot=app --project-name=${PROJECT_NAME} \
    --omit-containers=db --nodejs-version=$(ddev_nodejs_version) < /dev/null || exit 1 ;

  local bootstrap="" temp_admin="first-start-admin" temp_password="" ;
  if [ "${INSTALL}" == 'yes' ] ; then
    if [ -n "${realm_file}" ] ; then
      cp "${realm_file}" keycloak/import/ || exit 1 ;
      realm="$(keycloak_realm_of "${realm_file}")" ;
    else
      cp "${WORKSPACE_SCRIPTS}/plugins/keycloak/keycloak-realm.json" keycloak/import/webship-realm.json || exit 1 ;
      realm="webship" ;
    fi
    if [ -n "${theme}" ] ; then
      python3 - "keycloak/import/$(ls keycloak/import | head -n 1)" "${theme}" <<'PYEOF' || exit 1
import json, sys
path, theme = sys.argv[1:3]
data = json.load(open(path))
data["loginTheme"] = theme
json.dump(data, open(path, "w"), indent=2)
PYEOF
    fi
    # The server's admin at its first start: a temporary one with a password of this build only, replaced by
    # the workspace account once the server answers.
    temp_password="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)" ;
    bootstrap="      - KC_BOOTSTRAP_ADMIN_USERNAME=${temp_admin}
      - KC_BOOTSTRAP_ADMIN_PASSWORD=${temp_password}
" ;
  fi
  keycloak_write_config "${project_path}" "${PROJECT_NAME}" "${version}" "${bootstrap}" "${realm}" || exit 1 ;
  keycloak_write_app "${project_path}" "${PROJECT_NAME}" "${realm:-webship}" || exit 1 ;

  echo "Starting the project and the sign-in server (Keycloak ${version}): the image is about 470 MB the first time." ;
  ddev_up start -y < /dev/null || exit 1 ;
  echo "Installing the test app's packages (keycloak-js ${KEYCLOAK_JS_VERSION})." ;
  ddev exec "cd /var/www/html/app && npm install --no-audit --no-fund --loglevel=error" < /dev/null || exit 1 ;
  keycloak_wait || exit 1 ;

  if [ "${INSTALL}" == 'yes' ] ; then
    echo "Making the workspace account the admin of the master realm." ;
    local ADMIN_USER="${temp_admin}" ADMIN_PASSWORD="${temp_password}" OWNER_USER="${account_name}" OWNER_PASSWORD="${account_pass}" OWNER REALM="${realm}" ;
    OWNER="$(keycloak_owner_json)" ;
    keycloak_site owner ADMIN_USER ADMIN_PASSWORD OWNER_USER OWNER_PASSWORD OWNER || { echo "The server's admin could not be made." ; exit 1 ; } ;
    # The temporary admin is gone: its password leaves the project's files.
    keycloak_write_config "${project_path}" "${PROJECT_NAME}" "${version}" "" "${realm}" || exit 1 ;
    if [ "${ADD_USERS}" == 'yes' ] ; then
      set_keycloak_users ;
      add_keycloak_users || exit 1 ;
      users=() ;
    fi
    echo "${doc_name} ${PROJECT_NAME} has been installed: Keycloak $(keycloak_version), realm ${realm}.";
    echo "The test app: ${base_url} · the server: ${base_url}/auth (admin console: ${base_url}/auth/admin/${realm}/console/) · its mail: ${base_url}:8026";
    echo "The admin of the master realm is ${account_name}: ${base_url}/auth/admin/master/console/";
  else
    echo "${doc_name} ${PROJECT_NAME} is ready, without an admin and without a realm: Keycloak $(keycloak_version) at ${base_url}/auth.";
    echo "Build it again with --install (and --add-users) to import the realm and make the workspace account its admin.";
  fi

  if [ "${LAUNCH}" == 'yes' ] ; then
    ddev launch "${base_url}" ;
  fi

  cd ${WORKSPACE_ROOT}/${doc_name};
}

# The admin of the master realm the site script logs in as: the workspace account (the builder's --install).
function keycloak_admin_payload_vars() {
  ADMIN_USER="${account_name}" ;
  ADMIN_PASSWORD="${account_pass}" ;
  REALM="$(keycloak_setting KEYCLOAK_REALM)" ;
  REALM="${REALM:-webship}" ;
}

# Create the default accounts with the server's admin CLI: a partial import that also gives an existing
# account back its email, names, password, roles and one-time code. The list is loaded by the caller
# (set_keycloak_users): the core's add_users, the builder, the tool.
function add_keycloak_users() {
  keycloak_enter_project || return 1 ;
  local user user_name user_mail user_password user_role ;
  for user in "${users[@]}" ; do
    user_name="user_${user}_name"; user_mail="user_${user}_mail";
    user_password="user_${user}_password"; user_role="user_${user}_role";

    echo " ---------------------------------------------------------------- ";
    echo "      User name: ${!user_name}";
    echo "      User mail: ${!user_mail}";
    echo "  User password: ${!user_password}";
    echo "      User role: ${!user_role}";
    echo " ================================================================= ";
  done
  local ADMIN_USER ADMIN_PASSWORD REALM ACCOUNTS ROLES ;
  keycloak_admin_payload_vars ;
  ACCOUNTS="$(keycloak_accounts_json "${REALM}")" ;
  ROLES="$(keycloak_account_roles)" ;
  keycloak_site "roles accounts" ADMIN_USER ADMIN_PASSWORD REALM ACCOUNTS ROLES ;
  local status=$? ;
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# Delete the default accounts from the realm (never the admin of the master realm).
function cancel_keycloak_users() {
  keycloak_enter_project || return 1 ;
  local user user_name names="" ;
  for user in "${users[@]}" ; do
    user_name="user_${user}_name";
    names="${names}${!user_name}"$'\n' ;
    echo " ---------------------------------------------------------------- ";
    echo "      User name: ${!user_name}";
    echo " ================================================================= ";
  done
  local ADMIN_USER ADMIN_PASSWORD REALM USERNAMES="${names}" ;
  keycloak_admin_payload_vars ;
  keycloak_site cancel ADMIN_USER ADMIN_PASSWORD REALM USERNAMES ;
  local status=$? ;
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# What cmd-tools-keycloak-admin.sh does: the first of --kcadm, --restart, --add-users, --cancel-users that was
# asked for; with none of them, what the server is.
function keycloak_admin_tool() {
  trim_project_name ;
  keycloak_enter_project || exit 1 ;

  if ! ddev describe -j 2>/dev/null | grep -q '"status":"running"' ; then
    ddev start -y < /dev/null || exit 1 ;
  fi
  keycloak_wait > /dev/null || { echo "The sign-in server of ${PROJECT_NAME} does not answer; start it again with --restart." ; exit 1 ; } ;

  local ADMIN_USER ADMIN_PASSWORD REALM ;
  keycloak_admin_payload_vars ;
  if [ ! "${KCADM}" == '_none_' ] ; then
    local KCADM_ARGS="${KCADM}" ;
    keycloak_site kcadm ADMIN_USER ADMIN_PASSWORD REALM KCADM_ARGS ;
    exit $? ;
  fi

  if [ "${RESTART}" == 'yes' ] ; then
    docker restart "ddev-${PROJECT_NAME}-keycloak" > /dev/null || exit 1 ;
    keycloak_wait || exit 1 ;
    echo "Keycloak $(keycloak_version) is running at https://${PROJECT_NAME}.ddev.site/auth" ;
  elif [ "${ADD_USERS}" == 'yes' ] ; then
    set_keycloak_users ;
    add_keycloak_users ;
  elif [ "${CANCEL_USERS}" == 'yes' ] ; then
    set_keycloak_users ;
    cancel_keycloak_users ;
  else
    echo "${doc_name}/${PROJECT_NAME}: Keycloak $(keycloak_version), realm ${REALM}" ;
    echo "  the test app: https://${PROJECT_NAME}.ddev.site" ;
    echo "  the server:   https://${PROJECT_NAME}.ddev.site/auth (admin console: /auth/admin/${REALM}/console/)" ;
    echo "  its mail:     https://${PROJECT_NAME}.ddev.site:8026" ;
    echo "" ;
    set_keycloak_users ;
    local user user_name USERNAMES="" ;
    for user in "${users[@]}" ; do user_name="user_${user}_name"; USERNAMES="${USERNAMES}${!user_name}"$'\n' ; done
    echo "Accounts:" ;
    keycloak_site "list realm" ADMIN_USER ADMIN_PASSWORD REALM USERNAMES ;
  fi
  cd ${WORKSPACE_ROOT}/${doc_name};
}

# The step pack in the testing stack of a Keycloak site. The core's testing_configure calls this in the
# project folder once webship-js is scaffolded and before the dependencies are installed; for a project that
# is not one of this plugin's it changes nothing.
#
# It adds the pack to package.json, lists its step definitions in cucumber.js after webship-js's own, gives
# cucumber.js the tags that keep the pack's assertions that must fail out of a normal run, the sign-in
# server (the site's /auth and its realm), how the test app starts a sign-in, the mail catcher, the handle
# the test-data steps work as (dataAdmin), and the users registry of the default accounts (a handle a scenario
# reads, mapped to an account; otpuser with the key of its one-time code; never the workspace account), and
# writes a first feature when the project has none of its own. Every part is skipped when it is already there,
# so a second run adds what the first missed and never resets a suite.
function testing_configure_keycloak() {
  local project_path="$1";
  keycloak_is_project "${project_path}" || return 0 ;
  if [ ! -f "${project_path}/cucumber.js" ] || [ ! -f "${project_path}/package.json" ] ; then
    echo "  Keycloak: cucumber.js is not here yet — run the testing setup again once webship-js is scaffolded." ;
    return 1 ;
  fi

  echo "Adding the Keycloak step pack (${KEYCLOAK_STEPS_PACKAGE} ${KEYCLOAK_STEPS_VERSION}).";
  set_keycloak_users ;
  local registry="" user user_name user_mail user_password user_role otp ;
  for user in "${users[@]}" ; do
    user_name="user_${user}_name"; user_mail="user_${user}_mail"; user_password="user_${user}_password"; user_role="user_${user}_role";
    otp="" ; [ "${!user_role}" == 'otp' ] && otp="${KEYCLOAK_OTP_KEY}" ;
    registry="${registry}${user}|${!user_name}|${!user_mail}|${!user_password}|${otp}"$'\n' ;
  done

  local site_name realm ;
  site_name="$(sed -n 's/^name:[[:space:]]*"\{0,1\}\([A-Za-z0-9._-]*\)"\{0,1\}[[:space:]]*$/\1/p' "${project_path}/.ddev/config.yaml" | head -n 1)" ;
  realm="$(keycloak_setting KEYCLOAK_REALM "${project_path}")" ;

  python3 - "${project_path}" "${KEYCLOAK_STEPS_PACKAGE}" "${KEYCLOAK_STEPS_VERSION}" 'KEYCLOAK' "${registry}" "https://${site_name:-${PROJECT_NAME}}.ddev.site" "${realm:-webship}" <<'PYEOF' || return 1
import json, re, sys

project, pack, version, prefix, registry, address, realm = sys.argv[1:8]

# package.json: the pack as a dev dependency, at the release line this plugin was proven on.
pkg_file = project + '/package.json'
pkg = json.load(open(pkg_file))
if pack not in pkg.get('dependencies', {}) and pack not in pkg.get('devDependencies', {}):
    pkg.setdefault('devDependencies', {})[pack] = version
    open(pkg_file, 'w').write(json.dumps(pkg, indent=4) + '\n')
    print('  package.json: %s %s' % (pack, version))

cucumber_file = project + '/cucumber.js'
src = open(cucumber_file).read()
before = src

if ('node_modules/%s/' % pack) not in src:
    line = "'node_modules/%s/tests/step-definitions/**/*.js'," % pack
    core = re.search(r"^([ \t]*)'node_modules/webship-js/tests/step-definitions/[^']*',.*$", src, re.M)
    opening = re.search(r"^([ \t]*)require:[ \t]*\[[ \t]*$", src, re.M)
    if core:
        src = src[:core.end()] + '\n' + core.group(1) + line + src[core.end():]
    elif opening:
        src = src[:opening.end()] + '\n' + opening.group(1) + '  ' + line + src[opening.end():]
    else:
        sys.exit("  cucumber.js has no require list this can add to. Add this line to it:\n    " + line)
    print('  cucumber.js: the step definitions of %s' % pack)

if not re.search(r"^[ \t]*tags:", src, re.M):
    default = re.search(r"^([ \t]*)default:[ \t]*\{[ \t]*$", src, re.M)
    if default:
        pad = default.group(1) + '  '
        block = [
            pad + "// The pack's assertions that must fail are no part of a normal run.",
            pad + "tags: process.env.CUCUMBER_TAGS || 'not @wip and not @must-fail',",
        ]
        src = src[:default.end()] + '\n' + '\n'.join(block) + src[default.end():]
        print('  cucumber.js: the tags that keep the assertions that must fail out of a normal run')

world = re.search(r"^([ \t]*)worldParameters:[ \t]*\{[ \t]*$", src, re.M)
if not world:
    sys.exit("  cucumber.js has no worldParameters block to add the users registry to.")
pad = world.group(1) + '  '
additions = []
base = "(process.env.LAUNCH_URL || '%s').replace(/\\/+$/, '')" % address
if not re.search(r"^[ \t]*signInServer:", src, re.M):
    additions += [
        pad + "// The sign-in server of the site (under /auth) and its realm; the test app at the root signs in through it.",
        pad + "signInServer: { url: process.env.SIGN_IN_SERVER || `${%s}/auth`, realm: process.env.SIGN_IN_REALM || '%s' }," % (base, realm),
        pad + "appSignIn: { path: '/', button: 'Sign in' },",
    ]
if not re.search(r"^[ \t]*mailUrl:", src, re.M):
    additions += [
        pad + "// The project's mail catcher, which the server sends its mail to.",
        pad + "mailUrl: process.env.MAIL_URL || `${%s}:8026`," % base,
    ]
if not re.search(r"^[ \t]*dataAdmin:", src, re.M):
    additions += [
        pad + "// The account the test-data steps and the clean-up work as, through the admin REST API: the realm's admin of `users`.",
        pad + "dataAdmin: process.env.DATA_ADMIN || 'administrator',",
    ]
if not re.search(r"^[ \t]*javascript:", src, re.M):
    additions += [
        pad + "// Browser messages that are no error of the site: a request lost when the network of the machine changed.",
        pad + "javascript: { mode: process.env.WEBSHIP_JS_ERROR_MODE || 'warn', levels: ['error'], ignore: 'net::ERR_NETWORK_CHANGED', beforeScenario: false, afterScenario: true },",
    ]
if not re.search(r"^[ \t]*users:[ \t]*\{", src, re.M):
    rows = [r.split('|') for r in registry.splitlines() if r.strip()]
    additions += [
        pad + "// The users registry: a handle a scenario reads, mapped to an account of the realm (the default accounts:",
        pad + "// cmd-tools-keycloak-admin.sh --add-users); otpSecret is the key of an account's one-time code, in base32.",
        pad + "// Override one with %s_<HANDLE>_USERNAME and %s_<HANDLE>_PASSWORD." % (prefix, prefix),
        pad + "users: {",
    ]
    for handle, username, email, password, otp in rows:
        env = '%s_%s' % (prefix, handle.upper())
        extra = ", otpSecret: '%s'" % otp if otp else ''
        additions.append(pad + "  %s: { username: process.env.%s_USERNAME || '%s', email: '%s', password: process.env.%s_PASSWORD || '%s'%s }," % (handle, env, username, email, env, password, extra))
    additions.append(pad + "},")
    print('  cucumber.js: the users registry (%s)' % ', '.join(r[0] for r in rows))
if additions:
    src = src[:world.end()] + '\n' + '\n'.join(additions) + src[world.end():]
    print('  cucumber.js: the sign-in server, the mail catcher and the data administrator')

# The address the suite opens when LAUNCH_URL is not set: the placeholder of the scaffold becomes the app's.
placeholder = "process.env.LAUNCH_URL || 'http://localhost:8080'"
if placeholder in src:
    src = src.replace(placeholder, "process.env.LAUNCH_URL || '%s'" % address)
    print('  cucumber.js: the address of the app (%s)' % address)

if src != before:
    open(cucumber_file, 'w').write(src)
PYEOF

  # A first feature, when the project has none for the site yet.
  local feature="${WORKSPACE_SCRIPTS}/plugins/keycloak/site.feature" ;
  if [ -f "${feature}" ] && [ ! -f "${project_path}/tests/features/site.feature" ] ; then
    mkdir -p "${project_path}/tests/features" && cp "${feature}" "${project_path}/tests/features/site.feature" \
      && echo "  tests/features/site.feature: a first feature for the sign-in" ;
  fi

  # The scenarios log in as the default accounts: make sure a site that has its realm has them, once the server
  # answers again (installing the webship-js add-on restarts the project, and the server with it).
  if [ -n "${realm}" ] && ( cd "${project_path}" && keycloak_wait > /dev/null 2>&1 && add_keycloak_users > /dev/null 2>&1 ) ; then
    echo "  the default accounts are in the realm ${realm} (${users[*]})" ;
  elif [ -n "${realm}" ] ; then
    echo "  The default accounts could not be written: is the server running (ddev start in ${project_path})?" ;
  fi
}
