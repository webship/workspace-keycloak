// The test app: it asks the sign-in server whether the browser is signed in (silently, in a hidden
// frame), shows the account it signed in as, and sends a person to the sign-in server to sign in,
// register, manage their account or sign out. It uses the official JavaScript adapter (keycloak-js).
//
// When it has its answer it sets <html data-sign-in="signed-in|signed-out|error">: a signal a test can
// wait on. config.json (written by the build of the site) names the server, the realm and the clients.
//
// A browser does not run TypeScript: `npm run build` compiles this file to keycloak-app.js beside it
// (tsconfig.app.json), and that is the file the builder copies into a site as app.js.
import Keycloak from 'keycloak-js';
import type { KeycloakTokenParsed } from 'keycloak-js';

/** What the page says about the sign-in, in <html data-sign-in>. */
type SignInState = 'signed-in' | 'signed-out' | 'error';

/** config.json, written by the build of the site. */
interface AppConfig {
  url: string;
  realm: string;
}

/** An element of the page by its id. The page (keycloak-app.html) has every id the app asks for. */
function $<T extends HTMLElement = HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) throw new Error(`The page has no element with the id "${id}".`);
  return element as T;
}

const root: HTMLElement = document.documentElement;
const clientId: string = document.body.dataset.client ?? '';
const appName: string = document.body.dataset.appName ?? '';
const base: string = new URL('./', location.href).href;

function show(state: SignInState, text: string): void {
  $('status').textContent = text;
  $('signed-in').hidden = state !== 'signed-in';
  $('signed-out').hidden = state === 'signed-in';
  root.dataset.signIn = state;
}

/** The reason an error carries: the adapter's (error_description, error) or a thrown Error's message. */
function reasonOf(error: unknown): string {
  if (typeof error === 'object' && error !== null) {
    const known = error as { error_description?: unknown; error?: unknown; message?: unknown };
    const reason = known.error_description || known.error || known.message;
    if (reason) return String(reason);
  }
  return String(error || 'unknown error');
}

function fail(error: unknown): void {
  $('error').textContent = `The sign-in did not succeed: ${reasonOf(error)}`;
  $('error').hidden = false;
}

try {
  const config = await (await fetch('/config.json', { cache: 'no-store' })).json() as AppConfig;
  const keycloak = new Keycloak({ url: config.url, realm: config.realm, clientId });
  let authenticated = false;
  try {
    authenticated = await keycloak.init({
      onLoad: 'check-sso',
      silentCheckSsoRedirectUri: new URL('silent-check-sso.html', base).href,
      checkLoginIframe: false,
      pkceMethod: 'S256',
    });
  } catch (error) {
    fail(error);
  }

  $('sign-in').addEventListener('click', () => keycloak.login({ redirectUri: base }));
  $('sign-out').addEventListener('click', () => keycloak.logout({ redirectUri: base }));
  $<HTMLAnchorElement>('register').href = await keycloak.createRegisterUrl({ redirectUri: base });

  if (authenticated) {
    const token: KeycloakTokenParsed = keycloak.tokenParsed || {};
    const roles: string[] = ((token.realm_access && token.realm_access.roles) || [])
      .filter((role) => !/^(default-roles-.*|offline_access|uma_authorization)$/.test(role)).sort();
    const claim = (name: string): string => {
      const value: unknown = token[name];
      return typeof value === 'string' ? value : '';
    };
    $('username').textContent = claim('preferred_username');
    $('name').textContent = claim('name') || [claim('given_name'), claim('family_name')].filter(Boolean).join(' ');
    $('email').textContent = claim('email');
    $('roles').textContent = roles.length ? roles.join(', ') : 'none';
    $<HTMLAnchorElement>('account').href = keycloak.createAccountUrl({ redirectUri: base });
    show('signed-in', `Signed in to ${appName} as ${claim('preferred_username')}.`);
  } else {
    show('signed-out', `You are not signed in to ${appName}.`);
  }
} catch (error) {
  fail(error);
  show('error', 'The app could not reach the sign-in server.');
}
