Feature: The sign-in server answers and its accounts work
  As the owner of the sign-in server
  I want the login, each default account, the one-time code and the refusals to work
  So that a build that came out broken is caught before anything else is tested

  # Placed by the workspace's testing setup as a starting point: it is yours to change.
  # The accounts are the default ones (cmd-tools-keycloak-admin.sh --add-users); a scenario logs in by a
  # handle of the users registry in cucumber.js, so no password is written here. It passes on a site built
  # with --install --add-users.

  @critical
  Scenario: A visitor of the app is sent to the login form
    Given I am not logged in
    Then I should see "You are not signed in to Webship test app."
    When I go to the login page
    Then I should be on the login page

  Scenario Outline: The <account> account logs in and is back in the app
    Given I am not logged in
    When I log in as "<account>" with the login form
    Then I should be back in the app
    And I should be logged in as "<account>"

    Examples:
      | account       |
      | administrator |
      | editor        |
      | user          |

  Scenario: The account with a one-time code types the code its key gives
    Given I am not logged in
    When I submit the login form as "otpuser"
    Then I should be asked for a one-time code
    When I enter the one-time code of "otpuser"
    Then I should be logged in as "otpuser"

  Scenario: A wrong password is refused
    Given I am on the login page
    When I log in with the username "user" and the password "Wrong-password-1"
    Then the login should be refused with "Invalid username or password."
    And I should not be logged in

  # The browser logs the console's refused request (403).
  @js-off
  Scenario: An account without the realm's admin rights is not let into the admin console
    Given I am a logged in user with the "user" user
    When I go to the admin console
    Then I should not be allowed into the admin console
