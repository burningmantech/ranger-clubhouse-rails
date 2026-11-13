# frozen_string_literal: true

require "test_helper"

class ModalHelperTest < ActionView::TestCase
  include ModalHelper
  include ButtonHelper
  include IconHelper

  # Why the dialog must leave the helper as ordinary text is written out in
  # ModalHelper#confirm_modal_dialog. These pin the part that would otherwise
  # go quiet: borrowed text has to survive the trip as text.
  PAYLOAD = "<img src=x onerror=alert(1)>"

  test "the dialog is not marked safe, so writing it into an attribute escapes it" do
    dialog = confirm_modal_dialog(message: "Delete #{PAYLOAD}?")

    assert_not dialog.html_safe?, "marking this safe lets borrowed text reach innerHTML as markup"
  end

  test "borrowed text survives the attribute round trip as text, not markup" do
    dialog = confirm_modal_dialog(title: "Confirm", message: "Delete #{PAYLOAD}?")

    # What the page actually carries.
    attribute = tag.a("Delete", data: { turbo_confirm: dialog })

    # The browser takes one layer off when it reads the attribute back. What is
    # left is what innerHTML is asked to parse.
    read_back = CGI.unescapeHTML(attribute[/data-turbo-confirm="([^"]*)"/, 1])

    assert_includes read_back, "<dialog", "the dialog itself must still be markup"
    assert_not_includes read_back, PAYLOAD, "the payload must not arrive as live markup"
    assert_includes read_back, "&lt;img", "the payload must arrive as text"
  end

  test "a confirmation still reads the way it was written" do
    dialog = confirm_modal_dialog(title: "Confirm Deletion",
                                  message: "Are you sure?",
                                  confirm_label: "Delete It",
                                  cancel_label: "Never Mind")

    assert_includes dialog, "Confirm Deletion"
    assert_includes dialog, "Are you sure?"
    assert_includes dialog, "Delete It"
    assert_includes dialog, "Never Mind"
    assert_includes dialog, "turbo-confirm-button"
    assert_includes dialog, "turbo-cancel-button"
  end

  test "a dialog is named by its title and announced as modal" do
    html = modal(id: "edit-note") { |m| m.title("Edit Note") + m.body { "Body" } }
    dialog = Nokogiri::HTML5.fragment(html).at_css("dialog")

    assert_equal "edit-note-title", dialog["aria-labelledby"]
    assert_equal "true", dialog["aria-modal"]
    assert_equal "Edit Note", Nokogiri::HTML5.fragment(html).at_css("h3#edit-note-title").text
    assert_equal "Close Dialog", Nokogiri::HTML5.fragment(html).at_css(".modal-backdrop button").text
  end

  test "a dialog without a title points at nothing" do
    dialog = Nokogiri::HTML5.fragment(modal { |m| m.body { "Body" } }).at_css("dialog")

    assert_nil dialog["aria-labelledby"]
  end

  test "confirm_modal carries the dialog plus the verb" do
    data = confirm_modal(title: "Confirm", message: "Sure?", method: :delete)

    assert_equal :delete, data[:turbo_method]
    assert_not data[:turbo_confirm].html_safe?
    assert_includes data[:turbo_confirm], "<dialog"
  end
end
