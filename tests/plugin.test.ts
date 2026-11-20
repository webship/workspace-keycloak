import test from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import path from 'path';
import { spawnSync } from 'child_process';

import { register, assistantContext, PLATFORM, COMMANDS, AGENTS } from '../src/index';

// Compiled, these tests run from dist/tests, so the package root is one folder further up.
const PKG = fs.existsSync(path.join(__dirname, '..', 'package.json')) ? path.join(__dirname, '..') : path.join(__dirname, '..', '..');
const read = (f: string) => fs.readFileSync(path.join(PKG, f), 'utf8');
const manifest = JSON.parse(read('package.json')).workspacePlugin;

test('the manifest names the platform, and every file it names ships', () => {
  assert.strictEqual(manifest.name, PLATFORM);
  const named = [...manifest.commands.files, ...manifest.scripts.functions, ...manifest.scripts.args, ...manifest.scripts.machine,
    ...manifest.ai.agents, ...manifest.ai.skills, ...manifest.ai.commands, ...manifest.ai.prompts, ...manifest.features];
  for (const f of named) assert.ok(fs.existsSync(path.join(PKG, f)), `${f} is in the package`);
  assert.deepStrictEqual(manifest.commands.files.map((f: string) => path.basename(f)), COMMANDS);
  assert.deepStrictEqual(manifest.ai.agents.map((f: string) => path.basename(f, '.md')), AGENTS);
  assert.deepStrictEqual(manifest.commands.types, ['sites'], 'the commands go to sites folders only');
  const files: string[] = JSON.parse(read('package.json')).files;
  for (const f of named) assert.ok(files.includes(f.split('/')[0]), `${f} is published with the package`);
  // The machine files land side by side in core/scripts/plugins/keycloak/: no two may share a name.
  const names = manifest.scripts.machine.map((f: string) => path.basename(f));
  assert.strictEqual(new Set(names).size, names.length, 'the machine files have names of their own');
});

