# frozen_string_literal: true

require "test_helper"

class IdListTest < ActiveSupport::TestCase
  test "parse keeps whole positive numbers, in the order sent, once each" do
    assert_equal [5], IdList.parse(["abc", "", "5", "7x"])
    assert_equal [7, 5], IdList.parse(["7", 5, "0", "00", "-3", "5", 7])
    assert_equal [5], IdList.parse("5")
    assert_equal [], IdList.parse(nil)
  end

  test "clean? allows ids and the hidden blank, and nothing else" do
    assert IdList.clean?(["", "5", 7])
    assert IdList.clean?([])

    [["abc"], ["0"], ["7x"], [nil], [["5"]], [{ "5" => "1" }], "5", nil].each do |values|
      assert_not IdList.clean?(values), values.inspect
    end
  end

  test "the type reads nil as no ids" do
    type = IdList::Type.new

    assert_equal [], type.cast(nil)
    assert_equal [5], type.cast(["", "abc", "5"])
  end
end
