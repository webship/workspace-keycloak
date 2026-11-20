Feature: Signing in to the app
  Scenario: The user logs in through the login form and is back in the app
    Given I am not logged in
    When I log in as "user" with the login form
    Then I should be back in the app
    And I should see "Signed in to Webship test app as user."
    And I should be logged in as "user"

  Scenario: A wrong password is refused
    Given I am on the login page
    When I log in with the username "user" and the password "Wrong-password-1"
    Then the login should be refused with "Invalid username or password."
    And I should not be logged in

  Scenario: A login with "Remember me" outlives the browser
    Given I am not logged in
    When I log in as "editor" with the login form and "Remember me" checked
    Then the sign-in should be remembered
    When I close the browser and open it again
    Then I should be logged in as "editor"