test('every command finds the workspace by itself, names its folder, and sources its args from where the installer puts them', () => {
  for (const f of manifest.commands.files) {
    const src = read(f);
    assert.match(src, /^#!\/usr\/bin\/env bash/, `${f} is a bash script`);
    assert.match(src, /WORKSPACE_SCRIPTS="\$\{WORKSPACE_SCRIPTS:-\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)\/\.\.\/core\/scripts" && pwd\)\}"/, `${f} locates the tooling from its own path`);
    assert.match(src, /workspace\.__WORKSPACE__\.settings\.yml/, `${f} loads the settings of the folder it is installed into`);
    assert.match(src, /source \$\{WORKSPACE_SCRIPTS\}\/plugins\/keycloak\/args\/arg-[a-z-]+\.sh \|\| exit 1 ;/, `${f} reads its arguments from the plugin's args`);
    const last = src.trim().split('\n').pop() as string;
    assert.match(read('scripts/functions/fun-keycloak.sh'), new RegExp(`^function ${last.replace(/ ;$/, '')}\\(\\)`, 'm'), `${f} ends by calling a function the plugin defines`);
  }
  assert.match(read('commands/cmd-keycloak-project.sh'), /^# workspace-name: Keycloak/m, 'the builder carries the name the Build list shows');
  assert.doesNotMatch(read('commands/cmd-tools-keycloak-admin.sh'), /^# workspace-name:/m, 'a tool is not a builder');
});

test('every shell script parses', () => {
  for (const f of [...manifest.commands.files, ...manifest.scripts.functions, ...manifest.scripts.args, 'scripts/keycloak-site.sh']) {
    const r = spawnSync('bash', ['-n', path.join(PKG, f)], { encoding: 'utf8' });
    assert.strictEqual(r.status, 0, `${f}: ${r.stderr}`);
  }
});

test('the site script runs in the server\'s container with its admin CLI, with every verb the functions call', () => {
  const src = read('scripts/keycloak-site.sh');
  for (const verb of ['owner', 'roles', 'accounts', 'cancel', 'list', 'realm', 'kcadm']) assert.match(src, new RegExp(`^    ${verb}\\)$`, 'm'), `keycloak-site.sh has the verb ${verb}`);
  assert.match(src, /KCADM=\/opt\/keycloak\/bin\/kcadm\.sh/, 'the server\'s own admin CLI');
  assert.match(src, /KC_CLI_PASSWORD="\$password"/, 'the password reaches the admin CLI in its environment, never on a command line');
  assert.match(src, /SITE_PAYLOAD/, 'the payload comes on the first line of the input');
  assert.match(src, /P\["\$\{line%%=\*\}"\]/, 'each line of the payload is split by hand: read would drop a single trailing "="');
  const functions = read('scripts/functions/fun-keycloak.sh');
  for (const call of functions.matchAll(/keycloak_site "?([a-z ]+?)"? [A-Z_]/g)) {
    for (const word of call[1].split(' ')) assert.match(src, new RegExp(`^    ${word}\\)$`, 'm'), `fun-keycloak.sh calls the verb ${word}`);
  }
});

test('the test realm is the pack\'s: the clients of the test app, the role of the accounts, the mail to the catcher', () => {
  const realm = JSON.parse(read('scripts/keycloak-realm.json'));
  assert.strictEqual(realm.realm, 'webship');
  assert.deepStrictEqual(realm.clients.map((c: any) => c.clientId), ['webship-app', 'webship-partner']);
  assert.strictEqual(realm.clients[1].consentRequired, true, 'the partner app asks for consent');
  assert.ok(realm.clients.every((c: any) => c.publicClient && c.attributes['pkce.code.challenge.method'] === 'S256'), 'public clients with PKCE');
  assert.ok(realm.clients.every((c: any) => c.redirectUris.every((u: string) => u.startsWith('${APP_URL}'))), 'the redirects are the app\'s address, set at the import');
  assert.deepStrictEqual(realm.roles.realm.map((r: any) => r.name), ['editor']);
  assert.strictEqual(realm.smtpServer.host, '${SMTP_HOST:web}', 'the mail goes to the project\'s mail catcher');
  assert.strictEqual(realm.otpPolicyCodeReusable, false, 'a one-time code is taken once');
  assert.strictEqual(realm.loginTheme, undefined, 'the server\'s default login theme, unless the builder is asked for another');
});

test('the functions carry the names the core\'s tools look for, and run the server the official way', () => {
  const src = read('scripts/functions/fun-keycloak.sh');
  for (const fn of ['set_keycloak_users', 'add_keycloak_users', 'cancel_keycloak_users', 'testing_configure_keycloak', 'keycloak_build', 'keycloak_admin_tool']) {
    assert.match(src, new RegExp(`^function ${fn}\\(\\) \\{`, 'm'), `${fn} is defined`);
  }
  assert.match(src, /--project-type=generic --webserver-type=nginx-fpm --docroot=app/, 'a generic project whose web server serves the test app');
  assert.match(src, /--omit-containers=db/, 'the server keeps its own data');
  assert.match(src, /image: quay\.io\/keycloak\/keycloak:\$\{version\}/, 'the official image');
  assert.match(src, /command: \["start-dev", "--import-realm"\]/, 'development mode, with the realm imported at the first start');
  assert.match(src, /KC_HTTP_RELATIVE_PATH=\/auth/, 'the server under /auth');
  assert.match(src, /location \^~ \/auth\/ \{/, 'the web server sends /auth/ to the server, so the router needs no port of its own');
  assert.match(src, /name: ddev-\\\$\{DDEV_SITENAME\}-keycloak-data/, 'the data volume is the project\'s');
  assert.match(src, /--nodejs-version=\$\(ddev_nodejs_version\)/, 'the project carries the Node.js of the workspace rule');
  assert.match(src, /KC_BOOTSTRAP_ADMIN_USERNAME=\$\{temp_admin\}/, 'a temporary admin of the first start');
  assert.match(src, /keycloak_write_config "\$\{project_path\}" "\$\{PROJECT_NAME\}" "\$\{version\}" "" "\$\{realm\}"/, 'whose password leaves the project\'s files once the workspace account is the admin');
  assert.doesNotMatch(src, /ddev stop -y/, 'ddev stop takes no -y');
});

test('each agent is a definition the AI Agents folder can list: named after its file, described, on the fable model', () => {
  for (const f of manifest.ai.agents) {
    const src = read(f);
    const head = src.split('\n---\n')[0];
    assert.match(head, /^---\n/, `${f} opens with frontmatter`);
    assert.match(head, new RegExp(`^name: ${path.basename(f, '.md')}$`, 'm'));
    assert.match(head, /^description: .{80,}$/m, `${f} says when to use it`);
    assert.match(head, /^model: fable$/m);
    assert.match(head, /^tools:\n(  - \S+\n?)+/m);
    assert.match(src, /cmd-tools-testing\.sh|cmd-keycloak-project\.sh/, `${f} names the plugin's commands`);
  }
  const tester = read('ai/agents/keycloak-tester.md');
  assert.match(tester, /Never create or delete an account in a suite/);
  assert.match(tester, /No platform name in a step phrase/);
  assert.match(tester, /Playwright MCP browser first/);
});

test('register() adds the assistant context and nothing else', () => {
  const calls: string[] = [];
  const api: any = { name: 'keycloak', addAssistantContext: (fn: () => string) => calls.push(fn()) };
  register(api);
  assert.strictEqual(calls.length, 1);
  assert.strictEqual(calls[0], assistantContext());
  for (const c of COMMANDS) assert.ok(calls[0].includes(c), `the assistant is told about ${c}`);
  for (const a of AGENTS) assert.ok(calls[0].includes(a), `the assistant is told about ${a}`);
});

test('the docs say container-based, name only what ships, and carry no personal value', () => {
  const docs = ['README.md', ...manifest.ai.agents, 'scripts/functions/fun-keycloak.sh'];
  for (const f of docs) {
    const src = read(f);
    assert.doesNotMatch(src, /DDEV-only/i, `${f}: the workspace is container-based, DDEV by default`);
    assert.doesNotMatch(src, /\/home\/(?!YOUR_USER)[a-z]/, `${f} carries no personal path`);
    const mails = src.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[a-z]{2,}/g) || [];
    for (const m of mails) assert.match(m, /@example\.(com|org)$/, `${f}: ${m} is not an example address`);
  }
  for (const c of COMMANDS) assert.ok(read('README.md').includes(c), `the README lists ${c}`);
});
