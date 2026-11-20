# The site script of the sign-in server: run by bash in the server's container, with its own admin CLI
# (kcadm.sh), never on the host. The build of the test site and the Webship Workspace's builder both
# run it the same way:
#
#   { printf "SITE_PAYLOAD='%s'\n" "<base64 of the payload>"; cat keycloak-site.sh; } \
#     | ddev exec -s keycloak "SITE_VERBS='<verbs>' bash -s"
#
# The payload travels on the first line of the input, as base64 of lines of KEY=base64(value): no
# password is ever on a command line, in a file of the project, or in the output of a failed run.
#   ADMIN_USER, ADMIN_PASSWORD   the admin of the master realm this script logs in as
#   REALM                        the realm the accounts belong to
#   OWNER                        (owner) the partial import of the permanent admin of the master realm
#   OWNER_USER, OWNER_PASSWORD   (owner) its username and password
#   ACCOUNTS                     (accounts) the partial import of the accounts of REALM
#   ROLES                        (roles) the realm roles the accounts are given, one per line
#   USERNAMES                    (cancel, list) the usernames of the accounts, one per line
#   KCADM_ARGS                   (kcadm) the arguments of one admin CLI command, quoted as in a shell
#
# Verbs, in the order given (SITE_VERBS):
#   owner      make OWNER the permanent admin of the master realm, then delete the temporary admin the
#              server made at its first start (ADMIN_USER), and work as OWNER from then on
#   roles      make the realm roles of ROLES that REALM does not have yet (a realm file of one's own)
#   accounts   create the accounts of ACCOUNTS in REALM, or give an existing one back its email, names,
#              password, roles and one-time code (a partial import that overwrites them)
#   cancel     delete the accounts of USERNAMES from REALM (never an admin of the master realm)
#   list       print the accounts of USERNAMES in REALM: their email, roles and one-time code
#   realm      print the realm: its name, its clients and its roles
#   kcadm      run one admin CLI command (KCADM_ARGS), logged in, and print what it prints
set -uo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh
SERVER="http://localhost:8080${KC_HTTP_RELATIVE_PATH:-}"
SERVER="${SERVER%/}"
CONFIG="$(mktemp /tmp/kcadm.XXXXXX)"
trap 'rm -f "$CONFIG"' EXIT

# One KEY=base64 line per value; the line is split by hand (read would drop a single trailing "=").
declare -A P
while IFS= read -r line; do
  [ -z "$line" ] && continue
  P["${line%%=*}"]="$(printf '%s' "${line#*=}" | base64 -d)"
done < <(printf '%s' "${SITE_PAYLOAD:-}" | base64 -d)
value() { printf '%s' "${P[$1]:-}"; }

kc() { "$KCADM" "$@" --config "$CONFIG"; }

login() {
  local user="$1" password="$2"
  if ! KC_CLI_PASSWORD="$password" "$KCADM" config credentials --config "$CONFIG" --server "$SERVER" --realm master --user "$user" > /dev/null 2>&1; then
    echo "The admin \"$user\" of the master realm could not log in to $SERVER: is the server up, and is the password the one it was given?" >&2
    exit 1
  fi
}

# The id of an account of a realm, by its username, or nothing.
user_id() {
  kc get users -r "$1" -q username="$2" -q exact=true --fields id --format csv --noquotes 2> /dev/null | head -n 1
}

login "$(value ADMIN_USER)" "$(value ADMIN_PASSWORD)"
REALM="$(value REALM)"

for verb in ${SITE_VERBS:-}; do
  case "$verb" in
    owner)
      owner="$(value OWNER_USER)"
      if ! kc create partialImport -r master -f - <<< "$(value OWNER)" > /dev/null; then
        echo "The permanent admin \"$owner\" of the master realm could not be written." >&2
        exit 1
      fi
      login "$owner" "$(value OWNER_PASSWORD)"
      temporary="$(value ADMIN_USER)"
      if [ "$temporary" != "$owner" ]; then
        id="$(user_id master "$temporary")"
        [ -n "$id" ] && kc delete "users/$id" -r master > /dev/null && echo "The temporary admin of the first start is deleted."
      fi
      echo "\"$owner\" is the admin of the master realm."
      ;;
    roles)
      while read -r role; do
        [ -z "$role" ] && continue
        if ! kc get "roles/$role" -r "$REALM" > /dev/null 2>&1; then
          kc create roles -r "$REALM" -s "name=$role" > /dev/null && echo "  the realm role $role is made"
        fi
      done <<< "$(value ROLES)"
      ;;
    accounts)
      if ! kc create partialImport -r "$REALM" -f - <<< "$(value ACCOUNTS)" > /dev/null; then
        echo "The accounts could not be written into the realm $REALM." >&2
        exit 1
      fi
      echo "The accounts are in the realm $REALM."
      ;;
    cancel)
      while read -r username; do
        [ -z "$username" ] && continue
        id="$(user_id "$REALM" "$username")"
        if [ -n "$id" ]; then
          kc delete "users/$id" -r "$REALM" > /dev/null && echo "  deleted: $username"
        else
          echo "  not there: $username"
        fi
      done <<< "$(value USERNAMES)"
      ;;
    list)
      while read -r username; do
        [ -z "$username" ] && continue
        id="$(user_id "$REALM" "$username")"
        if [ -z "$id" ]; then
          printf '  %-16s (not there)\n' "$username"
          continue
        fi
        email="$(kc get "users/$id" -r "$REALM" --fields email --format csv --noquotes 2> /dev/null)"
        roles="$(kc get-roles -r "$REALM" --uid "$id" --effective --fields name --format csv --noquotes 2> /dev/null | grep -v -E '^(default-roles-.*|offline_access|uma_authorization)$' | paste -sd ' ' -)"
        admin="$(kc get-roles -r "$REALM" --uid "$id" --cclientid realm-management --fields name --format csv --noquotes 2> /dev/null | grep -x realm-admin)"
        [ -n "$admin" ] && roles="${roles:+$roles }realm-admin"
        otp="$(kc get "users/$id/credentials" -r "$REALM" 2> /dev/null | grep -c '"type" : "otp"')"
        printf '  %-16s %-32s roles: %s%s\n' "$username" "$email" "${roles:-none}" "$([ "${otp:-0}" -gt 0 ] && echo ', one-time code set up')"
      done <<< "$(value USERNAMES)"
      ;;
    realm)
      kc get "realms/$REALM" --fields realm,displayName,enabled,registrationAllowed,resetPasswordAllowed,rememberMe,loginTheme 2> /dev/null
      echo
      echo "Clients:"
      kc get clients -r "$REALM" --fields clientId --format csv --noquotes 2> /dev/null | sed 's/^/  /'
      echo "Realm roles:"
      kc get roles -r "$REALM" --fields name --format csv --noquotes 2> /dev/null | sed 's/^/  /'
      ;;
    kcadm)
      # The arguments as a shell splits them, quotes kept: what a person typed after --kcadm.
      eval "set -- $(value KCADM_ARGS)"
      kc "$@"
      status=$?
      if [ "$status" -ne 0 ]; then exit "$status"; fi
      ;;
    *)
      echo "keycloak-site.sh: no verb \"$verb\"." >&2
      exit 1
      ;;
  esac
done
