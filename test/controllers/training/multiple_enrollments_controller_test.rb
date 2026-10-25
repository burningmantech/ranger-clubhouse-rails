# frozen_string_literal: true

require "test_helper"

# Training > Multiple Enrollments report: the shared view gate, the session-group
# rule (which deliberately diverges from upstream), the mentee-section gate, and
# the CSV export shape.
class Training::MultipleEnrollmentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 8, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::TRAINING, title: "Training",
                             type: Position::TYPE_TRAINING, active: true)
    @green_dot = Position.create!(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training",
                                  type: Position::TYPE_TRAINING, active: true)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")

    @trainer = person(:echelon_ranger)
    @art_trainer = person(:retired_ranger)
    @outsider = person(:inactive_ranger)

    grant_role(@trainer, Role::TRAINER)
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # Sign someone up for one session per description, a week apart.
  def enroll(person_record, *descriptions, position: @dirt)
    descriptions.each_with_index.map do |description, index|
      slot = create_slot(position, begins: Time.zone.local(YEAR, 6, 1 + (index * 7), 9, 0, 0),
                                   description:)
      PersonSlot.create!(person_id: person_record.id, slot_id: slot.id)
      slot
    end
  end

  test "someone in two ordinary sessions is listed with both" do
    enroll(person(:active_ranger), "Johnson Valley, CA", "Reno, NV")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "h1", text: /Training Multiple Enrollments/
    assert_select "th", text: "TestRanger"
    assert_select "td", text: /Johnson Valley, CA/
    assert_select "td", text: /Reno, NV/
  end

  test "someone in a single session is not listed" do
    enroll(person(:active_ranger), "Johnson Valley, CA")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger", count: 0
    assert_match "Congratulations!", response.body
  end

  # --- session groups: the deliberate divergence from upstream ---------------

  test "two halves of one multi-part session are not a double booking" do
    enroll(person(:active_ranger), "Pre-Event Part 1", "Pre-Event Part 2")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger", count: 0
  end

  # Upstream pairs slots off two at a time, so the unpaired third part flags the
  # person. Three parts are still one training.
  test "an odd-sized session group is not a double booking" do
    enroll(person(:active_ranger), "Pre-Event Part 1", "Pre-Event Part 2", "Pre-Event Part 3")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger", count: 0
  end

  # The other half of the same upstream defect: two COMPLETE groups pair off
  # entirely and escape the report, though the person really is double booked.
  test "two complete session groups are a double booking" do
    enroll(person(:active_ranger),
           "Pre-Event Part 1", "Pre-Event Part 2", "Post-Event Part 1", "Post-Event Part 2")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger"
    assert_select "td", text: "4", count: 1
  end

  # A part token mid-description leaves Slot.session_group_name nil; the report
  # strips the token in place instead of relying on nil == nil.
  test "a part token in the middle of a description still groups" do
    enroll(person(:active_ranger),
           "WAP/Part 1, Black Rock City, NV USA", "WAP/Part 2, Black Rock City, NV USA")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger", count: 0
  end

  # Real slots carry a NULL description. PHP coerces null to ""; Ruby raises in
  # Slot.session_group_part, so a faithful port would 500 here.
  test "a session with no description does not blow up the report" do
    slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: nil)
    PersonSlot.create!(person_id: person(:active_ranger).id, slot_id: slot.id)
    enroll(person(:active_ranger), "Reno, NV")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person")

    assert_response :success
    assert_select "th", text: "TestRanger"
    assert_match "(no description)", response.body
  end

  # --- sections --------------------------------------------------------------

  test "an ART with mentees gets a section per mentee position" do
    Position.create!(id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee", type: "Frontline")
    Position.create!(id: Position::SANCTUARY_MENTEE, title: "Green Dot Sanctuary Novice", type: "Frontline")

    sign_in_as(@art_trainer)
    get training_multiple_enrollments_path("green-dot")

    assert_response :success
    titles = css_select("[role=heading]").map { |node| node.text.sub(node.css(".badge").text, "").strip }
    assert_includes titles, "Green Dot Training"
    assert_includes titles, "Green Dot Mentee"
    assert_includes titles, "Green Dot Sanctuary Novice"
  end

  # Upstream appends a Sandman SHIFT section here, where several sign-ups are
  # normal -- 34-49 people a year, all noise. Gated on Training.has_mentees?.
  test "Sandman gets no shift section" do
    Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                     type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::SANDMAN, title: "Sandman", type: "Frontline")
    ensure_role(Role::ART_TRAINER_BASE | Position::SANDMAN_TRAINING, "Sandman Interface")
    grant_role(@art_trainer, Role::ART_TRAINER_BASE | Position::SANDMAN_TRAINING)

    sign_in_as(@art_trainer)
    get training_multiple_enrollments_path("sandman")

    assert_response :success
    titles = css_select("[role=heading]").map { |node| node.text.sub(node.css(".badge").text, "").strip }
    assert_includes titles, "Sandman Training"
    refute_includes titles, "Sandman"
  end

  # --- gate, empty state, export ---------------------------------------------

  test "the view gate matches the interface: ART trainers get their ART only" do
    sign_in_as(@art_trainer)

    get training_multiple_enrollments_path("green-dot")
    assert_response :success
    assert_select "h1", text: /Green Dot Training Multiple Enrollments/

    get training_multiple_enrollments_path("in-person")
    assert_redirected_to me_root_path
    assert_match(/not authorized/, flash[:error])
  end

  test "an unauthorized person is turned away" do
    sign_in_as(@outsider)

    get training_multiple_enrollments_path("in-person")
    assert_redirected_to me_root_path
  end

  test "a clean year congratulates and offers no export" do
    sign_in_as(@trainer)

    get training_multiple_enrollments_path("in-person", year: YEAR - 1)

    assert_response :success
    assert_match "Congratulations! No multiple enrollments were found for #{YEAR - 1}.", response.body
    assert_select "a[href=?]",
                  training_multiple_enrollments_path("in-person", year: YEAR - 1, format: :csv),
                  count: 0
  end

  test "the CSV carries one row per sign-up with sortable dates" do
    enroll(person(:active_ranger), "Johnson Valley, CA", "Reno, NV")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person", format: :csv)

    assert_response :success
    assert_match "2026-in-person-multiple-enrollments.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "Position,Callsign,First Name,Last Name,Email,Session,Date,Timezone", lines.first
    assert_equal "Training,TestRanger,Test,Ranger,testranger@example.com,\"Johnson Valley, CA\",2026-06-01 09:00,PDT",
                 lines.second
    assert_equal "Training,TestRanger,Test,Ranger,testranger@example.com,\"Reno, NV\",2026-06-08 09:00,PDT",
                 lines.third
    assert_equal 3, lines.size
  end

  # slot.begins is already local wall-clock; Slot#begins_adjusted converts it and
  # shifts any session outside the app zone. Pin the raw time against a Mountain
  # session, which begins_adjusted would push an hour late.
  test "the CSV date matches the page for a session outside the app timezone" do
    mountain = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 1, 17, 15, 0),
                                  description: "Littleton, CO", timezone: "America/Denver")
    PersonSlot.create!(person_id: person(:active_ranger).id, slot_id: mountain.id)
    enroll(person(:active_ranger), "Reno, NV")

    sign_in_as(@trainer)
    get training_multiple_enrollments_path("in-person", format: :csv)

    assert_response :success
    assert_match(/Littleton, CO",2026-06-01 17:15,MDT/, response.body)

    get training_multiple_enrollments_path("in-person")
    assert_select "a", text: /Jun 1 @ 17:15 \(MDT\)/
  end
end
