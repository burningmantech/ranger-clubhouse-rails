# frozen_string_literal: true

require "test_helper"

class StatusChangeWarningsTest < ActiveSupport::TestCase
  test "uses active warnings when the current status is active" do
    warning = StatusChangeWarnings.warning_for(old_status: Person::ACTIVE, new_status: Person::ALPHA)

    assert_equal "Confirm Alpha Conversion", warning[:title]
    assert_includes warning[:message], "convert an active account to an Alpha account"
  end

  test "uses other warnings when the current status is not active" do
    warning = StatusChangeWarnings.warning_for(old_status: Person::INACTIVE, new_status: Person::ALPHA)

    assert_equal "Confirm Alpha Conversion", warning[:title]
    assert_includes warning[:message], "convert an inactive account to an Alpha account"
  end

  test "returns nil when the selected status has no warning entry" do
    assert_nil StatusChangeWarnings.warning_for(old_status: Person::ACTIVE, new_status: Person::ACTIVE)
    assert_nil StatusChangeWarnings.warning_for(old_status: Person::INACTIVE, new_status: Person::ACTIVE)
  end

  # The wording is written as markup and has to stay that way -- the dialog
  # shows it, and the destructive ones lean on the bold to be read.
  test "the wording keeps the markup it is written with" do
    warning = StatusChangeWarnings.warning_for(old_status: Person::ACTIVE, new_status: Person::DECEASED)

    assert_predicate warning[:message], :html_safe?
    assert_includes warning[:message], "<p>"
    assert_includes warning[:message], "<b"
  end

  # A status is filled into that markup, so it has to arrive as text. Read as
  # markup it would run, because the dialog is put on the page by assigning it.
  test "a status filled into the wording arrives as text, not markup" do
    warning = StatusChangeWarnings.warning_for(old_status: Person::ACTIVE,
                                               new_status: "<img src=x onerror=alert(1)>")

    assert_nil warning, "an unknown status has no warning to fill in"
  end

  test "a status that looks like markup is escaped where it is filled in" do
    # Reach past the status list on purpose: the point is what the filling in
    # does with the value, not which values can reach it today.
    message = StatusChangeWarnings::ACTIVE_WARNINGS[Person::DECEASED][:message]

    filled = message.html_safe % { old_status: "active", status: "<img src=x onerror=alert(1)>" }

    assert_not_includes filled, "<img", "a status must not arrive as markup"
    assert_includes filled, "&lt;img", "a status must arrive as text"
    assert_includes filled, "<b", "the wording keeps its own markup"
  end
end
