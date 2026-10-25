# frozen_string_literal: true

require "test_helper"

# The Alpha Mentor Assignments worksheet. The data layer is covered by
# AlphaMentorAssignmentTest; these assertions concentrate on what the controller
# and the form add: the two filters, the keyed-hash wire format, the 422
# re-renders (validation, the bonk confirmation, and the pod fill), and the
# print sheet.
class Mentoring::AlphaMentorAssignmentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include TrainingSlotTestHelper
  include PersonTestFactory
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to record mentor assignments."

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor",
                                        type: Position::TYPE_MENTORING, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 8, 0, 0),
                                         description: "Saturday Day")
    @other_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 27, 8, 0, 0),
                                               description: "Sunday Day")

    @alpha = create_person("Zebra", status: Person::ALPHA)
    @second_alpha = create_person("DustBunny", status: Person::ALPHA)
    @mentor_one = create_person("Firecracker")
    @mentor_two = create_person("HotShot")
    [@mentor_one, @mentor_two].each do |person|
      PersonPosition.create!(person_id: person.id, position_id: Position::MENTOR)
    end

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # The fixtures carry an Alpha of their own, so row assertions intersect
  # against only the people this test made.
  def my_row_ids
    mine = [@alpha, @second_alpha].map { |person| "assignment-row-#{person.id}" }
    css_select("tbody tr").filter_map { |row| row["id"] } & mine
  end

  def row_params(person, status:, mentor_ids: [])
    padded = mentor_ids.map(&:to_s) + [""] * (AlphaMentorAssignment::MENTOR_SLOTS - mentor_ids.size)
    [person.id.to_s, { status:, mentor_ids: padded }]
  end

  # -------------------------------------------------------------- authorization

  test "requires the admin or mentor role" do
    sign_in_as(@outsider)

    get mentoring_alpha_mentor_assignments_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "a mentor may open the worksheet" do
    sign_in_as(@mentor)

    get mentoring_alpha_mentor_assignments_path

    assert_response :success
  end

  test "the save is gated by the same role" do
    sign_in_as(@outsider)

    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path,
           params: { alphas: [row_params(@alpha, status: PersonMentor::STATUS_PASS,
                                         mentor_ids: [@mentor_one.id])].to_h }
    end

    assert_redirected_to me_root_path
  end

  # -------------------------------------------------------------------- index

  test "the worksheet lists current Alphas with a select per mentor slot" do
    get mentoring_alpha_mentor_assignments_path

    assert_response :success
    assert_equal ["assignment-row-#{@second_alpha.id}", "assignment-row-#{@alpha.id}"], my_row_ids
    assert_select "select[name='alphas[#{@alpha.id}][mentor_ids][]']", AlphaMentorAssignment::MENTOR_SLOTS
    assert_select "select[name='alphas[#{@alpha.id}][status]']", 1
  end

  test "the worksheet renders no duplicate DOM ids" do
    get mentoring_alpha_mentor_assignments_path

    assert_response :success
    assert_unique_dom_ids
  end

  test "the page says a result here does not change the account status" do
    get mentoring_alpha_mentor_assignments_path

    assert_response :success
    assert_match(/does not change anyone's account status/, response.body.squish)
  end

  test "the stat boxes count the whole roster, not the filtered rows" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    get mentoring_alpha_mentor_assignments_path(status: AlphaMentorAssignment::STATUS_PASSED)

    assert_response :success
    assert_equal ["assignment-row-#{@alpha.id}"], my_row_ids

    # The discriminating box: the filter shows one row, but Still pending must
    # still report every unrecorded Alpha on the roster (the fixtures carry one
    # of their own, hence the query rather than a literal).
    pending = Person.where(status: Person::ALPHA).count - 1
    assert_select "div", text: "Still Pending" do |labels|
      assert_equal "#{pending}Still Pending", labels.first.parent.text.strip
    end
    assert_select "div", text: "Passed" do |labels|
      assert_equal "1Passed", labels.first.parent.text.strip
    end
  end

  test "the page ignores a year parameter" do
    get mentoring_alpha_mentor_assignments_path(year: 2019)

    assert_response :success
    assert_select "#mentor-assignments-header", text: /#{YEAR} Alpha Mentor Assignments/
  end

  # ------------------------------------------------------------------ filters

  test "the pending filter wants a mentor picked, not merely an untouched row" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    get mentoring_alpha_mentor_assignments_path(
      status: AlphaMentorAssignment::STATUS_PENDING_WITH_MENTORS
    )

    assert_response :success
    assert_equal ["assignment-row-#{@alpha.id}"], my_row_ids
  end

  test "the bonked filter matches plain bonks as well as self-bonks" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person: @second_alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_SELF_BONK)

    get mentoring_alpha_mentor_assignments_path(status: AlphaMentorAssignment::STATUS_BONKED)

    assert_response :success
    assert_equal 2, my_row_ids.size, "upstream's filter silently drops plain bonks"
  end

  test "a signed-up shift filter narrows to that shift's Alphas" do
    PersonSlot.create!(person_id: @alpha.id, slot_id: @slot.id)
    PersonSlot.create!(person_id: @second_alpha.id, slot_id: @other_slot.id)

    get mentoring_alpha_mentor_assignments_path(
      shift: "#{AlphaMentorAssignment::SIGNED_UP_PREFIX}#{@slot.id}"
    )

    assert_response :success
    assert_equal ["assignment-row-#{@alpha.id}"], my_row_ids
  end

  test "the not-checked-in filter drops anyone signed in to an Alpha shift" do
    Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id, slot_id: @slot.id,
                      on_duty: Current.time - 1.hour, additional_notes: "signed in")

    get mentoring_alpha_mentor_assignments_path(shift: AlphaMentorAssignment::SHIFT_NOT_CHECKED_IN)

    assert_response :success
    assert_equal ["assignment-row-#{@second_alpha.id}"], my_row_ids
  end

  test "filters that match no one say so" do
    get mentoring_alpha_mentor_assignments_path(status: AlphaMentorAssignment::STATUS_PASSED)

    assert_response :success
    assert_select "tbody tr", false
    assert_match "No Alphas matched those filters", response.body
  end

  # --------------------------------------------------------------------- save

  test "a sheet with a bonk saves and redirects back to the same filtered view" do
    post mentoring_alpha_mentor_assignments_path, params: {
      status: AlphaMentorAssignment::STATUS_PASSED,
      shift: AlphaMentorAssignment::ALL_FILTER,
      alphas: [
        row_params(@alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor_one.id]),
        row_params(@second_alpha, status: PersonMentor::STATUS_BONK, mentor_ids: [@mentor_two.id])
      ].to_h
    }

    assert_redirected_to mentoring_alpha_mentor_assignments_path(
      status: AlphaMentorAssignment::STATUS_PASSED, shift: AlphaMentorAssignment::ALL_FILTER
    )
    assert_equal PersonMentor::STATUS_PASS,
                 PersonMentor.find_by(person_id: @alpha.id, mentor_year: YEAR).status
    assert_equal PersonMentor::STATUS_BONK,
                 PersonMentor.find_by(person_id: @second_alpha.id, mentor_year: YEAR).status
  end

  test "all passes and no bonks asks before recording anything" do
    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path, params: {
        alphas: [row_params(@alpha, status: PersonMentor::STATUS_PASS,
                            mentor_ids: [@mentor_one.id])].to_h
      }
    end

    assert_response :unprocessable_entity
    assert_match "No bonks on this sheet?", response.body
    assert_select "input[name=confirmed]"
  end

  test "the confirmed submit records the sheet" do
    post mentoring_alpha_mentor_assignments_path, params: {
      confirmed: "1",
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PASS,
                          mentor_ids: [@mentor_one.id])].to_h
    }

    assert_redirected_to mentoring_alpha_mentor_assignments_path(
      status: AlphaMentorAssignment::ALL_FILTER, shift: AlphaMentorAssignment::ALL_FILTER
    )
    assert_equal 1, PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR).count
  end

  test "the confirmation step keeps the edits that were typed" do
    post mentoring_alpha_mentor_assignments_path, params: {
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PASS,
                          mentor_ids: [@mentor_one.id])].to_h
    }

    assert_response :unprocessable_entity
    row = css_select("#assignment-row-#{@alpha.id}").first.to_s
    assert_match(/option selected="selected" value="#{@mentor_one.id}"/, row)
    assert_match(/option selected="selected" value="#{PersonMentor::STATUS_PASS}"/, row)
  end

  test "a duplicate mentor is refused and the whole sheet is left unwritten" do
    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path, params: {
        confirmed: "1",
        alphas: [
          row_params(@alpha, status: PersonMentor::STATUS_PASS,
                     mentor_ids: [@mentor_one.id, @mentor_one.id]),
          row_params(@second_alpha, status: PersonMentor::STATUS_BONK, mentor_ids: [@mentor_two.id])
        ].to_h
      }
    end

    assert_response :unprocessable_entity
    assert_match "Nothing Was Recorded", response.body
    # Scoped to the offending row's error line, not the whole page: an assertion
    # against the body would pass no matter which row the message landed on.
    assert_select "#assignment-error-#{@alpha.id}", /same mentor is listed twice/
    assert_select "#assignment-error-#{@second_alpha.id}", false,
                  "the innocent row carries no error"
  end

  test "a result with no mentor is refused rather than silently dropped" do
    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path, params: {
        alphas: [row_params(@second_alpha, status: PersonMentor::STATUS_BONK)].to_h
      }
    end

    assert_response :unprocessable_entity
    assert_match(/at least one mentor/, response.body)
  end

  test "blanking every mentor clears that Alpha's assignments" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    post mentoring_alpha_mentor_assignments_path, params: {
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PENDING)].to_h
    }

    assert_response :redirect
    assert_empty PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR)
  end

  # The list replaces the stored mentors, so junk dropped would read as blanked
  # and clear the row. to_i refused it only because 0 was no one's mentor. The
  # pass beside it would raise the No Bonks question first, and its redraw would
  # show the row blank with no error; the refusal has to come before it.
  test "a mentor list holding something that is not an id is refused rather than clearing the row" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PENDING)

    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path, params: {
        alphas: [
          row_params(@alpha, status: PersonMentor::STATUS_PENDING, mentor_ids: ["abc"]),
          row_params(@second_alpha, status: PersonMentor::STATUS_PASS, mentor_ids: [@mentor_two.id])
        ].to_h
      }
    end

    assert_response :unprocessable_entity
    assert_select "#assignment-error-#{@alpha.id}", /not submitted correctly/
    assert PersonMentor.exists?(person_id: @alpha.id, mentor_id: @mentor_one.id, mentor_year: YEAR)
  end

  test "a save with no rows at all is refused with a message" do
    post mentoring_alpha_mentor_assignments_path

    assert_redirected_to mentoring_alpha_mentor_assignments_path(
      status: AlphaMentorAssignment::ALL_FILTER, shift: AlphaMentorAssignment::ALL_FILTER
    )
    assert_equal "No Alphas were listed, so there was nothing to record.", flash[:alert]
  end

  test "a hand-edited row for someone who is not an Alpha writes nothing" do
    ranger = create_person("Interloper", status: Person::ACTIVE)

    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_path, params: {
        confirmed: "1",
        alphas: [row_params(ranger, status: PersonMentor::STATUS_PASS,
                            mentor_ids: [@mentor_one.id])].to_h
      }
    end

    assert_response :redirect
  end

  # -------------------------------------------------------------- pod prefill

  test "the pod fill puts the pod's mentors into blank slots without saving" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor_one)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    assert_no_difference "PersonMentor.count" do
      post mentoring_alpha_mentor_assignments_pod_prefill_path, params: {
        pod_slot_id: @slot.id,
        alphas: [row_params(@alpha, status: PersonMentor::STATUS_PENDING)].to_h
      }
    end

    assert_response :unprocessable_entity
    assert_match "Mentors Filled In from Pods", response.body
    assert_match(/option selected="selected" value="#{@mentor_one.id}"/,
                 css_select("#assignment-row-#{@alpha.id}").first.to_s)
  end

  test "the pod fill leaves an Alpha who already has a mentor alone and says so" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@mentor_one)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)

    post mentoring_alpha_mentor_assignments_pod_prefill_path, params: {
      pod_slot_id: @slot.id,
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PENDING,
                          mentor_ids: [@mentor_two.id])].to_h
    }

    assert_response :unprocessable_entity
    assert_match "already had a mentor", response.body
    assert_match(/option selected="selected" value="#{@mentor_two.id}"/,
                 css_select("#assignment-row-#{@alpha.id}").first.to_s)
  end

  test "the pod fill refuses a shift that is not one of this year's Alpha walks" do
    post mentoring_alpha_mentor_assignments_pod_prefill_path, params: { pod_slot_id: 0 }

    assert_response :redirect
    assert_equal "Pick one of this year's Alpha shifts to fill mentors from.", flash[:alert]
  end

  # Filled from pods, a mentor list that is not ids would come back as the ids
  # it kept, with no error, and the save after it would remove the rest.
  test "the pod fill refuses a sheet whose mentor list is not ids" do
    post mentoring_alpha_mentor_assignments_pod_prefill_path, params: {
      pod_slot_id: @slot.id,
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PENDING, mentor_ids: ["abc"])].to_h
    }

    assert_response :redirect
    assert_equal "The mentors were not submitted correctly, so nothing was filled in. Try again.", flash[:alert]
  end

  # The control stays on the page before any pod exists. Hiding it until pods
  # are formed made the whole feature look missing at the start of a season.
  test "the pod control lists every Alpha shift, pods or not" do
    get mentoring_alpha_mentor_assignments_path

    assert_response :success
    assert_select "input[type=submit][value='Assign Mentors from Pods']"
    assert_select "select[name=pod_slot_id] option", 2
    assert_select "select[name=pod_slot_id] option", text: /Saturday Day \(no pods yet\)/

    Pod.create_alpha_set!(@slot)
    get mentoring_alpha_mentor_assignments_path

    assert_select "select[name=pod_slot_id] option", text: /Saturday Day \(1 pod\)/
  end

  test "picking a shift with no pods says so instead of reporting an empty fill" do
    post mentoring_alpha_mentor_assignments_pod_prefill_path, params: {
      pod_slot_id: @slot.id,
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PENDING)].to_h
    }

    assert_response :unprocessable_entity
    assert_match "That Shift Has No Pods Yet", response.body
    assert_no_match(/Mentors Filled In from Pods/, response.body)
    assert_select "a[href=?]", mentoring_alpha_pods_path(year: YEAR)
  end

  # --------------------------------------------------------------- print sheet

  test "the print sheet renders the filtered rows on the print layout" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    get mentoring_alpha_mentor_assignments_print_path(status: AlphaMentorAssignment::STATUS_PASSED)

    assert_response :success
    assert_select "nav", false, "the print layout carries no navigation"
    assert_select "select", false, "the sheet is a readout, not a worksheet"
    assert_select "tbody tr", 1, "the filter reached the paper, not just the screen"
    assert_no_match(/DustBunny/, response.body, "the filtered-out Alpha is off the sheet")
    assert_match "Firecracker", response.body
    assert_match "Passed", response.body
  end

  test "the sheet carries the active filters so a save returns to the same view" do
    PersonMentor.create!(person: @alpha, mentor: @mentor_one, mentor_year: YEAR,
                         status: PersonMentor::STATUS_PASS)

    get mentoring_alpha_mentor_assignments_path(status: AlphaMentorAssignment::STATUS_PASSED)

    assert_response :success
    assert_select "form[method=post] input[type=hidden][name=status][value=?]",
                  AlphaMentorAssignment::STATUS_PASSED
    assert_select "form[method=post] input[type=hidden][name=shift][value=?]",
                  AlphaMentorAssignment::ALL_FILTER
  end

  test "a filter value that is not a scalar falls back to all rather than raising" do
    get mentoring_alpha_mentor_assignments_path, params: { shift: ["x"], status: { a: "b" } }

    assert_response :success
    assert_select "tbody tr"
  end

  test "a junk filter on the save path still redirects cleanly" do
    post mentoring_alpha_mentor_assignments_path, params: {
      confirmed: "1", shift: ["x"],
      alphas: [row_params(@alpha, status: PersonMentor::STATUS_PASS,
                          mentor_ids: [@mentor_one.id])].to_h
    }

    assert_redirected_to mentoring_alpha_mentor_assignments_path(
      status: AlphaMentorAssignment::ALL_FILTER, shift: AlphaMentorAssignment::ALL_FILTER
    )
    assert_equal 1, PersonMentor.where(person_id: @alpha.id, mentor_year: YEAR).count
  end
end
