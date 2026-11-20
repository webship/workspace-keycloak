import test from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { spawnSync } from 'child_process';

// Compiled, these tests run from dist/tests, so the package root is one folder further up.
const PKG = fs.existsSync(path.join(__dirname, '..', 'package.json')) ? path.join(__dirname, '..') : path.join(__dirname, '..', '..');
const FUNCTIONS = path.join(PKG, 'scripts', 'functions', 'fun-keycloak.sh');

// The cucumber.js webship-js scaffolds, as far as the testing hook reads it.
const SCAFFOLD = `module.exports = {
  default: {
    requireModule: ['tsx/cjs'],
    require: [
      'node_modules/webship-js/tests/step-definitions/**/*.js',          // Webship-js core step definitions.
      'tests/step-definitions/**/*.js',                                  // Your custom step definitions.
    ],
    paths: ['tests/features/**/*.feature'],
    worldParameters: {
      launchUrl: process.env.LAUNCH_URL || 'http://localhost:8080',
    },
  },
};
`;

/**
 * A project folder with the testing stack scaffolded, and the tooling folder the installer would have filled.
 * A site of this plugin has the builder's .ddev/config.keycloak.yaml.
 */
function project(kind: 'keycloak' | 'drupal') {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'keycloak-plugin-'));
  const dir = path.join(root, 'dev', 'site1');
  fs.mkdirSync(path.join(dir, '.ddev'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.ddev', 'config.yaml'), `name: site1\ntype: ${kind === 'keycloak' ? 'generic' : 'drupal11'}\n`);
  if (kind === 'keycloak') fs.writeFileSync(path.join(dir, '.ddev', 'config.keycloak.yaml'), 'web_environment:\n  - KEYCLOAK_VERSION=26.8.2\n  - KEYCLOAK_REALM=webship\n');
  fs.writeFileSync(path.join(dir, 'cucumber.js'), SCAFFOLD);
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'site1', devDependencies: { 'webship-js': '^2.0.6' } }, null, 2));
  const scripts = path.join(root, 'core', 'scripts');
  const plugin = path.join(scripts, 'plugins', 'keycloak');
  fs.mkdirSync(plugin, { recursive: true });
  for (const f of ['testing/site.feature', 'scripts/keycloak-site.sh', 'scripts/keycloak-realm.json', 'scripts/app/keycloak-app.html', 'scripts/app/keycloak-app.js', 'scripts/app/keycloak-app.css', 'scripts/app/keycloak-silent-check-sso.html', 'scripts/app/keycloak-app-package.json']) {
    fs.copyFileSync(path.join(PKG, f), path.join(plugin, path.basename(f)));
  }
  return { root, dir, scripts };
}

/**
 * Run bash with the plugin's functions sourced and `ddev` replaced by a recorder of its calls and of what it reads
 * on stdin: the first line whole (`stdin1:`), then the start of the rest (`stdin:`).
 */
function bash(script: string, env: Record<string, string> = {}) {
  const fake = 'ddev() { echo "ddev $*" >> "${DDEV_LOG:-/dev/null}" ; if [ ! -t 0 ] ; then IFS= read -r first ; echo "  stdin1: ${first}" >> "${DDEV_LOG:-/dev/null}" ; head -c 120 | sed "s/^/  stdin: /" >> "${DDEV_LOG:-/dev/null}" ; echo >> "${DDEV_LOG:-/dev/null}" ; fi ; return 0 ; }';
  return spawnSync('bash', ['-c', `${fake}\nsource ${FUNCTIONS}\n${script}`], { encoding: 'utf8', env: { ...process.env, ...env } });
}

/** The payload a recorded call of keycloak-site.sh carried: on the first line of its standard input, never on its command line. */
function payloadOf(recorded: string, verbs: string) {
  const lines = recorded.split('\n');
  const call = lines.findIndex((l) => l === `ddev exec -s keycloak SITE_VERBS='${verbs}' bash -s`);
  assert.ok(call >= 0, `a call of the site script with the verbs "${verbs}": ${recorded}`);
  const m = (lines[call + 1] || '').match(/^  stdin1: SITE_PAYLOAD='([A-Za-z0-9+/=]+)'$/);
  assert.ok(m, `the first line of its input carries the payload: ${lines[call + 1]}`);
  const out: Record<string, string> = {};
  for (const line of Buffer.from(m![1], 'base64').toString('utf8').split('\n').filter(Boolean)) {
    const at = line.indexOf('=');
    out[line.slice(0, at)] = Buffer.from(line.slice(at + 1), 'base64').toString('utf8');
  }
  return out;
}

