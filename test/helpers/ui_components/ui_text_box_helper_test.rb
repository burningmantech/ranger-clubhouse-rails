# frozen_string_literal: true

require "test_helper"

class UiComponents::UiTextBoxHelperTest < ActionView::TestCase
  test "draws a bordered, tinted, padded box that does not scroll or take focus" do
    render inline: <<~ERB
      <%= ui_text_box class: "mb-3" do %>Hello<% end %>
    ERB

    assert_select "div.rounded-base.border.border-line.bg-default.p-3.mb-3", text: "Hello" do |boxes|
      box = boxes.first
      assert_nil box["tabindex"]
      assert_nil box["role"]
      assert_not_includes box["class"], "overflow-y-auto"
    end
  end

  test "scrolls past max_height: as a named, focusable region with a focus ring" do
    render inline: <<~ERB
      <%= ui_text_box max_height: "max-h-64", label: "Prologue" do %>Long<% end %>
    ERB

    assert_select "div.bg-default.max-h-64.overflow-y-auto.focus-visible\\:ring-2" \
                  "[tabindex='0'][role=region][aria-label=Prologue]", text: "Long"
  end

  test "a scrolling box without a label raises" do
    assert_raises(ArgumentError) { ui_text_box(max_height: "max-h-64") { "x" } }
  end

  test "max_height: takes only a Tailwind max-h step" do
    assert_raises(ArgumentError) { ui_text_box(max_height: "max-h-[300px]", label: "X") { "x" } }
    assert_raises(ArgumentError) { ui_text_box(max_height: "300px", label: "X") { "x" } }
  end
end
