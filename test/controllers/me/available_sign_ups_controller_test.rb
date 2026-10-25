# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Characterization of the available_sign_ups#create / #destroy verdict TYPE dispatch.
# There was no controller-level coverage of this mapping before; these tests lock the
# @message / @status / @modal each Scheduling::Verdict resolves to, so the migration
# from status-string decoding to verdict-class dispatch is provably output-preserving.
#
# Scheduling::Management / Query / Permission are swapped with plain-Ruby stubs (mocha
# is not available in this project) so the dispatch can be exercised against each
# verdict in isolation, independent of the DB write path.
class Me::AvailableSignUpsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TrainingSlotTestHelper

  setup do
    @person = person(:active_ranger)
    @position = positions(:council_manager)
    @slot = Slot.create!(
      position: @position,
      begins: Time.zone.local(Current.year, 8, 25, 10, 0, 0),
      ends: Time.zone.local(Current.year, 8, 25, 16, 0, 0),
      max: 10, active: true, timezone: "America/Los_Angeles"
    )
    sign_in_as(@person)

    @stubbed = []

    # No outstanding requirements, so retrieve_permission_and_recommendation does not redirect.
    permission = Object.new
    permission.define_singleton_method(:requirements) { [] }
    permission.define_singleton_method(:training_signups_allowed) { true }
    permission.define_singleton_method(:all_signups_allowed) { true }
    stub_singleton(Scheduling::Permission, :new) { |*_args| permission }

    stub_singleton(Scheduling::Query, :find_for_query) { |*_args, **_kw| [[], []] }
  end

  teardown do
    # Unwind stubs LIFO: re-stubbing a method pushes a second @stubbed entry whose captured
    # "original" is the earlier (setup) stub, not the real method. Restoring in reverse order
    # puts the genuine original back last and prevents cross-test leakage.
    @stubbed.reverse_each { |mod, name, original| mod.define_singleton_method(name, original) }
  end

  def stub_singleton(mod, name, &block)
    @stubbed << [mod, name, mod.method(name)]
    mod.define_singleton_method(name, &block)
  end

  def post_create
    post me_available_sign_up_slot_path(position_id: @position.id, slot_id: @slot.id),
         as: :turbo_stream
  end

  def delete_destroy
    delete me_available_sign_up_slot_path(position_id: @position.id, slot_id: @slot.id),
           as: :turbo_stream
  end

  def stub_add(verdict)
    result = Scheduling::Signup::SignupResult.from(verdict)
    stub_singleton(Scheduling::Signup, :add) { |*_args, **_kw| result }
  end

  def stub_remove(verdict)
    result = Scheduling::Signup::SignupResult.from(verdict)
    stub_singleton(Scheduling::Signup, :remove) { |*_args, **_kw| result }
  end

  # --- create dispatch ----------------------------------------------------

  test "Accepted with no extra info shows success toast and no modal" do
    stub_add(accepted(linked_slots_became_full: false, linked_slots: []))
    post_create
    assert_response :success
    assert_match "Shift added.", response.body
    assert_match "toast-success", response.body
    assert_no_match(/slot_additional_info/, response.body)
    assert_no_match(/target="modal"/, response.body)
  end

  test "Accepted with linked_slots_became_full opens slot_additional_info_modal" do
    stub_add(accepted(linked_slots_became_full: true, linked_slots: [linked_slot]))
    post_create
    assert_match "Shift added.", response.body
    assert_match "Linked Shifts Now Full", response.body
    assert_match(/target="modal"/, response.body)
  end

  test "Accepted that is MVR eligible opens slot_additional_info_modal" do
    mvr = Scheduling::Verdict::MvrInfo.new(
      deadline: Time.zone.local(Current.year, 8, 1, 12, 0, 0),
      past_deadline: false, signed_motorpool_agreement: true
    )
    stub_add(accepted(linked_slots_became_full: false, linked_slots: [], mvr: mvr))
    post_create
    assert_match "Shift added.", response.body
    assert_match "MVR", response.body
    assert_match(/target="modal"/, response.body)
  end

  test "Full shows the become-full error toast" do
    stub_add(Scheduling::Verdict::Full.new(may_force: false))
    post_create
    assert_match "Sorry, the shift has become full.", response.body
    assert_match "toast-error", response.body
  end

  test "AlreadyExists shows the previously-added warning toast" do
    stub_add(Scheduling::Verdict::AlreadyExists.new)
    post_create
    assert_match "The shift was previously added.", response.body
    assert_match "toast-warning", response.body
  end

  test "OutsideWindow (started) on create shows the started error toast" do
    stub_add(Scheduling::Verdict::OutsideWindow.new(ended: false, may_force: false))
    post_create
    assert_match "The shift has started", response.body
    assert_match "toast-error", response.body
  end

  test "OutsideWindow (ended) on create shows the ended error toast" do
    stub_add(Scheduling::Verdict::OutsideWindow.new(ended: true, may_force: false))
    post_create
    assert_match "The shift has ended", response.body
    assert_match "toast-error", response.body
  end

  test "MissingRequirements dispatches to and renders the missing_requirements_modal" do
    stub_add(Scheduling::Verdict::MissingRequirements.new(
               requirements: [Scheduling::OC_IS_NOT_COMPLETED], may_force: false, training_signups_allowed: true
             ))
    post_create
    assert_equal "common/scheduling/missing_requirements_modal",
                 @controller.instance_variable_get(:@modal)
    assert_nil @controller.instance_variable_get(:@message)
    # create.turbo_stream passes { result:, slot:, person: }; the modal must tolerate the
    # extra slot: and person: locals and render rather than raising StrictLocalsError.
    assert_match "Missing Sign Up Prerequisite", response.body
    assert_match(/target="modal"/, response.body)
  end

  # The branch pointed at a bare "multiple_enrollment_modal" that no directory held, so a
  # refused second enrollment raised MissingTemplate instead of saying why.
  test "MultipleEnrollment dispatches to and renders the multiple_enrollment_modal" do
    enrolled = create_slot(@position, begins: Time.zone.local(Current.year, 8, 26, 10),
                                      description: "Council Shift One")
    stub_add(Scheduling::Verdict::MultipleEnrollment.new(slots: [enrolled], may_force: false))
    post_create
    assert_equal "common/scheduling/multiple_enrollment_modal",
                 @controller.instance_variable_get(:@modal)
    assert_nil @controller.instance_variable_get(:@message)
    assert_match "Already Signed Up", response.body
    assert_match "You are already signed up", response.body
    assert_match "Council Shift One", response.body
    assert_match EmailAddresses::VOLUNTEER_COORDINATORS_TEAM, response.body
    assert_match(/target="modal"/, response.body)
  end

  test "MultipleEnrollment on a Training slot sends the person to the Training Academy" do
    @position = Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end
    PersonPosition.find_or_create_by!(person: @person, position: @position)
    @slot = create_slot(@position, begins: Time.zone.local(Current.year, 8, 27, 10))
    stub_add(Scheduling::Verdict::MultipleEnrollment.new(slots: [@slot], may_force: false))
    post_create
    assert_match "Only one In-Person Training session may be signed up for.", response.body
    assert_match EmailAddresses::TRAINING_ACADEMY, response.body
    assert_no_match EmailAddresses::VOLUNTEER_COORDINATORS_TEAM, response.body
  end

  test "Failed renders the unknown-status error toast" do
    stub_add(Scheduling::Verdict::Failed.new(status: Scheduling::STATUS_DB_FAILURE))
    post_create
    assert_match "Unknown status [#{Scheduling::STATUS_DB_FAILURE}]", response.body
    assert_match "toast-error", response.body
  end

  # --- destroy dispatch ---------------------------------------------------

  test "Removed shows the success toast" do
    stub_remove(Scheduling::Verdict::Removed.new)
    delete_destroy
    assert_match "Shift removed.", response.body
    assert_match "toast-success", response.body
  end

  test "OutsideWindow (started) on destroy shows the started error toast" do
    stub_remove(Scheduling::Verdict::OutsideWindow.new(ended: false, may_force: true))
    delete_destroy
    assert_match "The shift has started and cannot be removed from the schedule.", response.body
    assert_match "toast-error", response.body
  end

  test "OutsideWindow (ended) on destroy shows the ended error toast" do
    stub_remove(Scheduling::Verdict::OutsideWindow.new(ended: true, may_force: true))
    delete_destroy
    assert_match "The shift has ended and cannot be removed from the schedule.", response.body
    assert_match "toast-error", response.body
  end

  test "MissingSignup shows the not-signed-up error toast" do
    stub_remove(Scheduling::Verdict::MissingSignup.new)
    delete_destroy
    assert_match "The shift was not signed up for.", response.body
    assert_match "toast-error", response.body
  end

  test "Failed on destroy renders the unknown-status error toast" do
    stub_remove(Scheduling::Verdict::Failed.new(status: Scheduling::STATUS_DB_FAILURE))
    delete_destroy
    assert_match "Unknown status [#{Scheduling::STATUS_DB_FAILURE}]", response.body
    assert_match "toast-error", response.body
  end

  # The Training row stays a link without the Online Course: #show renders a
  # preview (below), so the row only carries a note (ruled 2026-10-22).
  test "index links the training row with a note when the online course is not complete" do
    stub_training_signups(allowed: false)

    get me_available_sign_up_path

    assert_response :success
    assert_select "a[href*='sign-ups/position/#{Position::TRAINING}']", count: 1
    assert_select "[aria-disabled]", count: 0
    assert_match "Complete the Online Course to sign up", response.body
  end

  test "index links the training row without the note once the online course is complete" do
    stub_training_signups(allowed: true)

    get me_available_sign_up_path

    assert_response :success
    assert_select "a[href*='sign-ups/position/#{Position::TRAINING}']", count: 1
    assert_no_match "Complete the Online Course to sign up", response.body
  end

  # ------------------------------------------------- training preview

  # Without the Online Course the Training page warns, then shows the shift
  # cards; the by-month preview lives on the applicant's schedule page.
  test "show warns and renders the shift cards without the online course" do
    stub_training_entries(allowed: false)

    get me_available_sign_up_position_path(@position.id)

    assert_response :success
    assert_select "h2", text: "Online Course Required"
    assert_select "turbo-frame[id^='slot_']", count: 4
    assert_select "[role=heading]", text: /sign-up/, count: 0
    assert_no_match "No Walk-Ins", response.body
  end

  test "show renders the full shift cards once the online course is complete" do
    stub_training_entries(allowed: true)

    get me_available_sign_up_position_path(@position.id)

    assert_response :success
    assert_select "h2", text: "Online Course Required", count: 0
    assert_select "turbo-frame[id^='slot_']", count: 4
    assert_match "No Walk-Ins", response.body
  end

  test "show renders the full shift cards for a past year without the online course" do
    stub_training_entries(allowed: false)

    get me_available_sign_up_position_path(@position.id, year: Current.year - 1)

    assert_response :success
    assert_select "h2", text: "Online Course Required", count: 0
    # A past year shows only its past section, so the upcoming slots' frames are absent.
    assert_select "turbo-frame[id^='slot_']", count: 2
  end

  # ------------------------------------------------- scheduling headers

  test "show prints the ranger header to a Ranger" do
    @position.update!(ranger_scheduling_header: "<p>Bring <strong>water</strong></p>",
                      applicant_scheduling_header: "<p>Welcome</p>")

    get me_available_sign_up_position_path(@position.id)

    assert_response :success
    assert_select "h2", text: "#{@position.title} Information"
    assert_select ".lexxy-content strong", text: "water"
    assert_select ".lexxy-content", text: /Welcome/, count: 0
  end

  # The scrubber drops the element and keeps its words (contact_mailer_test
  # pins the same for strip_tags), so the proof is "no script element", not
  # "no trace of it".
  test "show prints the applicant header to a Prospective, with the script element stripped" do
    @position.update!(ranger_scheduling_header: "<p>Bring water</p>",
                      applicant_scheduling_header: "<p>Welcome</p><script>alert(1)</script>")
    sign_in_as_holder(person(:prospective_ranger))

    get me_available_sign_up_position_path(@position.id)

    assert_response :success
    assert_select ".lexxy-content", text: /Welcome/
    assert_select ".lexxy-content script", count: 0
    assert_select ".lexxy-content", text: /Bring water/, count: 0
  end

  test "show prints no header above a past year's shifts" do
    @position.update!(ranger_scheduling_header: "<p>Bring water</p>")

    get me_available_sign_up_position_path(@position.id, year: Current.year - 1)

    assert_response :success
    assert_select "#position-shifts-header", text: /#{Current.year - 1}/
    assert_select ".lexxy-content", count: 0
  end

  test "show prints no header to anyone else" do
    @position.update!(ranger_scheduling_header: "<p>Bring water</p>", applicant_scheduling_header: "<p>Welcome</p>")
    sign_in_as_holder(person(:auditor_ranger))

    get me_available_sign_up_position_path(@position.id)

    assert_response :success
    assert_select ".lexxy-content", count: 0
  end

  private

  # show turns away anyone who does not hold the position.
  def sign_in_as_holder(person)
    PersonPosition.find_or_create_by!(person:, position: @position)
    sign_in_as(person)
  end

  # Puts a single Training position on the index with the course requirement
  # either met or outstanding.
  def stub_training_signups(allowed:)
    permission = Object.new
    permission.define_singleton_method(:requirements) { [] }
    permission.define_singleton_method(:training_signups_allowed) { allowed }
    permission.define_singleton_method(:all_signups_allowed) { true }
    stub_singleton(Scheduling::Permission, :new) { |*_args| permission }

    training = OpenStruct.new(id: Position::TRAINING, title: "In-Person Training",
                              slot_count: 2, sign_ups: 0)
    stub_singleton(Scheduling::Query, :find_for_query) { |*_args, **_kw| [[], [training]] }
  end

  # Signs the Ranger in as a Training holder and answers find_for_query with two
  # upcoming and two past Training sessions, 40 days either side of today so the
  # two months always differ. The upcoming pair arrives out of alphabetical
  # order; the past pair shares one description.
  def stub_training_entries(allowed:)
    @position = Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end
    sign_in_as_holder(@person)

    @upcoming_slot = create_slot(@position, begins: 40.days.from_now, description: "Reno - Second Half")
    later_slot = create_slot(@position, begins: 41.days.from_now, description: "Berkeley - Full Day")
    @past_slot = create_slot(@position, begins: 40.days.ago, description: "Oakland - Full Day")
    earlier_slot = create_slot(@position, begins: 41.days.ago, description: "Oakland - Full Day")
    entries = [earlier_slot, @past_slot, @upcoming_slot, later_slot].map do |slot|
      Scheduling::Query::ScheduleEntry.new.tap do |entry|
        entry.slot = slot
        entry.position = @position
        entry.position_id = @position.id
        entry.person_assigned = false
        entry.credits = 0
        entry.max_base = entry.max_effective = slot.max
      end
    end

    permission = Object.new
    permission.define_singleton_method(:requirements) { [] }
    permission.define_singleton_method(:training_signups_allowed) { allowed }
    permission.define_singleton_method(:all_signups_allowed) { true }
    stub_singleton(Scheduling::Permission, :new) { |*_args| permission }
    stub_singleton(Scheduling::Query, :find_for_query) { |*_args, **_kw| [entries, []] }
  end

  def accepted(linked_slots_became_full:, linked_slots:, mvr: nil)
    Scheduling::Verdict::Accepted.new(
      is_full: false, combined_max: 10, linked_slots: linked_slots,
      linked_slots_became_full: linked_slots_became_full, signed_up: 1, mvr: mvr
    )
  end

  def linked_slot
    OpenStruct.new(slot: @slot, signed_up: 10, max: 10)
  end
end
