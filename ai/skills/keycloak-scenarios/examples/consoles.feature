Feature: The account console and the admin console
  Scenario: The personal info of the account signed in
    Given I am a logged in user with the "user" user
    When I go to the account console
    Then the personal info should show "user@example.com" as "Email"

  Scenario: A grant on the consent screen, listed in the account console and taken back
    Given "user" has not granted access to "Webship partner app"
    And I am not logged in
    When I go to "/partner/"
    And I log in as "user" with the login form
    Then I should be asked to grant access to "Webship partner app"
    When I grant access
    And I go to the account console
    And I open "Applications" in the account console
    Then the applications should list "Webship partner app" as "Third-party"
    When I remove the access of "Webship partner app" in the account console
    Then the applications should not list "Webship partner app"

  Scenario: The admin finds an account by the start of its name
    Given I am a logged in user with the "administrator" user
    When I go to the admin console
    And I search the users for "otp"
    Then the user list should show "otpuser"
