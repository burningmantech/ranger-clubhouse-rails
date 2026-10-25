# frozen_string_literal: true

require "application_system_test_case"

# Next Unread in the HQ window (slice 6 of .scratch/messaging-rework/PRD.md):
# the operator hands over a person's unread messages one after another, and
# looking never marks one read. At the window's width the next thread loads into
# the pane like a row's link, and the list's mark follows it; with none left the
# button leads back to the list.
class Hq::MessagesNextUnreadTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  REVIEW_PANE = "[data-controller~=review-pane]"

  setup do
    @operator = person(:ranger_with_custom_gender)
    @ranger = person(:active_ranger)
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@operator, Role::SHIFT_MANAGEMENT)
    # The HQ shell's training lookup falls back to this position.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    @newest = deliver("Lost radio", 1.minute.ago)
    @older = deliver("Camp tour", 1.hour.ago)
  end

  teardown do
    Current.reset
  end

  test "Next Unread loads the next unread thread into the pane, round to the first, then back to the list" do
    sign_in(@operator)
    visit hq_message_path(@ranger, @newest)
    # The shell warns once per person that the operator is on no shift.
    within("dialog[open]") { click_on "Close" }
    wait_for_controller "review-pane", REVIEW_PANE
    assert_selector "turbo-frame#messages-pane:not([disabled])", visible: :all
    # A page visit replaces <body>, which drops this; a frame visit keeps it.
    page.execute_script("document.querySelector('#{REVIEW_PANE}').dataset.kept = 'yes'")

    click_on "Next Unread"

    assert_selector "aside.review-pane [data-review-id='#{@older.id}']", text: "Camp tour"
    assert_selector "#{REVIEW_PANE}[data-kept=yes]"
    assert_selector "a.review-line[data-review-id='#{@older.id}'][aria-current=true]"
    assert_current_path hq_message_path(@ranger, @older, folder: PersonMessage::FOLDER_INBOX)

    # Handed over and marked read, the next is the one before it.
    click_on "Mark Read"
    assert_selector "#messages-panel-header", text: "Mark Unread"
    click_on "Next Unread"
    assert_selector "aside.review-pane [data-review-id='#{@newest.id}']", text: "Lost radio"

    click_on "Mark Read"
    click_on "Back to Messages"
    assert_current_path hq_messages_path(@ranger, folder: PersonMessage::FOLDER_INBOX)
    assert_text "Select a conversation to read it here."
  end

  # Review finding 15: beside the summary column the list was 308px (19.2rem)
  # at the window tablet's landscape 1180, and 245px at 1024.
  test "where the list would be under 20rem the pane drops under it, and beside it from there" do
    sign_in(@operator)
    { 1180 => true, 1440 => false }.each do |width, stacked|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width:, height: 900, deviceScaleFactor: 1,
                                                                             mobile: false)
      visit hq_messages_path(@ranger)
      within("dialog[open]") { click_on "Close" } if page.has_css?("dialog[open]", wait: 2)
      wait_for_controller "review-pane", REVIEW_PANE
      columns = page.evaluate_script(<<~JS)
        (() => {
          const list = document.querySelector("[data-review-pane-target=list]").getBoundingClientRect()
          const pane = document.querySelector("[data-review-pane-target=pane]").getBoundingClientRect()
          return {listRem: list.width / parseFloat(getComputedStyle(document.documentElement).fontSize),
                  under: pane.top >= list.bottom}
        })()
      JS

      assert_equal stacked, columns["under"], "at #{width}px"
      assert_operator columns["listRem"], :>=, 20, "at #{width}px"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def deliver(subject, created_at)
    PersonMessage.create!(person: @ranger, sender_person: person(:retired_ranger), creator_person: person(:retired_ranger),
                          sender_type: PersonMessage::SENDER_TYPE_PERSON, subject:, body: "#{subject}?", created_at:)
  end
end
