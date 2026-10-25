# frozen_string_literal: true

require "application_system_test_case"

# An announcement was drawn inside a Turbo Frame, and a frame takes over the
# links inside it: one that points at another Clubhouse page asked that page for
# the frame, found none, and the reader got an error where the page should be.
# Only a browser can show that, or that Mark as Read needs no frame.
class Me::AnnouncementLinksTest < ApplicationSystemTestCase
  setup do
    @announcement = motd(:ranger_announcement)
    @announcement.update_column(:message, %(<p>Sign up on <a href="#{me_directory_path}">the directory page</a>.</p>))

    sign_in(person(:active_ranger))
  end

  test "a link in an announcement opens the page it points at" do
    visit me_announcements_path

    within "##{ActionView::RecordIdentifier.dom_id(@announcement)}" do
      click_on "the directory page"
    end

    assert_current_path me_directory_path
    assert_selector "h1", text: "Cadre Directory"
  end

  test "marking an announcement as read redraws it in place" do
    visit me_announcements_path

    within "##{ActionView::RecordIdentifier.dom_id(@announcement)}" do
      click_on "Mark as Read"
      assert_selector "a", text: "Mark as Unread"
    end

    assert_current_path me_announcements_path
  end
end
