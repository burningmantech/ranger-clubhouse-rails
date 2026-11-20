# frozen_string_literal: true

require "test_helper"

class ToastHelperTest < ActionView::TestCase
  include UiComponents::ToastHelper
  include IconHelper

  # The layout hands over flash keys, which are strings, not symbols.
  test "a success toast from the flash is a status that counts down" do
    render inline: %(<%= ui_toast_render "Saved.", "success" %>)

    assert_select "[data-controller=toast][role=status]:not([aria-live])", text: /Saved\./ do
      assert_select ".toast-progress[data-toast-target=progress]"
    end
    assert_select "[data-toast-auto-hide-value]", false
  end

  # A page refresh morphs the page, and the morph reuses an element unless its
  # id differs. A toast reused for the next message keeps its controller, which
  # does not connect again, so the message would arrive hidden.
  test "every toast has an id of its own, so a morph never turns one into the next" do
    render inline: %(<%= ui_toast_render "Added.", :success %><%= ui_toast_render "Removed.", :success %>)

    ids = css_select("[data-controller=toast]").map { |toast| toast["id"] }
    assert_equal 2, ids.compact.uniq.size, "expected two toasts with different ids, got #{ids.inspect}"
  end

  test "an error toast interrupts and stays until it is closed" do
    render inline: %(<%= ui_toast_render "Not saved.", :error %>)

    assert_select "[data-controller=toast][role=alert][data-toast-auto-hide-value=false][data-turbo-temporary]",
                  text: /Not saved\./
    assert_select ".toast-progress", false
  end
end
