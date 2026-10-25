# frozen_string_literal: true

require "test_helper"

# Ticketing > Claimed, Didn't Ranger: who a claimed ticket puts on the list,
# what takes them back off it, and how the four yes/no columns read.
#
# The action reads the whole access_document, timesheet, person_slot, and
# person_online_course tables and the shared fixtures belong to other suites, so
# every test starts from empty tables and builds exactly the rows it needs.
class Ticketing::ClaimedWithNoSignupsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    # After the event: sign-ups have happened, training has ended, and shifts
    # have been rangered, so every column has something to say.
    travel_to Time.zone.local(YEAR, 9, 15, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @ticketing = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @other = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)
    grant_role(@ticketing, Role::EDIT_ACCESS_DOCS)

    AccessDocument.delete_all
    Timesheet.delete_all
    PersonSlot.delete_all
    PersonOnlineCourse.delete_all

    # No fixture position carries the ids the report looks for, and the
    # non-training exclusion reads position.type, so both are built here.
    @training = Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING)
    @trainer = Position.create!(id: Position::TRAINER, title: "Trainer", type: Position::TYPE_TRAINING)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look --------------------------------------------------------

  test "the report renders for an admin" do
    ticket_for(@admin)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
  end

  test "the report renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    ticket_for(@other)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@other.callsign], rendered_callsigns
  end

  test "the report is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_claimed_with_no_signups_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing reports.", flash[:error]
  end

  # --- who lands on the list ------------------------------------------------

  test "a claimed ticket with no course and no shifts is listed" do
    ticket_for(@admin)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal({ "Ticket Holders" => "1", "No Online Course" => "1", "No Shifts Rangered" => "1" },
                 rendered_stats)
  end

  test "a submitted ticket counts the same as a claimed one" do
    ticket_for(@admin, status: AccessDocument::SUBMITTED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
  end

  test "an unclaimed ticket holder is not listed" do
    ticket_for(@admin, status: AccessDocument::QUALIFIED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "a setup access pass is not a ticket" do
    ticket_for(@admin, type: AccessDocument::SAP)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  # --- what takes a person back off it --------------------------------------

  test "finishing the course and rangering a shift clears a person off the list" do
    ticket_for(@admin)
    completed_course(@admin)
    rangered(@admin)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "finishing the course alone is not enough" do
    ticket_for(@admin)
    completed_course(@admin)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal ["Yes", "No", "No", "No"], rendered_answers.first
  end

  test "rangering a shift alone is not enough" do
    ticket_for(@admin)
    rangered(@admin)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal ["No", "No", "Yes", "No"], rendered_answers.first
  end

  # Moodle sync writes the enrollment row when a person starts the course, so
  # the row alone says nothing about whether they finished.
  test "an unfinished course enrollment does not count as completed" do
    ticket_for(@admin)
    rangered(@admin)
    completed_course(@admin, completed_at: nil)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_equal ["No", "No", "Yes", "No"], rendered_answers.first
  end

  test "a course completed in another year does not count" do
    ticket_for(@admin)
    rangered(@admin)
    completed_course(@admin, year: YEAR - 1)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
  end

  # --- one row per person ---------------------------------------------------

  test "holding both a ticket and a credential is one row listing both" do
    spt = ticket_for(@admin)
    credential = ticket_for(@admin, type: AccessDocument::STAFF_CREDENTIAL,
                                    status: AccessDocument::SUBMITTED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_match "RAD-#{spt.id} SPT claimed", response.body
    assert_match "RAD-#{credential.id} SC submitted", response.body
  end

  # --- the sign-up column ---------------------------------------------------

  test "a late season shift counts as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, begins: Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "Yes", "No", "No"], rendered_answers.first
  end

  test "a shift before the cutoff does not count as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0))

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
  end

  # Turning up to be trained is not the same as turning up to ranger.
  test "a training session does not count as a sign-up" do
    ticket_for(@admin)
    sign_up(@admin, begins: Time.local(YEAR, 8, 20, 9, 0, 0), position: @training)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
  end

  # --- the training columns -------------------------------------------------

  test "passing a training session sets trained" do
    ticket_for(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    TraineeStatus.create!(person: @admin, slot:, status: TraineeStatus::STATUS_PASSED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "Yes"], rendered_answers.first
    assert_equal ["1 session"], rendered_session_summaries
    assert_match "passed", response.body
  end

  test "failing a training session does not set trained" do
    ticket_for(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    TraineeStatus.create!(person: @admin, slot:, status: TraineeStatus::STATUS_NOT_PASSED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
    assert_match "not passed", response.body
  end

  test "an ended session names a no-show, and reads one no one scored as not passed" do
    ticket_for(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    row = TraineeStatus.create!(person: @admin, slot:, status: TraineeStatus::STATUS_NO_SHOW)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
    assert_match "no-show", response.body

    row.update!(status: TraineeStatus::STATUS_PENDING)
    get ticketing_claimed_with_no_signups_path

    assert_match "not passed", response.body
  end

  test "a training session that has not happened yet reads as pending" do
    ticket_for(@admin)
    sign_up(@admin, begins: Time.local(YEAR, 10, 1, 9, 0, 0), position: @training)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
    assert_match "pending", response.body
  end

  test "attending as a trainer sets trained" do
    ticket_for(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @trainer)
    trainer_status(@admin, slot, TrainerStatus::STATUS_ATTENDED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "Yes"], rendered_answers.first
    assert_match "attended (as trainer)", response.body
  end

  test "a no-show trainer does not count as trained" do
    ticket_for(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @trainer)
    trainer_status(@admin, slot, TrainerStatus::STATUS_NO_SHOW)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["No", "No", "No", "No"], rendered_answers.first
    assert_match "no-show (as trainer)", response.body
  end

  test "trainee and trainer sessions share one list in start order" do
    ticket_for(@admin)
    taught = sign_up(@admin, begins: Time.local(YEAR, 8, 10, 9, 0, 0), position: @trainer)
    trainer_status(@admin, taught, TrainerStatus::STATUS_ATTENDED)
    trained = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    TraineeStatus.create!(person: @admin, slot: trained, status: TraineeStatus::STATUS_PASSED)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal ["2 sessions"], rendered_session_summaries
    assert_operator response.body.index("Sat Aug 1 @ 09:00"), :<, response.body.index("Mon Aug 10 @ 09:00")
  end

  # --- ordering and the empty case ------------------------------------------

  test "rows are sorted by callsign regardless of case" do
    ticket_for(@admin)
    ticket_for(@other)

    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_equal [@admin, @other].map(&:callsign).sort_by(&:downcase), rendered_callsigns
  end

  test "the empty report says so" do
    get ticketing_claimed_with_no_signups_path

    assert_response :success
    assert_match "Every ticket holder has finished the online course and rangered a shift", response.body
  end

  # --- filters --------------------------------------------------------------

  test "each filter narrows the table to the matching answer" do
    # @admin finished the course, signed up, and passed training. @other did
    # none of the three, so every filter separates the two.
    ticket_for(@admin)
    completed_course(@admin)
    sign_up(@admin, begins: Time.local(YEAR, 8, 20, 9, 0, 0))
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    TraineeStatus.create!(person: @admin, slot:, status: TraineeStatus::STATUS_PASSED)
    ticket_for(@other)

    { course: :oc_completed, signup: :has_signups, trained: :trained? }.each_key do |filter|
      get ticketing_claimed_with_no_signups_path(filter => "yes")

      assert_response :success
      assert_equal [@admin.callsign], rendered_callsigns, "#{filter}=yes should keep only the admin"

      get ticketing_claimed_with_no_signups_path(filter => "no")

      assert_response :success
      assert_equal [@other.callsign], rendered_callsigns, "#{filter}=no should keep only the other"
    end
  end

  test "the rangered filter separates a timesheet entry from none" do
    ticket_for(@admin)
    rangered(@admin)
    ticket_for(@other)

    get ticketing_claimed_with_no_signups_path(rangered: "yes")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
  end

  test "filters combine" do
    ticket_for(@admin)
    completed_course(@admin)
    ticket_for(@other)
    sign_up(@other, begins: Time.local(YEAR, 8, 20, 9, 0, 0))

    get ticketing_claimed_with_no_signups_path(course: "yes", signup: "no")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
  end

  # The header counts describe the whole report, so they hold still while the
  # filters narrow the table below them.
  test "the header counts ignore the filters and the bar reports the split" do
    ticket_for(@admin)
    completed_course(@admin)
    ticket_for(@other)

    get ticketing_claimed_with_no_signups_path(course: "yes")

    assert_response :success
    assert_equal({ "Ticket Holders" => "2", "No Online Course" => "1", "No Shifts Rangered" => "2" },
                 rendered_stats)
    assert_match "Showing 1 of 2 ticket holders", response.body
  end

  test "an active filter gets a chip that drops just that filter" do
    ticket_for(@admin)

    get ticketing_claimed_with_no_signups_path(course: "no", trained: "no")

    assert_response :success
    assert_equal ["Online Course: No", "Trained: No"], rendered_chips
    # Each chip drops only its own filter, and "Clear all" drops both.
    assert_select "a[href=?]", ticketing_claimed_with_no_signups_path(trained: "no")
    assert_select "a[href=?]", ticketing_claimed_with_no_signups_path(course: "no")
    assert_select "a[href=?]", ticketing_claimed_with_no_signups_path, text: "Clear All Filters"
  end

  # A hand-edited URL should not leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  test "an unknown filter value is ignored" do
    ticket_for(@admin)

    get ticketing_claimed_with_no_signups_path(course: "maybe")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_empty rendered_chips
  end

  test "filtering everything out says so rather than claiming there is nothing to chase" do
    ticket_for(@admin)

    get ticketing_claimed_with_no_signups_path(course: "yes")

    assert_response :success
    assert_empty rendered_callsigns
    assert_match "No ticket holders matched those filters", response.body
  end

  test "the csv export carries the active filters" do
    ticket_for(@admin)
    completed_course(@admin)
    ticket_for(@other)

    get ticketing_claimed_with_no_signups_path(course: "yes", format: :csv)

    assert_response :success
    lines = response.body.split("\n")
    assert_equal 2, lines.size
    assert_equal @admin.callsign, lines.second.split(",").first
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the rows under the expected filename" do
    ticket = ticket_for(@admin)
    rangered(@admin)
    slot = sign_up(@admin, begins: Time.local(YEAR, 8, 1, 9, 0, 0), position: @training)
    TraineeStatus.create!(person: @admin, slot:, status: TraineeStatus::STATUS_PASSED)

    get ticketing_claimed_with_no_signups_path(format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-claimed-tickets-no-signups.csv"),
                 response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Callsign,Status,Email,First Name,Last Name,Preferred Name,Tickets," \
                 "OC Completed?,Has Sign-Ups?,Rangered?,Trained?,Training Sessions",
                 lines.first
    assert_equal 2, lines.size
    assert_equal [@admin.callsign, @admin.status, @admin.email, @admin.first_name, @admin.last_name,
                  @admin.preferred_name, "RAD-#{ticket.id} SPT claimed",
                  "N", "N", "Y", "Y", "Sat Aug 1 @ 09:00 passed"].join(","),
                 lines.second
  end

  private

  # A claimed special price ticket by default: the plainest reason to appear.
  # delivery_method is spelled out because the column is NOT NULL and the model
  # only fills it in on a status change, as the fixtures do.
  def ticket_for(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE,
                           expiry_date: "#{YEAR + 3}-09-15")
  end

  # Timesheets are stored as machine-local wall clock, so shifts are built the
  # same way the report builds its year boundary. additional_notes is required
  # by the model's audit trail on every create.
  def rangered(person, year: YEAR)
    on_duty = Time.local(year, 8, 28, 10, 0, 0)
    Timesheet.create!(person:, position: positions(:ood_position), on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "test shift")
  end

  def sign_up(person, begins:, position: positions(:ood_position))
    slot = Slot.create!(position:, begins:, ends: begins + 4.hours, max: 10, active: true)
    PersonSlot.create!(person:, slot:)
    slot
  end

  # slot_id is the session being taught, trainer_slot_id the trainer's own
  # sign-up; this report reads the latter.
  def trainer_status(person, slot, status)
    TrainerStatus.create!(person:, slot:, trainer_slot: slot, status:)
  end

  def completed_course(person, year: YEAR, completed_at: Time.local(YEAR, 7, 1, 12, 0, 0))
    PersonOnlineCourse.create!(person:, year:, position_id: Position::TRAINING,
                               online_course: online_course(:training_all_2026),
                               completed_at:)
  end

  # The stat row above the table, as { label => value }.
  def rendered_stats
    css_select("div.rounded-lg.p-3.text-center").to_h do |box|
      parts = box.css("div")
      [parts.last.text.strip, parts.first.text.strip]
    end
  end

  # The callsign heading each rendered row of the table.
  def rendered_callsigns
    css_select("tbody th").map { |cell| cell.text.strip }
  end

  # The four yes/no columns per row, in table order: online course, signed up,
  # rangered, trained.
  def rendered_answers
    css_select("tbody tr").map { |row| row.css("td")[3..6].map { |cell| cell.css(".badge").text.strip } }
  end

  # The filter bar's removable chips, in order.
  def rendered_chips
    css_select("a[aria-label^='Remove filter']").map { |chip| chip.css("span").text.strip }
  end

  def rendered_session_summaries
    css_select("tbody tr").map { |row| row.css("td")[7].css("summary").text.strip }
  end
end
