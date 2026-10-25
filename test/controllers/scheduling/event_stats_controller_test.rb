# frozen_string_literal: true

require "test_helper"

class Scheduling::EventStatsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ReportCardTestHelper # assert_report_card / card_answer / assert_no_card_question
  include ActiveSupport::Testing::TimeHelpers

  # Clear of the timesheet fixtures, which occupy 2023-2025, and above the 2010
  # floor.
  YEAR = 2031
  # Two pairs in the About This Report card that come and go with the figure
  # they explain, one found by its question and one by its answer. Each is
  # spelled once: a test that expects one gone would keep passing against
  # wording that had merely changed.
  TRAINING_QUESTION = "Who counts as finishing a training?"
  ON_SITE_ANSWER = /only has an answer for the current year/

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EDIT_SLOTS, "Edit Slots")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    # Edit Slots reads the shift reports beside this page and must not read this
    # one.
    grant_role(@outsider, Role::EDIT_SLOTS)

    @training = Position.create!(id: Position::TRAINING, title: "Training",
                                 type: Position::TYPE_TRAINING, active: true)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def pass_training!(person, position: @training, year: YEAR)
    slot = create_slot(position, begins: Time.zone.local(year, 8, 1, 9, 0, 0))
    TraineeStatus.create!(person:, slot:, status: TraineeStatus::STATUS_PASSED)
  end

  # A second training, so the headline count has two rows to merge across.
  def art
    @art ||= Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                              type: Position::TYPE_TRAINING, active: true)
  end

  test "an admin sees the page" do
    get scheduling_event_stats_path(year: YEAR)

    assert_response :success
    assert_select "h1", text: /#{YEAR} Event Statistics/
  end

  # The four headline numbers are what the page is for, and the view picks each
  # one out of the report itself -- a badge pointed at the wrong field passes
  # every other assertion here.
  test "the headline counts name the four numbers the page leads with" do
    # One person through both trainings, so the rows sum to two while the
    # people come to one. A headline reading the rows instead of the people
    # would say 2 here, which is the whole point of the count being its own.
    pass_training!(person(:active_ranger))
    pass_training!(person(:active_ranger), position: art)

    get scheduling_event_stats_path(year: YEAR)

    assert_response :success
    ["People Rangered", "Timesheet Entries", "Alphas Passed"].each do |label|
      assert_select "div.rounded-lg.p-3.text-center", text: /#{label}/, minimum: 1,
                                                      message: "no headline count for #{label}"
    end
    assert_select "div.rounded-lg.p-3.text-center", text: /1People Trained/, minimum: 1
    assert_select "div.rounded-lg.p-3.text-center", text: /2People Trained/, count: 0,
                                                    message: "the headline counted rows, not people"
  end

  test "event management sees the page" do
    sign_in_as(@event_manager)
    get scheduling_event_stats_path(year: YEAR)

    assert_response :success
  end

  test "edit slots does not see the page" do
    sign_in_as(@outsider)
    get scheduling_event_stats_path(year: YEAR)

    assert_response :redirect
  end

  test "the year comes from the query string" do
    get scheduling_event_stats_path(year: YEAR - 1)

    assert_response :success
    assert_select "h1", text: /#{YEAR - 1} Event Statistics/
  end

  test "a year with nothing recorded says so" do
    get scheduling_event_stats_path(year: YEAR - 2)

    assert_response :success
    assert_select "body", text: /Nothing was recorded for #{YEAR - 2}/
  end

  test "the training table lists each training that trained somebody" do
    pass_training!(person(:active_ranger))

    get scheduling_event_stats_path(year: YEAR)

    assert_response :success
    assert_select "th[scope=row]", text: "In-Person Training"
  end

  # The table brings its own answers into the card. This is the current year,
  # so the on site count is a number and needs no note.
  test "the card explains the training table, and the current year gets no on site note" do
    pass_training!(person(:active_ranger))

    get scheduling_event_stats_path(year: YEAR)

    assert_report_card
    assert_not_empty card_answer(TRAINING_QUESTION)
    assert_select "details dd", text: ON_SITE_ANSWER, count: 0
  end

  test "a past year says the on site count has no answer" do
    # A past year with nothing in it renders the empty state instead, and the
    # note being checked lives in the card that only a year with something in
    # it has.
    slot = create_slot(positions(:ood_position),
                       begins: Time.zone.local(YEAR - 1, 8, 26, 18, 0, 0))
    PersonSlot.create!(person: person(:active_ranger), slot:)

    get scheduling_event_stats_path(year: YEAR - 1)

    assert_response :success
    assert_select "details dd", text: ON_SITE_ANSWER
    # No one finished a training that year, so there is no table to explain.
    assert_no_card_question TRAINING_QUESTION
  end
end
