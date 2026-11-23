# frozen_string_literal: true

require "test_helper"

class UiLabelValueHelperTest < ActionView::TestCase
  include UiComponents::UiLabelValueHelper

  test "the default layout puts each label and value straight in the list" do
    render inline: <<~ERB
      <%= ui_label_value label_width: "9rem" do |list| %>
        <% list.row "Email", "ranger@example.com" %>
      <% end %>
    ERB

    assert_select "dl.ui-label-value[style='--label-width: 9rem'] > dt", text: "Email", count: 1
    assert_select "dl.ui-label-value > dd.text-body", text: "ranger@example.com", count: 1
    assert_select "dl.ui-label-value-fitted", count: 0
  end

  test "the fitted layout adds its class and no wrapper" do
    render inline: <<~ERB
      <%= ui_label_value layout: :fitted do |list| %>
        <% list.row "Email", "ranger@example.com" %>
      <% end %>
    ERB

    assert_select "dl.ui-label-value.ui-label-value-fitted > dt + dd", text: "ranger@example.com", count: 1
    assert_select "dl > div", count: 0
  end
end
