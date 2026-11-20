Write and run the webship-js scenarios of one area of a Keycloak sign-in server (the login, one-time codes, passwords, consent, the consoles), from the step pack's own phrases.

The launch command below is for Claude Code, the default; the text between the triple quotes can be given to another AI CLI as it is.

```
claude --permission-mode bypassPermissions """
Write and run the scenarios of <area> for the Keycloak site <site> of this sites folder
# ~/workspace/<dev|test|sandboxes|demos> · https://<site>.ddev.site · container-based (DDEV by default)
# the area: <login|one-time codes|passwords and mail|registration refusals|consent|error pages|account console|admin console>
# every phrase from the step pack or webship-js (the keycloak-scenarios skill lists them by area): never invent a step, never name the platform in a step phrase
# accounts are configuration: never create or delete one in a suite, never write a password into a feature; registration is tested through its refusals only
# a feature to write or a run to read: the book Automated Functional Testing Recipes first (its README.md, then the matching chapter), from .claude/automated-functional-testing-recipes/ in the project, ~/.claude/automated-functional-testing-recipes/ or https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

1. bash cmd-tools-testing.sh <site>
   (once: webship-js, the step pack, the users registry)
2. Open the pages of the area in the Playwright MCP browser, in a tab of your own, as the account each scenario uses; note what a person reads.
3. Write tests/features/<area>.feature from those notes: one scenario per behaviour, the test-data steps for an account's state (they put it back after the scenario).
4. bash cmd-tools-testing.sh <site> --dry-run --path tests/features/<area>.feature
5. bash cmd-tools-testing.sh <site> --run --path tests/features/<area>.feature
6. Run it a second time: it must pass again (the steps put back what a scenario changed).

If a scenario fails, read its message and its screenshot, look at the page again in the browser, then fix the scenario, not the step pack.
When the feature is green twice: the scenarios, the steps, and anything the pages did that surprised you.
"""
```
