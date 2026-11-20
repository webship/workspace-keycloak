---
name: keycloak-scenarios
description: Write webship-js scenarios for the sign-in of an app through a Keycloak server of the Webship Workspace from phrases that exist — the Keycloak step pack's steps by area (the session and the login form, one-time codes, the required actions, the password reset and its mail, the registration form's refusals, the consent screen, the error pages, the account console and the admin console), the handles of the users registry, the test-data steps that put an account back after the scenario, the traps found on a real server, and three features that pass on a site built with the default accounts. Use when writing or fixing a scenario for a sign-in, choosing a step for a page of the server, or turning a manual check of the login into a feature.
---

# keycloak-scenarios

Scenarios for a site built with the Keycloak plugin (`bash cmd-keycloak-project.sh <site> --install
--add-users`) in a container-based workspace (DDEV by default), tested with webship-js and
`@webship-js/keycloak-steps` once `bash cmd-tools-testing.sh <site>` set the project up. Every phrase below
exists in the pack or in webship-js; a scenario names no platform.

## Accounts and test data

- `Given I am a logged in user with the "user" user`: `administrator` (the realm's admin), `editor` (the
  realm role editor), `user` (no role of its own), `otpuser` (a one-time code set up; its key is in the
  users registry). The server logs in with the username the registry gives. `Given I am not logged in` for a
  visitor of the app.
- `Given the account "user" must update its password` (`must verify its email`, `must set up a one-time
  code`): the server asks for it at the next login; the account's sessions end first.
- `Given "user" has not granted access to "Webship partner app"`: the app's consent screen comes again.
- Whatever a scenario changes on an account (a password, a required action, a code set up, a grant, its names)
  is put back after it through the admin REST API, as the data administrator (`dataAdmin` in `cucumber.js`).

## Phrases by area

| Area | Steps |
| --- | --- |
| Session | `I am on the login page`, `I go to the login page`, `I log in as "user" with the login form` (`… and "Remember me" checked`), `I submit the login form as "otpuser"`, `I log in with the username "…" and the password "…"`, `the login should be refused with "Invalid username or password."`, `I log out`, `I should be logged in as "user"`, `I should not be logged in`, `I should be on the login page`, `I should be back in the app`, `I close the browser and open it again`, `the sign-in should be remembered` (`should not`), `I restart the login` |
| One-time codes | `I should be asked for a one-time code`, `I enter the one-time code of "otpuser"`, `I enter the one-time code "000000"`, `the one-time code should be refused with "Invalid authenticator code."`, `I should be asked to set up a one-time code`, `I set up a one-time code named "Test laptop"` |
| Passwords and email | `I ask for a password reset link for "user"`, `I should see the status message "You should receive an email shortly with further instructions."`, `I should be asked to update my password`, `I choose a new password`, `I choose the new password "…" confirmed as "…"`, `I should be asked to verify my email` |
| Mail | `an email with the subject "Reset password" should be sent to "user"`, `no email should be sent to "nobody@example.com"`, `the email with the subject "Reset password" to "user" should contain "…"`, `I open the "Link to reset credentials" link of the email to "user"` |
| Registration (refusals only) | `I try to register with:` and a table of labels and values, `the "Username" field should have the error "Username already exists."`, `the "First name" field should have no error` |
| Consent | `I should be asked to grant access to "Webship partner app"`, `the consent screen should ask for "Email address"`, `I grant access`, `I deny access` |
| Error pages | `I start a sign-in for the client "webship-app" with the redirect "https://wrong.example.org/"`, `I should see the error page "Invalid parameter: redirect_uri"`, `I go back to the application` |
| Account console | `I go to the account console`, `I open "Signing in" in the account console`, `I should be on the "Signing in" page of the account console`, `the personal info should show "user@example.com" as "Email"`, `I set my "First name" to "…" in the personal info`, `I save my personal info`, `I should see the success notification "Your account has been updated."`, `the signing-in page should list the authenticator "Test phone"`, `I start setting up an authenticator in the account console`, `I delete the authenticator "…" in the account console`, `the device activity should show the current session with "Webship test app"`, `the applications should list "Webship partner app" as "Third-party"`, `"Webship partner app" should have access to "Email address"`, `I remove the access of "…" in the account console`, `I sign out of the account console` |
| Admin console | `I go to the admin console`, `the admin console should show the realm "Webship test sign-in"`, `I open "Users" in the admin console`, `I search the users for "otp"`, `the user list should show "otpuser"`, `I open the user "editor" in the admin console`, `I open the "Credentials" tab`, `the user's details should show "editor@example.com" as "Email"`, `the user should have the role "editor"`, `I reset the password of "user" in the admin console` (`… as a temporary password`), `the realm should have the client "webship-app"`, `the realm should have the role "editor"`, `I should not be allowed into the admin console` |

