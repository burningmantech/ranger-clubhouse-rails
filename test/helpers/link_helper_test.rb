# frozen_string_literal: true

require "test_helper"

class LinkHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "email_link_or_dash links an address and dashes a blank one" do
    assert_dom_equal %(<a class="#{LinkHelper::TABLE_LINK_CLASSES}" href="mailto:a@example.com">a@example.com</a>),
                     email_link_or_dash("a@example.com")
    assert_equal value_or_dash(nil), email_link_or_dash(nil)
    assert_equal value_or_dash(nil), email_link_or_dash("")
  end
end
