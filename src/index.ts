/**
 * Keycloak for Webship Workspace: a platform plugin.
 *
 * What the package carries is placed by the installer from the manifest: the builder and the server's admin
 * CLI tool in the sites folders, their functions and argparse under core/scripts/plugins/keycloak/ (with
 * keycloak-site.sh, which the builder runs with the server's own admin CLI, the test realm and the test app's
 * files), and its AI items (ai/ in this package) in the folder of their kind: the agents in AI Agents, the
 * skill in AI Skills, the command in AI Commands, the prompts in AI Prompts. The dashboard needs nothing drawn
 * for it: the builder is in the Build list because it is a cmd-*-project.sh, the row menus are the core's, the
 * AI items are listed like any other. What register() adds is what the assistant is told.
 *
 * Everything the dashboard is asked for goes through `api`; this package requires nothing from the dashboard's
 * own files, so it can be installed from npm and removed without a trace.
 */

import type { PluginApi } from '@webship.co/workspace-plugin-api';

/** The plugin's name. A Keycloak site is a generic DDEV project: the plugin knows it by .ddev/config.keycloak.yaml. */
export const PLATFORM = 'keycloak';

/** The commands the installer places in every sites folder. */
export const COMMANDS = ['cmd-keycloak-project.sh', 'cmd-tools-keycloak-admin.sh'];

/** The agents the installer places in the AI Agents folder. */
export const AGENTS = ['keycloak-site-builder', 'keycloak-tester'];

/** The skill the installer places in the AI Skills folder (a folder each, with its SKILL.md). */
export const SKILLS = ['keycloak-scenarios'];

/** The slash command the installer places in the AI Commands folder. */
export const AI_COMMANDS = ['keycloak-test'];

/** The prompts the installer places in the AI Prompts folder: each a whole launch command for a new session. */
export const PROMPTS = ['keycloak-build-and-test', 'keycloak-scenarios-for-an-area'];

/** What the assistant is told about Keycloak in this workspace. */
export function assistantContext(): string {
  return [
    'Keycloak (a plugin, @webship.co/workspace-keycloak): a sign-in server is built with',
    '`bash cmd-keycloak-project.sh <name> --install --add-users` from a sites folder (dev, test, sandboxes, demos):',
    'the official image (quay.io/keycloak/keycloak) in development mode, a service of a generic DDEV project behind its web server at https://<name>.ddev.site/auth,',
    'with a small test app at https://<name>.ddev.site that signs in through it, and the project\'s mail catcher for its mail (https://<name>.ddev.site:8026);',
    '`--install` imports the test realm (`--realm <file>` imports a realm file of one\'s own) and makes the workspace account the admin of the master realm,',
    '`--add-users` adds the default accounts (administrator, the realm\'s admin; editor; user; otpuser, with a one-time code set up),',
    '`--keycloak-version` takes a release (26.8.2 by default), `--login-theme` the realm\'s login theme. A build takes about a minute and the server about 850 MB of memory.',
    '`bash cmd-tools-keycloak-admin.sh <name>` says what the server is; `--kcadm "<command>"` runs the server\'s admin CLI (kcadm.sh) as the admin of the master realm,',
    '`--restart` starts the server again, `--add-users` and `--cancel-users` manage the default accounts.',
    'The row\'s Users menu does not apply to a sign-in server (its project type is generic): use the admin tool for the accounts.',
    '`bash cmd-tools-testing.sh <name>` sets up webship-js with the Keycloak step pack; `--run` runs the suite.',
    `For Keycloak work, hand over to the agents ${AGENTS.map((a) => `\`${a}\``).join(' and ')}.`,
    `The plugin also places the skill ${SKILLS.map((a) => `\`${a}\``).join(', ')} (the step pack's phrases, by area) in ai-skills/,`,
    `the command ${AI_COMMANDS.map((a) => `\`/${a} <site>\``).join(', ')} in ai-commands/ and the prompts ${PROMPTS.map((a) => `\`${a}\``).join(' and ')} in ai-prompts/.`,
    'Never run kcadm.sh, kc.sh or Java on the host for a project; removing the project removes the server\'s data volume too.',
  ].join(' ');
}

export function register(api: PluginApi): void {
  api.addAssistantContext(assistantContext);
}
