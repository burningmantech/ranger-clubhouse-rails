# frozen_string_literal: true

require "test_helper"

# Golden-master characterization of the scheduling-write decision tree as it stands
# BEFORE collapsing Scheduling::Management into the deep Scheduling::Signup module.
#
# It pins the verdict CLASS and the typed fields each branch of add_to_schedule /
# remove_from_schedule returns -- NOT the internal calls -- so the namespace move and
# clock injection are provably behaviour-preserving.
#
# There are no slot / person_event / setting / document fixtures, so slots are built
# programmatically (Slot.create! + update_columns, like the existing capacity / store
# characterization tests) and the Permission collaborators are stubbed with the same
# define_singleton_method pattern the controller test uses.
#
# Mgmt is the single seam under test. After the refactor this constant is repointed at
# Scheduling::Signup and the file must pass UNCHANGED.
class Scheduling::SignupCharacterizationTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActionMailer::TestHelper

  Mgmt = Scheduling::Management

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    @person = person(:active_ranger)
    Current.person = @person
    @position = positions(:council_manager)
    @year = Current.year

    @stubbed = []

    # Default permission double: everything allowed, no outstanding requirements.
    stub_permission(all: true, training: true, requirements: [])

    # Default collaborators for the post-permission gates. Individual tests override.
    stub_singleton(Agreements, :did_sign_document?) { |*_a, **_k| true }
    stub_singleton(VehicleEligibility, :is_mvr_eligible?) { |*_a, **_k| true }
  end

  teardown do
    # Unwind stubs LIFO: tests that re-stub a method push a second @stubbed entry whose
    # captured "original" is the earlier (setup) stub, not the real method. Restoring in
    # reverse order puts the genuine original back last and prevents cross-test leakage.
    @stubbed.reverse_each { |mod, name, original| mod.define_singleton_method(name, original) }
    PersonSlot.where(person_id: @person.id).delete_all
  end

  def stub_singleton(mod, name, &block)
    @stubbed << [mod, name, mod.method(name)]
    mod.define_singleton_method(name, &block)
  end

  def stub_permission(all:, training:, requirements:)
    permission = Object.new
    permission.define_singleton_method(:requirements) { requirements }
    permission.define_singleton_method(:all_signups_allowed) { all }
    permission.define_singleton_method(:training_signups_allowed) { training }
    stub_singleton(Scheduling::Permission, :new) { |*_args| permission }
  end

  # Build a slot for the held position with explicit counts (bypassing callbacks via
  # update_columns), like the existing characterization tests.
  def slot(position: @position, max: 10, signed_up: 0, begins: nil, ends: nil, &block)
    begins ||= Time.zone.local(@year, 8, 25, 10, 0, 0)
    ends ||= Time.zone.local(@year, 8, 25, 16, 0, 0)
    s = Slot.create!(
      position: position, begins: begins, ends: ends,
      max: max, active: true, timezone: "America/Los_Angeles"
    )
    s.update_columns(signed_up: signed_up)
    block&.call(s.position)
    s.reload
  end

  def add(slot, force = false) = Mgmt.add_to_schedule(@person, slot, force)
  def remove(slot, force = false) = Mgmt.remove_from_schedule(@person, slot, force)

  # ===== add: gate ordering =====

  test "(a) NoPosition when the person does not hold the slot's position" do
    other = positions(:khaki_supervisor) # active_ranger holds khaki_supervisor too...
    # ...so build against a position the person does NOT hold: mentor_lead.
    not_held = positions(:mentor_lead)
    assert_not PersonPosition.have_position?(@person.id, not_held.id)
    result = add(slot(position: not_held))
    assert_instance_of Scheduling::Verdict::NoPosition, result.verdict
    assert_equal "Mentor Lead", result.verdict.position_title
  end

  test "(b) AlreadyExists when already signed up for the slot" do
    s = slot
    PersonSlot.create!(person_id: @person.id, slot_id: s.id)
    result = add(s)
    assert_instance_of Scheduling::Verdict::AlreadyExists, result.verdict
  end

  test "(c) Accepted happy path on a plain slot" do
    s = slot(max: 10, signed_up: 3)
    result = add(s)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::Accepted, verdict
    assert_not verdict.is_full
    assert_equal 10, verdict.combined_max
    assert_equal 4, verdict.signed_up
    assert_nil verdict.mvr
    assert PersonSlot.exists?(person_id: @person.id, slot_id: s.id)
  end

  test "(d) Full when the slot is at capacity and not forced" do
    result = add(slot(max: 5, signed_up: 5))
    assert_instance_of Scheduling::Verdict::Full, result.verdict
  end

  test "(e) MissingRequirements when the permission gate fails" do
    stub_permission(all: false, training: false, requirements: [Scheduling::MISSING_BPGUID])
    result = add(slot)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::MissingRequirements, verdict
    assert_equal [Scheduling::MISSING_BPGUID], verdict.requirements
    assert_equal false, verdict.may_force
    assert_equal false, verdict.training_signups_allowed
  end

  # Formerly a pinned latent bug: decide_add called can_join_training_slot? /
  # multiple_enrollments? BARE, so this branch raised NoMethodError before it
  # could build a verdict -- which 500'd every add to a prevention-enabled
  # training or ALPHA slot. Fixed 2026-07-31 (training session management
  # port) by routing both calls at Scheduling::Query; the branch now yields
  # the MultipleEnrollment verdict it always intended.
  test "(f) a second ALPHA enrollment yields a MultipleEnrollment verdict" do
    alpha = alpha_position
    first = slot(position: alpha)
    PersonSlot.create!(person_id: @person.id, slot_id: first.id)

    second = slot(
      position: alpha,
      begins: Time.zone.local(@year, 8, 26, 10, 0, 0),
      ends: Time.zone.local(@year, 8, 26, 16, 0, 0)
    )

    result = add(second)
    verdict = result.verdict

    assert_instance_of Scheduling::Verdict::MultipleEnrollment, verdict
    assert_equal [first.id], verdict.slots.map(&:id)
    assert_not PersonSlot.have_slot?(@person.id, second.id)
  end

  test "(g) sandman gate -> MissingRequirements when affidavit unsigned and not forced" do
    sandman = sandman_position
    stub_singleton(Agreements, :did_sign_document?) { |*_a, **_k| false }
    result = add(slot(position: sandman))
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::MissingRequirements, verdict
    assert_equal [Scheduling::MISSING_SIGNED_SANDMAN_AFFIDAVIT], verdict.requirements
  end

  test "(h) mvr -> Accepted carrying MvrInfo when position is mvr_signup_eligible and not yet eligible" do
    s = slot { |pos| pos.update_columns(mvr_signup_eligible: true) }
    deadline = Time.zone.local(@year, 8, 1, 23, 59, 59)
    stub_singleton(VehicleEligibility, :is_mvr_eligible?) { |*_a, **_k| false }
    stub_singleton(VehicleEligibility, :retrieve_mvr_deadline) { |*_a| [deadline, false] }
    result = add(s)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::Accepted, verdict
    assert_not_nil verdict.mvr
    assert_equal deadline, verdict.mvr.deadline
    assert_equal false, verdict.mvr.past_deadline
  end

  test "(j) OutsideWindow on add when the slot has started and not forcing" do
    started = slot(
      begins: Time.zone.local(@year, 4, 16, 8, 0, 0),
      ends: Time.zone.local(@year, 4, 16, 16, 0, 0)
    )
    assert started.has_started
    result = add(started)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::OutsideWindow, verdict
    assert_equal false, verdict.ended
    assert_equal false, verdict.may_force
  end

  test "(i) force path: an admin forces a started, at-capacity slot to Accepted" do
    grant_role(Role::ADMIN)
    started_full = slot(
      max: 1, signed_up: 1,
      begins: Time.zone.local(@year, 4, 16, 8, 0, 0),
      ends: Time.zone.local(@year, 4, 16, 16, 0, 0)
    )
    assert started_full.has_started
    result = add(started_full, true)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::Accepted, verdict
    assert verdict.has_started
    assert verdict.is_full
  end

  # ===== add: training session full =====
  #
  # These run the mail job itself: a call the mailer cannot answer only fails
  # there, after the sign-up has already gone through.

  test "(l) taking the last seat in a training session emails the position's contact" do
    s = slot(max: 2, signed_up: 1) do |pos|
      pos.update_columns(type: Position::TYPE_TRAINING, contact_email: "training@example.com")
    end

    assert_emails 1 do
      perform_enqueued_jobs { add(s) }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal ["training@example.com"], mail.to
    assert_includes mail.body.to_s, "<b>Signups:</b> 2<br>"
  end

  # Sent from a job, where nobody is signed in, so whoever made the sign-up
  # travels with it -- the signed-in person, who need not be the one who took
  # the seat.
  test "(l) the training-full email is logged under whoever made the last sign-up" do
    s = slot(max: 2, signed_up: 1) do |pos|
      pos.update_columns(type: Position::TYPE_TRAINING, contact_email: "training@example.com")
    end

    add(s)
    Current.person = nil
    perform_enqueued_jobs

    assert_equal @person.id, MailLog.find_by!(to_email: "training@example.com").sender_id
  end

  # Two sign-ups reach the per-trainer max of 2, but two trainers make room for 4.
  test "(l) a training session with seats left sends nothing, counting every trainer's seats" do
    trainers = slot(signed_up: 2)
    s = slot(max: 2, signed_up: 1) do |pos|
      pos.update_columns(type: Position::TYPE_TRAINING, contact_email: "training@example.com")
    end
    s.update_columns(trainer_slot_id: trainers.id)

    assert_no_emails do
      perform_enqueued_jobs { add(s) }
    end
  end

  # ===== remove =====

  test "(k) remove: Removed on a real signup" do
    s = slot
    PersonSlot.create!(person_id: @person.id, slot_id: s.id)
    s.update_columns(signed_up: 1)
    result = remove(s.reload)
    assert_instance_of Scheduling::Verdict::Removed, result.verdict
    assert_not PersonSlot.exists?(person_id: @person.id, slot_id: s.id)
  end

  test "(k) remove: MissingSignup when not signed up" do
    result = remove(slot)
    assert_instance_of Scheduling::Verdict::MissingSignup, result.verdict
  end

  test "(k) remove: OutsideWindow when started and not forcing" do
    started = slot(
      begins: Time.zone.local(@year, 4, 16, 8, 0, 0),
      ends: Time.zone.local(@year, 4, 16, 16, 0, 0)
    )
    PersonSlot.create!(person_id: @person.id, slot_id: started.id)
    result = remove(started.reload, false)
    verdict = result.verdict
    assert_instance_of Scheduling::Verdict::OutsideWindow, verdict
    assert_equal false, verdict.ended
    # Plain non-trainer/non-ALPHA slot: only ADMIN may force, which this person is not.
    assert_equal false, verdict.may_force
  end

  private

  # Build (or reuse) a Sandman position the person holds, on the well-known id so the
  # is_sandman_shift branch fires.
  def sandman_position
    pos = Position.find_or_create_by!(id: Position::SANDMAN) do |p|
      p.title = "Sandman"
      p.active = true
    end
    PersonPosition.find_or_create_by!(person_id: @person.id, position_id: pos.id)
    pos
  end

  # Build (or reuse) the ALPHA position with multiple-enrollment prevention, held by
  # the person, so the ALPHA multiple-enrollment branch fires.
  def alpha_position
    pos = Position.find_or_create_by!(id: Position::ALPHA) do |p|
      p.title = "Alpha"
      p.active = true
    end
    pos.update_columns(prevent_multiple_enrollments: true)
    PersonPosition.find_or_create_by!(person_id: @person.id, position_id: pos.id)
    pos
  end

  def grant_role(role_id)
    rm = Object.new
    rm.define_singleton_method(:has_role?) { |role| Array(role).include?(role_id) }
    Current.roles_manager = rm
  end
end
