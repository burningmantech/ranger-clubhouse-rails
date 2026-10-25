# frozen_string_literal: true

require "test_helper"

class Person::WorkHistoryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper
  include ReportCardTestHelper # card_answer / assert_no_card_question

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @timesheet_manager = person(:ranger_with_custom_gender)
    @trainer = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@timesheet_manager, Role::TIMESHEET_MANAGEMENT)
    grant_role(@trainer, Role::TRAINER)

    Current.person = @admin
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "index is denied to the person-page roles without timesheet access" do
    sign_in_as(@trainer)

    get person_work_history_path(@target)

    assert_redirected_to me_root_path
  end

  test "index succeeds for an authorized role and renders the history table" do
    sign_in_as(@event_manager)

    get person_work_history_path(@target)

    assert_response :success
    assert_select "td", text: /OOD \(Officer of the Day\)/
    # Fixture totals for active_ranger: 6h + 12h (OOD, 2023) + 8h (Mentor Lead, 2024) = 26h.
    assert_select "td", text: "26.00"
  end

  test "index links the hour figures to the person's drill-downs" do
    sign_in_as(@event_manager)

    get person_work_history_path(@target)

    ood = positions(:ood_position).id
    assert_select "td a[href=?]", person_work_history_entire_year_path(@target, year: 2023)
    assert_select "td a[href=?]", person_work_history_position_all_path(@target, position_id: ood)
    assert_select "td a[href=?]", person_work_history_position_summary_path(@target, position_id: ood, year: 2023)
  end

  # "How do I see where the hours went?" is about the table's cells, so it goes
  # when the table does. What the page leaves out is said either way.
  test "the card explains the hour links only when there is a table of them" do
    question = "How do I see where the hours went?"
    sign_in_as(@event_manager)

    get person_work_history_path(@target)

    assert_match(/breakdown/, card_answer(question))

    Timesheet.where(person_id: @target.id).delete_all
    get person_work_history_path(@target)

    assert_select "body", text: /No countable timesheet entries were found/
    assert_match(/positions are excluded/, card_answer("What positions are excluded?"))
    assert_no_card_question question
  end

  test "Alpha, Deep Freeze, and Training positions are excluded from the totals" do
    alpha = ensure_position(Position::ALPHA, "Alpha")
    deep_freeze = ensure_position(Position::DEEP_FREEZE, "Deep Freeze")

    create_timesheet!(position: alpha, on_duty: Time.zone.local(2025, 8, 25, 8, 0, 0),
                      off_duty: Time.zone.local(2025, 8, 25, 14, 0, 0))
    create_timesheet!(position: deep_freeze, on_duty: Time.zone.local(2025, 1, 2, 8, 0, 0),
                      off_duty: Time.zone.local(2025, 1, 2, 14, 0, 0))
    create_timesheet!(position: positions(:training_lead), on_duty: Time.zone.local(2025, 6, 1, 8, 0, 0),
                      off_duty: Time.zone.local(2025, 6, 1, 14, 0, 0))

    sign_in_as(@event_manager)
    get person_work_history_path(@target)

    assert_response :success
    assert_select "td", text: /\AAlpha\z/, count: 0
    assert_select "td", text: /\ADeep Freeze\z/, count: 0
    assert_select "td", text: /Training Lead/, count: 0
    # The excluded entries contribute no hours to the grand total.
    assert_select "td", text: "26.00"
  end

  test "an entry before 2008 is inaccurate and excluded from years" do
    create_timesheet!(position: positions(:ood_position), on_duty: Time.zone.local(1999, 8, 28, 10, 0, 0),
                      off_duty: Time.zone.local(1999, 8, 28, 16, 0, 0))

    sign_in_as(@event_manager)
    get person_work_history_path(@target)

    assert_response :success
    assert_match(/timesheet entries before 2008/, response.body)
    assert_select "th", text: "1999", count: 0
  end

  test "position_all renders a breakdown page with the position's years" do
    sign_in_as(@event_manager)

    get person_work_history_position_all_path(@target, position_id: positions(:ood_position).id)
    assert_response :success
    assert_match(/OOD \(Officer of the Day\)/, response.body)
    assert_match(/Event Year 2023/, response.body)
  end

  test "entire_year renders a breakdown page with that year's entries across positions" do
    sign_in_as(@event_manager)

    get person_work_history_entire_year_path(@target, year: 2023)
    assert_response :success
    assert_match(/2023 All Positions/, response.body)
    assert_match(/OOD \(Officer of the Day\)/, response.body)
  end

  test "position_summary renders a breakdown page with that cell's entries" do
    sign_in_as(@event_manager)

    get person_work_history_position_summary_path(@target, position_id: positions(:ood_position).id, year: 2023)
    assert_response :success
    assert_match(/2023 OOD \(Officer of the Day\)/, response.body)
  end

  test "drill-downs are denied to the person-page roles without timesheet access" do
    sign_in_as(@trainer)

    get person_work_history_entire_year_path(@target, year: 2023)
    assert_redirected_to me_root_path
  end

  test "drill-downs return unprocessable for a position or year with no entries" do
    sign_in_as(@event_manager)

    get person_work_history_position_all_path(@target, position_id: 999_999)
    assert_response :unprocessable_entity

    get person_work_history_entire_year_path(@target, year: 1900)
    assert_response :unprocessable_entity
  end

  private

  def create_timesheet!(position:, on_duty:, off_duty:, person: @target)
    entry = Timesheet.new(person_id: person.id, position_id: position.id,
                          on_duty: on_duty, off_duty: off_duty, review_status: Timesheet::STATUS_VERIFIED)
    entry.save!(validate: false)
    entry
  end

  def ensure_position(id, title)
    Position.find_or_create_by!(id: id) do |p|
      p.title = title
      p.active = true
    end
  end
end
