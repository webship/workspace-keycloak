// The test app: it asks the sign-in server whether the browser is signed in (silently, in a hidden
// frame), shows the account it signed in as, and sends a person to the sign-in server to sign in,
// register, manage their account or sign out. It uses the official JavaScript adapter (keycloak-js).
//
// When it has its answer it sets <html data-sign-in="signed-in|signed-out|error">: a signal a test can
// wait on. config.json (written by the build of the site) names the server, the realm and the clients.
import Keycloak from 'keycloak-js';

const $ = (id) => document.getElementById(id);
const root = document.documentElement;
const clientId = document.body.dataset.client;
const appName = document.body.dataset.appName;
const base = new URL('./', location.href).href;

function show(state, text) {
  $('status').textContent = text;
  $('signed-in').hidden = state !== 'signed-in';
  $('signed-out').hidden = state === 'signed-in';
  root.dataset.signIn = state;
}

function fail(error) {
  const reason = (error && (error.error_description || error.error || error.message)) || String(error || 'unknown error');
  $('error').textContent = `The sign-in did not succeed: ${reason}`;
  $('error').hidden = false;
}

try {
  const config = await (await fetch('/config.json', { cache: 'no-store' })).json();
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
  $('register').href = await keycloak.createRegisterUrl({ redirectUri: base });

  if (authenticated) {
    const token = keycloak.tokenParsed || {};
    const roles = ((token.realm_access && token.realm_access.roles) || [])
      .filter((role) => !/^(default-roles-.*|offline_access|uma_authorization)$/.test(role)).sort();
    $('username').textContent = token.preferred_username || '';
    $('name').textContent = token.name || [token.given_name, token.family_name].filter(Boolean).join(' ');
    $('email').textContent = token.email || '';
    $('roles').textContent = roles.length ? roles.join(', ') : 'none';
    $('account').href = keycloak.createAccountUrl({ redirectUri: base });
    show('signed-in', `Signed in to ${appName} as ${token.preferred_username}.`);
  } else {
    show('signed-out', `You are not signed in to ${appName}.`);
  }
} catch (error) {
  fail(error);
  show('error', 'The app could not reach the sign-in server.');
}