## A scenario, start to end

A password reset by mail: the new password is the scenario's own, and the account gets its password back
after it whatever happens in it.

```gherkin
Feature: Forgotten passwords
  Scenario: A reset link by mail sets a new password
    Given I am not logged in
    When I ask for a password reset link for "user"
    Then an email with the subject "Reset password" should be sent to "user"
    When I open the "Link to reset credentials" link of the email to "user"
    Then I should be asked to update my password
    When I choose a new password
    Then I should be back in the app
    And I should be logged in as "user"
```

## Traps found on a real server

- The login pages are rendered by the server: every action is a form and a new page. The steps read which
  page of the flow is on screen (the login form, the code, a required action, the consent, an error) by its
  form, so a scenario says what the server asks next with `I should be asked …`.
- A one-time code is taken once: a second sign-in of the same account in the same 30-second window waits for
  the next window's code, as a person does. Keep the form logins of `otpuser` few; `Given I am a logged in
  user with the "otpuser" user` takes its session over.
- The required actions come only at a login: the test-data steps end the account's sessions, so the next
  login meets them.
- The "Mobile Authenticator Setup" page labels its two fields for an element that does not exist: the steps
  find them by their label's group; with webship-js's own field steps, use their ids (`#totp`, `#userLabel`).
- An error page and a refused save answer 400, 403 or 404, and the browser logs that answer: tag those
  scenarios `@js-off`.
- The account console's page "Applications" is headed "Application": read the page by its navigation item
  (`I should be on the "Applications" page of the account console`).
- On a shared machine the browser on the host can lose a request when another container starts: run the
  suite in the container (`bash cmd-tools-testing.sh <site> --run`).

## Examples

- [`examples/session.feature`](examples/session.feature): the login form, a refusal, "Remember me" and a closed browser.
- [`examples/one-time-code.feature`](examples/one-time-code.feature): the code of `otpuser`, a wrong code, a code set up when the server asks.
- [`examples/consoles.feature`](examples/consoles.feature): the personal info, the consent and its grant in the account console, the admin console's user search.

Copy them into `tests/features/` of the project and run them:

```bash
bash cmd-tools-testing.sh <site> --run --path tests/features/session.feature
```

## The book

For any automated functional testing in this work (a Gherkin feature, a step definition, choosing a
step, a test run and its failures), read the book *Automated Functional Testing Recipes* first.

- **Where.** Use the first that exists: `.claude/automated-functional-testing-recipes/` in the project,
  `~/.claude/automated-functional-testing-recipes/` (installed by webship/webship-js-ai-agent,
  webship/webship-js-skills or webship/ai-agents), or
  https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes
- **How.** Its `README.md` first, then the chapter that matches the task (one file per chapter,
  named by its subject), not the single complete file.
- **Which wins.** The installed webship-js package and the step pack are the source of truth for
  step phrasing. When they differ from the book, follow them and say so.
- **For Keycloak.** Start with `ch10-authentication-authorization.md` (logins, sessions, roles and refusals),
  `ch07-waiting-dynamic-content.md` (waiting on the app's own signals), `ch27-testing-spa.md` (the consoles, single-page
  apps) and `ch20-design-patterns-for-tests.md` (test data a scenario changes and puts back).
