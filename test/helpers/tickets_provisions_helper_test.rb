# frozen_string_literal: true

require "test_helper"

class TicketsProvisionsHelperTest < ActionView::TestCase
  test "dollars prints cents only when there are some" do
    assert_equal "$12.50", dollars(12.5) # a float mail price; "%g" printed "$12.5"
    assert_equal "$40", dollars(40)
    assert_equal "$40", dollars(40.0)
    assert_equal "$1,250", dollars(1250)
  end

  test "dollars prints nothing for an unset price" do
    assert_nil dollars(nil)
  end
end
