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

  test "an error toast interrupts and stays until it is closed" do
    render inline: %(<%= ui_toast_render "Not saved.", :error %>)

    assert_select "[data-controller=toast][role=alert][data-toast-auto-hide-value=false][data-turbo-temporary]",
                  text: /Not saved\./
    assert_select ".toast-progress", false
  end
end
