# frozen_string_literal: true

require "test_helper"

class UiDataBlockHelperTest < ActionView::TestCase
  include UiComponents::UiDataBlockHelper

  test "wraps content in a scrollable monospaced block" do
    render inline: %(<%= ui_data_block("{\\n  \\"a\\": 1\\n}") %>)

    assert_select "div.overflow-auto.rounded-base.border.bg-base-100.shadow-inner" do
      assert_select "pre.font-mono.whitespace-pre-wrap.break-all", text: /"a": 1/
    end
  end

  test "a max height is added when the caller asks for one" do
    render inline: %q(<%= ui_data_block("payload", max_height: "max-h-56") %>)

    assert_select "div.max-h-56.overflow-auto"
  end

  test "a block with no max height carries none" do
    render inline: %q(<%= ui_data_block("payload") %>)

    assert_select "div.overflow-auto"
    assert_select "div[class*=?]", /max-h/, count: 0
  end

  test "content is escaped, not interpreted" do
    render inline: '<%= ui_data_block("<script>alert(1)</script>") %>'

    assert_select "pre", text: "<script>alert(1)</script>"
    assert_select "pre script", count: 0
  end
end