const OWNER = { account_name: 'owner1', account_mail: 'owner1@example.com', account_pass: 'Owner-pass-1234' };

test('the default accounts are the realm\'s admin, an editor, a user and a user with a one-time code, with example addresses', () => {
  const r = bash('set_keycloak_users ; for u in "${users[@]}" ; do n="user_${u}_name" ; m="user_${u}_mail" ; p="user_${u}_password" ; g="user_${u}_role" ; echo "${!n}|${!m}|${!p}|${!g}" ; done');
  assert.strictEqual(r.status, 0, r.stderr);
  const rows = r.stdout.trim().split('\n').map((l) => l.split('|'));
  assert.deepStrictEqual(rows.map((x) => x[0]), ['administrator', 'editor', 'user', 'otpuser']);
  assert.deepStrictEqual(rows.map((x) => x[3]), ['realm-admin', 'editor', 'user', 'otp']);
  for (const [name, mail, password] of rows) {
    assert.strictEqual(mail, `${name}@example.com`);
    assert.ok(password.length >= 10, 'a password every common password rule accepts');
  }
});

test('the accounts are written by the site script with the server\'s admin CLI, as the workspace account, never in a file', () => {
  const p = project('keycloak');
  const log = path.join(p.root, 'ddev.log');
  const r = bash('set_keycloak_users ; add_keycloak_users', { WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', PROJECT_NAME: 'site1', DDEV_LOG: log, ...OWNER });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const recorded = fs.readFileSync(log, 'utf8');
  assert.match(recorded, /stdin: # The site script of the sign-in server/, 'the script goes in on stdin');
  assert.doesNotMatch(recorded.split('\n').filter((l) => l.startsWith('ddev ')).join('\n'), /Owner-pass|dD\./, 'no password on a command line');
  const payload = payloadOf(recorded, 'roles accounts');
  assert.strictEqual(payload.ADMIN_USER, 'owner1', 'the workspace account logs the admin CLI in');
  assert.strictEqual(payload.ADMIN_PASSWORD, 'Owner-pass-1234');
  assert.strictEqual(payload.REALM, 'webship', 'the realm of the site\'s settings');
  assert.strictEqual(payload.ROLES.trim(), 'editor', 'the realm roles the accounts are given');
  const accounts = JSON.parse(payload.ACCOUNTS);
  assert.strictEqual(accounts.ifResourceExists, 'OVERWRITE', 'an account that is there gets its state back');
  assert.deepStrictEqual(accounts.users.map((u: any) => [u.username, u.email, u.realmRoles.join(','), Object.keys(u.clientRoles || {}).join(','), u.credentials.map((c: any) => c.type).join(',')]), [
    ['administrator', 'administrator@example.com', 'default-roles-webship', 'realm-management', 'password'],
    ['editor', 'editor@example.com', 'default-roles-webship,editor', '', 'password'],
    ['user', 'user@example.com', 'default-roles-webship', '', 'password'],
    ['otpuser', 'otpuser@example.com', 'default-roles-webship', '', 'password,otp'],
  ]);
  const otp = accounts.users[3].credentials[1];
  assert.strictEqual(JSON.parse(otp.secretData).value, 'webshiptestotpsecret', 'the secret whose base32 key the users registry carries');
  assert.deepStrictEqual(JSON.parse(otp.credentialData), { subType: 'totp', digits: 6, counter: 0, period: 30, algorithm: 'HmacSHA1' });
  assert.deepStrictEqual(fs.readdirSync(p.dir).filter((f) => !['.ddev', 'cucumber.js', 'package.json'].includes(f)), [], 'no file with a password is left in the project');
});

test('the key of the one-time code in the users registry is the base32 form of the secret the accounts are given', () => {
  const src = fs.readFileSync(FUNCTIONS, 'utf8');
  const secret = (src.match(/KEYCLOAK_OTP_SECRET='([^']+)'/) || [])[1] as string;
  const key = (src.match(/KEYCLOAK_OTP_KEY='([^']+)'/) || [])[1] as string;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = '';
  for (const byte of Buffer.from(secret, 'utf8')) bits += byte.toString(2).padStart(8, '0');
  let base32 = '';
  for (let i = 0; i < bits.length; i += 5) base32 += alphabet[parseInt(bits.slice(i, i + 5).padEnd(5, '0'), 2)];
  assert.strictEqual(base32, key);
});

test('cancelling the accounts deletes the default ones through the site script', () => {
  const p = project('keycloak');
  const log = path.join(p.root, 'ddev.log');
  const r = bash('set_keycloak_users ; cancel_keycloak_users', { WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', PROJECT_NAME: 'site1', DDEV_LOG: log, ...OWNER });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const payload = payloadOf(fs.readFileSync(log, 'utf8'), 'cancel');
  assert.deepStrictEqual(payload.USERNAMES.trim().split('\n'), ['administrator', 'editor', 'user', 'otpuser']);
  assert.strictEqual(payload.REALM, 'webship');
});

test('the builder refuses a release it does not know, a bad name, a realm file it cannot read, and the options that need --install, before it changes anything', () => {
  const p = project('keycloak');
  const log = path.join(p.root, 'ddev.log');
  const base = { WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', DDEV_LOG: log, ...OWNER };
  const stub = 'trim_project_name() { :; } ; drop_database() { echo dropped ; } ;';
  const cases: Array<[string, RegExp]> = [
    [`PROJECT_NAME=site1 ; KEYCLOAK_VERSION="beta" ;`, /--keycloak-version takes a release \(26\.8\.2\), latest or nightly, not beta\. Nothing was changed\./],
    [`PROJECT_NAME=site1 ; ADD_USERS=yes ; INSTALL=no ;`, /--add-users needs --install/],
    [`PROJECT_NAME=site1 ; REALM_FILE=/etc/hostname ; INSTALL=no ;`, /--realm needs --install/],
    [`PROJECT_NAME=site1 ; REALM_FILE=/etc/hostname ; INSTALL=yes ;`, /--realm takes a realm file \(JSON with a "realm" name\), not \/etc\/hostname/],
    [`PROJECT_NAME=Site_1 ;`, /must be small letters, digits and dashes/],
    [`PROJECT_NAME=site1 ; INSTALL=yes ; account_pass="" ;`, /The workspace account's password is not set/],
  ];
  for (const [vars, message] of cases) {
    const r = bash(`${vars} ${stub} keycloak_build`, base);
    assert.strictEqual(r.status, 1, `${vars}: ${r.stdout}`);
    assert.match(r.stdout, message);
    assert.doesNotMatch(r.stdout, /dropped/, 'nothing was deleted');
  }
  for (const ok of ['26.8.2', '26.7', 'latest', 'nightly']) {
    const r = bash(`PROJECT_NAME=site1 ; KEYCLOAK_VERSION="${ok}" ; ADD_USERS=yes ; INSTALL=no ; ${stub} keycloak_build`, base);
    assert.doesNotMatch(r.stdout, /--keycloak-version takes/, `${ok} is a release the builder knows`);
  }
  assert.ok(!fs.existsSync(log), 'the container tool was never called');
});

test('the builder writes the server\'s service, the web server\'s /auth/ and the site\'s settings: the volume is the project\'s', () => {
  const p = project('keycloak');
  const boot = '      - KC_BOOTSTRAP_ADMIN_USERNAME=first-start-admin\n      - KC_BOOTSTRAP_ADMIN_PASSWORD=abc\n';
  const r = bash(`keycloak_write_config ${p.dir} site1 26.8.2 "${boot}" webship`);
  assert.strictEqual(r.status, 0, r.stderr);
  const compose = fs.readFileSync(path.join(p.dir, '.ddev', 'docker-compose.keycloak.yaml'), 'utf8');
  assert.match(compose, /image: quay\.io\/keycloak\/keycloak:26\.8\.2/);
  assert.match(compose, /KC_HOSTNAME=https:\/\/site1\.ddev\.site\/auth/);
  assert.match(compose, /APP_URL=https:\/\/site1\.ddev\.site/);
  assert.match(compose, /KC_BOOTSTRAP_ADMIN_USERNAME=first-start-admin/);
  assert.match(compose, /name: ddev-\$\{DDEV_SITENAME\}-keycloak-data/);
  assert.doesNotMatch(compose, /HTTPS?_EXPOSE/, 'no port of the router: the web server sends /auth/ to the server');
  const nginx = fs.readFileSync(path.join(p.dir, '.ddev', 'nginx', 'keycloak.conf'), 'utf8');
  assert.match(nginx, /location \^~ \/auth\/ \{\n\s+proxy_pass http:\/\/keycloak:8080;/);
  assert.match(fs.readFileSync(path.join(p.dir, '.ddev', 'config.keycloak.yaml'), 'utf8'), /KEYCLOAK_REALM=webship/);
  // Once the workspace account is the admin, the temporary admin leaves the project's files.
  const again = bash(`keycloak_write_config ${p.dir} site1 26.8.2 "" webship`);
  assert.strictEqual(again.status, 0, again.stderr);
  assert.doesNotMatch(fs.readFileSync(path.join(p.dir, '.ddev', 'docker-compose.keycloak.yaml'), 'utf8'), /KC_BOOTSTRAP_ADMIN/);
});

test('the builder writes the test app: the page as the client webship-app, the same page at /partner/ as webship-partner, and its configuration', () => {
  const p = project('keycloak');
  const r = bash(`keycloak_write_app ${p.dir} site1 webship`, { WORKSPACE_SCRIPTS: p.scripts });
  assert.strictEqual(r.status, 0, r.stderr);
  const app = path.join(p.dir, 'app');
  assert.match(fs.readFileSync(path.join(app, 'index.html'), 'utf8'), /data-client="webship-app"/);
  const partner = fs.readFileSync(path.join(app, 'partner', 'index.html'), 'utf8');
  assert.match(partner, /data-client="webship-partner" data-app-name="Webship partner app"/);
  assert.match(partner, /<h1>Webship partner app<\/h1>/);
  for (const f of ['app.js', 'app.css', 'silent-check-sso.html', 'partner/silent-check-sso.html', 'package.json']) assert.ok(fs.existsSync(path.join(app, f)), `app/${f}`);
  assert.deepStrictEqual(JSON.parse(fs.readFileSync(path.join(app, 'config.json'), 'utf8')), { url: 'https://site1.ddev.site/auth', realm: 'webship' });
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(app, 'package.json'), 'utf8')).dependencies['keycloak-js'], '26.2.5', 'the official adapter, at the release the builder names');
});

test('the testing hook adds the step pack, the sign-in server, the mail catcher, the users registry, the data admin, the tags and a first feature, once', () => {
  const p = project('keycloak');
  const log = path.join(p.root, 'ddev.log');
  // The server answers at once here: the wait for it is the recorder's.
  const run = () => bash(`keycloak_wait() { echo "ddev wait" >> "${log}" ; } ; cd ${p.dir} && testing_configure_keycloak ${p.dir}`, { WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', PROJECT_NAME: 'site1', DDEV_LOG: log, ...OWNER });
  const r = run();
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const pkg = JSON.parse(fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8'));
  assert.strictEqual(pkg.devDependencies['@webship-js/keycloak-steps'], '^2.0.0');
  assert.strictEqual(pkg.devDependencies['webship-js'], '^2.0.6', 'what was there stays');
  const cucumber = fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8');
  const lines = cucumber.split('\n');
  const core = lines.findIndex((l) => l.includes('node_modules/webship-js/tests/step-definitions'));
  assert.strictEqual(lines[core + 1], "      'node_modules/@webship-js/keycloak-steps/tests/step-definitions/**/*.js',", 'the pack is listed right after webship-js');
  assert.match(cucumber, /otpuser: \{ username: process\.env\.KEYCLOAK_OTPUSER_USERNAME \|\| 'otpuser', email: 'otpuser@example\.com', password: process\.env\.KEYCLOAK_OTPUSER_PASSWORD \|\| '[^']+', otpSecret: 'O5SWE43INFYHIZLTORXXI4DTMVRXEZLU' \},/);
  assert.match(cucumber, /dataAdmin: process\.env\.DATA_ADMIN \|\| 'administrator',/);
  assert.match(cucumber, /tags: process\.env\.CUCUMBER_TAGS \|\| 'not @wip and not @must-fail',/);
  assert.match(cucumber, /launchUrl: process\.env\.LAUNCH_URL \|\| 'https:\/\/site1\.ddev\.site',/);
  // Still a module node can load, with the registry and the server where the pack reads them.
  const loaded = spawnSync(process.execPath, ['-e', `const c = require(${JSON.stringify(path.join(p.dir, 'cucumber.js'))}).default; const w = c.worldParameters; console.log(JSON.stringify([c.require.length, Object.keys(w.users), c.tags, w.dataAdmin, w.signInServer, w.appSignIn, w.mailUrl, w.javascript.mode]))`], { encoding: 'utf8', env: { ...process.env, CUCUMBER_TAGS: '', LAUNCH_URL: '' } });
  assert.strictEqual(loaded.status, 0, loaded.stderr);
  const [requires, handles, tags, admin, server, signIn, mail, mode] = JSON.parse(loaded.stdout);
  assert.strictEqual(requires, 3);
  assert.deepStrictEqual(handles, ['administrator', 'editor', 'user', 'otpuser']);
  assert.match(tags, /not @must-fail/);
  assert.strictEqual(admin, 'administrator');
  assert.deepStrictEqual(server, { url: 'https://site1.ddev.site/auth', realm: 'webship' });
  assert.deepStrictEqual(signIn, { path: '/', button: 'Sign in' });
  assert.strictEqual(mail, 'https://site1.ddev.site:8026');
  assert.strictEqual(mode, 'warn');
  assert.ok(fs.existsSync(path.join(p.dir, 'tests', 'features', 'site.feature')));
  assert.match(fs.readFileSync(log, 'utf8'), /^ddev wait\n[\s\S]*SITE_VERBS='roles accounts' bash -s$/m, 'the realm gets the default accounts, once the server answers');
  // Again, after a person changed the feature: nothing is doubled, nothing is reset.
  fs.writeFileSync(path.join(p.dir, 'tests', 'features', 'site.feature'), 'Feature: mine\n');
  assert.strictEqual(run().status, 0);
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8'), cucumber);
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'tests', 'features', 'site.feature'), 'utf8'), 'Feature: mine\n');
});

test('the testing hook leaves a project of another platform alone', () => {
  const p = project('drupal');
  const r = bash(`cd ${p.dir} && testing_configure_keycloak ${p.dir}`, { WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', PROJECT_NAME: 'site1' });
  assert.strictEqual(r.status, 0);
  assert.strictEqual(r.stdout, '');
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8'), SCAFFOLD);
  assert.ok(!fs.existsSync(path.join(p.dir, 'tests')));
});

test('the admin tool refuses a project that is not a site of the plugin', () => {
  const p = project('drupal');
  const r = bash('PROJECT_NAME=site1 ; KCADM="get realms" ; trim_project_name() { :; } ; keycloak_admin_tool', { WORKSPACE_ROOT: p.root, doc_name: 'dev' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stdout, /is not a Keycloak project of this plugin/);
});

test('the admin tool runs a command of the admin CLI in the server\'s container, as the workspace account', () => {
  const p = project('keycloak');
  const log = path.join(p.root, 'ddev.log');
  const fake = `ddev() { case "$*" in describe*) echo '{"raw":{"status":"running"}}' ;; *) echo "ddev $*" >> "${log}" ; if [ ! -t 0 ] ; then IFS= read -r first ; echo "  stdin1: \${first}" >> "${log}" ; cat > /dev/null ; fi ;; esac ; return 0 ; }`;
  const r = spawnSync('bash', ['-c', `source ${FUNCTIONS}\n${fake}\nkeycloak_wait() { :; } ; PROJECT_NAME=site1 ; KCADM="get users -r webship --fields username" ; trim_project_name() { :; } ; keycloak_admin_tool`], { encoding: 'utf8', env: { ...process.env, WORKSPACE_ROOT: p.root, WORKSPACE_SCRIPTS: p.scripts, doc_name: 'dev', ...OWNER } });
  assert.strictEqual(r.status, 0, r.stdout + r.stderr);
  const payload = payloadOf(fs.readFileSync(log, 'utf8'), 'kcadm');
  assert.strictEqual(payload.KCADM_ARGS, 'get users -r webship --fields username');
  assert.strictEqual(payload.ADMIN_USER, 'owner1');
});

test('the first feature names no platform in a step, and no password', () => {
  const feature = fs.readFileSync(path.join(PKG, 'testing', 'site.feature'), 'utf8');
  const steps = feature.split('\n').filter((l) => /^\s*(Given|When|Then|And|But) /.test(l));
  assert.ok(steps.length >= 10);
  for (const s of steps) assert.doesNotMatch(s, /keycloak/i, s);
  assert.doesNotMatch(feature, /dD\.123123ddd|O5SWE43/);
  assert.doesNotMatch(feature, /try to register|Create your account/i, 'a first feature makes no account');
});
