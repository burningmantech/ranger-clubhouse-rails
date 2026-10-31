# frozen_string_literal: true

require "test_helper"

class UiComponents::UiMatchStepperHelperTest < ActionView::TestCase
  test "draws the count and two icon buttons for the named controller, in a named group" do
    render inline: <<~ERB
      <%= ui_match_stepper "search-matches", label: "Matches in this conversation", current: 2, total: 3 %>
    ERB

    assert_select "div.join[role=group][aria-label='Matches in this conversation']" do
      assert_select "span.join-item[role=status][data-search-matches-target=count]", text: "Match 2 of 3"
      assert_select "button.btn-sm.btn-square.join-item[type=button]", count: 2
      assert_select "button[aria-label='Previous match'][data-action='search-matches#previous'] i.fa-chevron-up"
      assert_select "button[aria-label='Next match'][data-action='search-matches#next'] i.fa-chevron-down"
    end
  end
end
