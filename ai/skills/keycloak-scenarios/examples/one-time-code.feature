Feature: One-time codes
  Scenario: The account with a one-time code types the code its key gives
    Given I am not logged in
    When I submit the login form as "otpuser"
    Then I should be asked for a one-time code
    When I enter the one-time code of "otpuser"
    Then I should be logged in as "otpuser"

  Scenario: A wrong code is refused
    Given I am not logged in
    When I submit the login form as "otpuser"
    And I enter the one-time code "000000"
    Then the one-time code should be refused with "Invalid authenticator code."

  Scenario: A code set up when the server asks for it
    Given the account "user" must set up a one-time code
    And I am not logged in
    When I log in as "user" with the login form
    Then I should be asked to set up a one-time code
    When I set up a one-time code named "Skill phone"
    Then I should be back in the app
