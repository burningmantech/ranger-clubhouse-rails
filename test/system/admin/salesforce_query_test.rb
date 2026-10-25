# frozen_string_literal: true

require "application_system_test_case"

# Sorting happens in the browser, on the rows a run brought back
# (table_sort_controller.js), so this is the one place it can be seen working.
# The fake connector swap is process-wide, so it reaches the server thread.
class Admin::SalesforceQueryTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include FakeSalesforceConnectorHelper

  RESULTS = "#salesforce-query-results"

  setup do
    tech_ninja = person(:echelon_ranger)
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(tech_ninja, Role::TECH_NINJA)
    sign_in(tech_ninja)
  end

  test "pressing a heading sorts by it, ascending then descending, with a null last both times" do
    with_fake_connector(connector) do
      run_query

      click_heading "Name"
      assert_selector "#{RESULTS} [data-table-sort-target=status]", text: "Sorted by Name, ascending."
      assert_selector "#{RESULTS} th[aria-sort]", count: 1
      assert_selector "#{RESULTS} th[aria-sort=ascending]", text: "Name"
      assert_equal ["alpha", "Bravo", "Charlie", "—null"], column(0)
      assert_selector "#live-region", text: "Sorted by Name, ascending.", visible: :all

      click_heading "Name"
      assert_selector "#{RESULTS} [data-table-sort-target=status]", text: "Sorted by Name, descending."
      assert_equal ["Charlie", "Bravo", "alpha", "—null"], column(0)
    end
  end

  test "a number column sorts by value, and its icon turns from neutral to a caret" do
    with_fake_connector(connector) do
      run_query
      assert_selector "#{RESULTS} th:nth-child(2) i.fa-sort"

      click_heading "Score__c"
      assert_selector "#{RESULTS} th[aria-sort=ascending]", text: "Score__c"
      assert_equal ["1", "9", "10", "—null"], column(1)
      assert_selector "#{RESULTS} th:nth-child(2) i.fa-caret-up"
      assert_selector "#{RESULTS} th:nth-child(1) i.fa-sort"
    end
  end

  test "a new run starts back in query order" do
    with_fake_connector(connector(runs: 2)) do
      run_query
      click_heading "Name"
      assert_selector "#{RESULTS} [data-table-sort-target=status]", text: "Sorted by Name, ascending."

      run_query
      assert_selector "#{RESULTS} [data-table-sort-target=status]", text: "In query order."
      assert_no_selector "#{RESULTS} th[aria-sort]"
      assert_equal ["Bravo", "alpha", "—null", "Charlie"], column(0)
    end
  end

  private

  def connector(runs: 1)
    records = [
      { "Name" => "Bravo", "Score__c" => 9 },
      { "Name" => "alpha", "Score__c" => 10 },
      { "Name" => nil, "Score__c" => nil },
      { "Name" => "Charlie", "Score__c" => 1 }
    ]
    FakeSalesforceConnector.new(query_results: Array.new(runs) { FakeSalesforceConnector.envelope(*records) })
  end

  def run_query
    visit admin_salesforce_query_path unless page.has_field?("SOQL or SOSL Query", wait: 0)
    fill_in "SOQL or SOSL Query", with: "SELECT Name, Score__c FROM Ranger__c"
    click_button "Run Query"
    assert_selector "#{RESULTS} [data-table-sort-target=status]", text: "In query order."
  end

  def click_heading(name)
    within(RESULTS) { find("th button", exact_text: name).click }
  end

  def column(index)
    evaluate_script(<<~JS)
      [...document.querySelectorAll("#{RESULTS} tbody tr")].map((row) => row.cells[#{index}].textContent.trim())
    JS
  end
end
