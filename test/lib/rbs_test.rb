# frozen_string_literal: true

require "test_helper"
# turbo-rails includes it into every test case only once Action Cable has loaded,
# which can be after this file is read.
require "turbo/broadcastable/test_helper"
require "active_job/continuation/test_helper"

# The Ranger Broadcast System: who each kind of broadcast reaches, what sending
# one records, and what sending the failures again does.
class RbsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper
  include ActiveJob::Continuation::TestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include SesTestHelper
  include CacheTestHelper
  include EnvTestHelper
  include EmailSuppressionTestHelper
  include FakeTwilioTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @sender = person(:active_ranger)
    Current.person = @sender
    Current.roles_manager = RoleManager.retrieve(@sender)

    @year = Current.year
    @event_start, @event_end = Rbs.event_dates
  end

  teardown do
    Current.reset
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  # A Ranger who can be reached by both text and email unless told otherwise.
  #
  # Copied from the fixture rather than built from scratch: an account carries
  # more required detail than a broadcast cares about, and none of it is what
  # these tests are checking.
  def reachable(callsign:, status: Person::ACTIVE, sms: nil, verified: true, stopped: false,
                on_site: false)
    @sms_counter = (@sms_counter || 0) + 1
    copy = person(:active_ranger).dup
    copy.assign_attributes(
      callsign:, callsign_normalized: callsign.downcase, callsign_soundex: callsign.upcase,
      first_name: callsign, last_name: "Test", email: "#{callsign.downcase}@example.com",
      bpguid: "#{callsign}-GUID", status:, status_date: Current.today,
      sms_number: sms.nil? ? "+1415555#{format("%04d", @sms_counter)}" : sms,
      sms_verified: verified, sms_stopped: stopped, on_site:
    )
    copy.save!(validate: false) unless copy.save
    copy
  end

  # Someone who is on a shift right now. A timesheet entry always has to say
  # why it was made, whoever made it.
  def on_shift(person)
    Timesheet.create!(person_id: person.id, position_id: positions(:ood_position).id,
                      on_duty: Current.time - 1.hour,
                      additional_notes: "Signed in for a broadcast test")
  end

  # A shift during the event, which is what makes someone count as on site.
  def event_slot(position, begins: @event_start + 2.days)
    Slot.create!(position:, begins: begins.to_time + 9.hours, ends: begins.to_time + 17.hours,
                 description: "Test shift", max: 10, begins_year: begins.year, active: true)
  end

  def sign_up(person, slot)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
  end

  def callsigns(people)
    people.map(&:callsign).sort
  end

  # Runs the block with Twilio set up and faked and the jobs it queues
  # performed, so a broadcast's texts go out through the fake. Returns the
  # fake: created_texts holds every text Twilio was asked for.
  def through_twilio(fake = FakeTwilioClient.new, &)
    configure_twilio
    with_fake_twilio(fake) { perform_enqueued_jobs(&) }
    fake
  end

  # Everything a broadcast's texts came to, one status per row.
  def text_statuses(broadcast)
    BroadcastMessage.where(broadcast_id: broadcast.id, address_type: "sms").pluck(:status)
  end

  def general_texts_criteria
    { alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE], on_site: false, attending: false,
      training: Rbs::TRAINING_ANY, send_sms: true, send_email: false, send_clubhouse: false }
  end

  def send_general_text
    Rbs.transmit(type: Broadcast::TYPE_GENERAL, sender: @sender, criteria: general_texts_criteria,
                 message: { sms_message: "Hello", subject: nil, message: nil, expires_at: nil })
  end

  # A broadcast aimed at a position that exactly one new Ranger holds, so a
  # count is about them and not about the Rangers the fixtures already hold.
  def only_listener(send_sms: false, send_email: false, send_clubhouse: false)
    listening("Listener")
    listener_criteria(send_sms:, send_email:, send_clubhouse:)
  end

  # Someone holding the position only_listener aims at.
  def listening(callsign)
    reachable(callsign:).tap do |person|
      PersonPosition.create!(person_id: person.id, position_id: positions(:ood_position).id)
    end
  end

  # Everyone holding that position, over the channels asked for.
  def listener_criteria(send_sms: false, send_email: false, send_clubhouse: false)
    { alert_id: Alert::SHIFT_MUSTER, statuses: [Person::ACTIVE],
      position_ids: [positions(:ood_position).id], position_signed_up: Rbs::SIGNED_UP_ANY,
      send_sms:, send_email:, send_clubhouse: }
  end

  # Stands in for one of Rbs's own private methods for a block, then puts the
  # real one back -- private, as it was.
  def standing_in_for(name, stand_in)
    original = Rbs.method(name)
    Rbs.define_singleton_method(name, &stand_in)
    yield
  ensure
    Rbs.define_singleton_method(name, original)
    Rbs.singleton_class.send(:private, name)
  end

  # Writing down the first batch picks chooses raises, as a dropped connection
  # would; every other batch is written by the real method. Picks is handed
  # each batch's outcomes, and by default chooses the first batch of all.
  def losing_batch(name = :record_email_batch, picks: ->(_outcomes) { true }, &)
    record = Rbs.method(name)
    lost = false
    lose_once = lambda do |*args|
      if !lost && picks.call(args.last)
        lost = true
        raise ActiveRecord::StatementInvalid, "lost"
      end
      record.call(*args)
    end
    standing_in_for(name, lose_once, &)
  end

  # Records the waits between SES calls instead of sleeping through them.
  def without_pacing
    waits = []
    pace = lambda do |last_call|
      waits << last_call if last_call
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    standing_in_for(:pace, pace) { yield waits }
  end

  # An SES client that cannot be built, as on a server with no AWS settings.
  def without_ses_account(&)
    standing_in_for(:ses_client, -> { raise Aws::Errors::MissingRegionError }, &)
  end

  def set_send_rate(value)
    Setting.find_or_initialize_by(name: Setting::SES_MAX_SEND_RATE).update!(value:)
  end

  # An email-only broadcast to everyone listening.
  def send_email(subject: "Hello", message: "Body")
    Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria: listener_criteria(send_email: true),
                 message: { sms_message: nil, subject:, message:, expires_at: nil })
  end

  # A broadcast whose one email to this person failed, ready to send again.
  def failed_email(person, address: person.email, status: Broadcast::STATUS_SERVICE_FAIL)
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE, subject: "Hello",
                                  email_message: "Body", recipient_count: 1, sent_email: true, email_failed: 1)
    [broadcast, failed_row(broadcast, person, status, address:)]
  end

  # One more email of this broadcast that did not go, and why.
  def failed_row(broadcast, person, status, address: person.email)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: person.id, address_type: "email",
                             address:, direction: "outbound", status:)
  end

  # A broadcast whose one text to this person did not go.
  def failed_text(person)
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE, sms_message: "Try again",
                                  subject: "Try again", recipient_count: 1, sent_sms: true, sms_failed: 1)
    [broadcast, failed_text_row(broadcast, person)]
  end

  # One more text of this broadcast that did not go, to the number given.
  def failed_text_row(broadcast, person, address: person.sms_number)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: person.id, address_type: "sms",
                             address:, direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)
  end

  def send_again(broadcast)
    perform_enqueued_jobs { Rbs.retry_broadcast(broadcast, @sender.id) }
  end

  def email_row(broadcast, person)
    BroadcastMessage.find_by!(broadcast_id: broadcast.id, person_id: person.id, address_type: "email")
  end

  # The one row a new-message alert recorded for this person over a channel.
  def alert_row(person, address_type = "email")
    BroadcastMessage.where(person_id: person.id, address_type:).sole
  end

  # ==========================================================================
  # Who a broadcast reaches
  # ==========================================================================

  test "a general broadcast reaches active Rangers who can be reached" do
    wanted = reachable(callsign: "Wanted")
    reachable(callsign: "Rested", status: Person::RETIRED)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)

    assert_includes callsigns(people), wanted.callsign
    assert_not_includes callsigns(people), "Rested"
  end

  test "chosen statuses decide who a general broadcast reaches" do
    reachable(callsign: "StillActive")
    retiree = reachable(callsign: "Retiree", status: Person::RETIRED)
    # The fixtures hold Rangers of their own, so the test asks who was picked
    # up and who was left out rather than for the whole list.

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::RETIRED],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)

    assert_includes callsigns(people), retiree.callsign
    assert_not_includes callsigns(people), "StillActive"
  end

  test "a status that never receives messages is left out even when it is chosen" do
    reachable(callsign: "TheAuditor", status: Person::AUDITOR)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::AUDITOR],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)

    assert_empty people
  end

  # The on-site rule is the one every on-playa broadcast leans on, and it is
  # invisible in the result unless someone who is not on site is left out.
  test "asking for people on site leaves out the people who are not" do
    here = reachable(callsign: "OnSite", on_site: true)
    reachable(callsign: "AtHome")

    criteria = { alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                 attending: false, training: Rbs::TRAINING_ANY, send_sms: true, send_email: true }

    everyone = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL, criteria.merge(on_site: false))
    on_site = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL, criteria.merge(on_site: true))

    assert_includes callsigns(everyone), "AtHome"
    assert_includes callsigns(on_site), here.callsign
    assert_not_includes callsigns(on_site), "AtHome"
  end

  test "a shift during the event counts as being on site" do
    signed_up = reachable(callsign: "SignedUp")
    sign_up(signed_up, event_slot(positions(:ood_position)))

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: true, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)

    assert_includes callsigns(people), signed_up.callsign
  end

  # Passed wants a pass this year; registered, any trainee status row; no
  # training, neither.
  test "the training choice narrows a general broadcast by this year's in-person training" do
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    session = event_slot(training)
    passer = reachable(callsign: "Passer")
    flunker = reachable(callsign: "Flunker")
    reachable(callsign: "Untrained")
    TraineeStatus.create!(person: passer, slot: session, status: TraineeStatus::STATUS_PASSED)
    TraineeStatus.create!(person: flunker, slot: session, status: TraineeStatus::STATUS_NOT_PASSED)

    reached = lambda do |choice|
      people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                       alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                       on_site: false, attending: false, training: choice,
                                       send_sms: true, send_email: true)
      callsigns(people) & %w[Flunker Passer Untrained]
    end

    assert_equal %w[Passer], reached.call(Rbs::TRAINING_PASSED)
    assert_equal %w[Flunker Passer], reached.call(Rbs::TRAINING_REGISTERED)
    assert_equal %w[Untrained], reached.call(Rbs::TRAINING_NONE)
  end

  test "someone who has opted out of both channels is not a recipient" do
    quiet = reachable(callsign: "Quiet")
    PersonAlert.create!(person_id: quiet.id, alert_id: Alert::SHIFT_CHANGE,
                        use_sms: false, use_email: false)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)

    assert_not_includes callsigns(people), quiet.callsign
  end

  test "an emergency reaches people who have opted out" do
    quiet = reachable(callsign: "Quiet", on_site: true)
    PersonAlert.create!(person_id: quiet.id, alert_id: Alert::EMERGENCY_BROADCAST,
                        use_sms: false, use_email: false)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_EMERGENCY, {})
    found = people.find { |person| person.callsign == quiet.callsign }

    assert_not_nil found
    assert found.use_sms, "an emergency text overrides the choice not to be texted"
    assert found.use_email
  end

  test "an emergency leaves out the people already on a shift" do
    on_duty = reachable(callsign: "OnDuty", on_site: true)
    on_shift(on_duty)
    reachable(callsign: "OffDuty", on_site: true)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_EMERGENCY, {})

    assert_includes callsigns(people), "OffDuty"
    assert_not_includes callsigns(people), on_duty.callsign
  end

  test "an on-shift broadcast reaches only the people on a shift" do
    on_duty = reachable(callsign: "Working")
    on_shift(on_duty)
    reachable(callsign: "Resting")

    people = Rbs.retrieve_recipients(Broadcast::TYPE_ONSHIFT, {})

    assert_equal [on_duty.callsign], callsigns(people)
  end

  test "an on-shift broadcast skips a number that was never confirmed" do
    unconfirmed = reachable(callsign: "Unconfirmed", verified: false)
    on_shift(unconfirmed)

    assert_empty Rbs.retrieve_recipients(Broadcast::TYPE_ONSHIFT, {})
  end

  test "a position broadcast reaches the people holding the position" do
    holder = reachable(callsign: "Holder")
    PersonPosition.create!(person_id: holder.id, position_id: positions(:ood_position).id)
    reachable(callsign: "Outsider")

    people = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION,
                                     alert_id: Alert::SHIFT_MUSTER, statuses: [Person::ACTIVE],
                                     position_ids: [positions(:ood_position).id],
                                     position_signed_up: Rbs::SIGNED_UP_ANY,
                                     send_sms: true, send_email: true)

    assert_equal [holder.callsign], callsigns(people)
  end

  test "a position broadcast can be narrowed to this year's sign-ups" do
    signed_up = reachable(callsign: "Signed")
    not_signed = reachable(callsign: "NotSigned")
    [signed_up, not_signed].each do |person|
      PersonPosition.create!(person_id: person.id, position_id: positions(:ood_position).id)
    end
    sign_up(signed_up, event_slot(positions(:ood_position)))

    criteria = { alert_id: Alert::SHIFT_MUSTER, statuses: [Person::ACTIVE],
                 position_ids: [positions(:ood_position).id], send_sms: true, send_email: true }

    yes = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION,
                                  criteria.merge(position_signed_up: Rbs::SIGNED_UP_YES))
    no = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION,
                                 criteria.merge(position_signed_up: Rbs::SIGNED_UP_NO))

    assert_equal [signed_up.callsign], callsigns(yes)
    assert_equal [not_signed.callsign], callsigns(no)
  end

  test "a shift broadcast reaches that shift's sign-ups" do
    slot = event_slot(positions(:ood_position))
    going = reachable(callsign: "Going")
    sign_up(going, slot)
    reachable(callsign: "NotGoing")

    people = Rbs.retrieve_recipients(Broadcast::TYPE_SLOT,
                                     alert_id: Alert::SHIFT_CHANGE, slot_id: slot.id,
                                     send_sms: true, send_email: true)

    assert_equal [going.callsign], callsigns(people)
  end

  test "a Clubhouse message reaches people no other channel can" do
    unreachable = reachable(callsign: "NoPhone", sms: "")
    PersonAlert.create!(person_id: unreachable.id, alert_id: Alert::SHIFT_CHANGE,
                        use_sms: false, use_email: false)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_clubhouse: true)

    assert_includes callsigns(people), unreachable.callsign
  end

  test "why a text cannot reach someone is recorded against them" do
    reachable(callsign: "NoNumber", sms: "")
    reachable(callsign: "Unconfirmed", verified: false)
    reachable(callsign: "Stopped", stopped: true)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)
    reasons = people.to_h { |person| [person.callsign, person.sms_status] }

    assert_equal Rbs::SMS_STATUS_NO_PHONE, reasons["NoNumber"]
    assert_equal Rbs::SMS_STATUS_UNVERIFIED, reasons["Unconfirmed"]
    assert_equal Rbs::SMS_STATUS_STOPPED, reasons["Stopped"]
    assert_not people.select { |person| reasons.key?(person.callsign) }.any?(&:use_sms)
  end

  test "the emergency alert is offered to no other kind of broadcast" do
    Rbs::PAGE_TYPES.each do |type|
      offered = Rbs.alerts_for(type).map(&:id)

      assert_not_includes offered, Alert::EMERGENCY_BROADCAST,
                          "#{type} must not be able to borrow the emergency alert"
    end
  end

  test "an emergency alert on another kind of broadcast does not override an opt-out" do
    quiet = reachable(callsign: "Quiet")
    PersonAlert.create!(person_id: quiet.id, alert_id: Alert::EMERGENCY_BROADCAST,
                        use_sms: false, use_email: false)
    PersonPosition.create!(person_id: quiet.id, position_id: positions(:ood_position).id)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      perform_enqueued_jobs do
        Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender,
                     criteria: { alert_id: Alert::EMERGENCY_BROADCAST, statuses: [Person::ACTIVE],
                                 position_ids: [positions(:ood_position).id],
                                 position_signed_up: Rbs::SIGNED_UP_ANY,
                                 send_sms: false, send_email: true, send_clubhouse: false },
                     message: { sms_message: nil, subject: "Hello", message: "Body", expires_at: nil })
      end

      assert_not_includes calls.flat_map { |call| ses_addresses(call) }, quiet.email
    end
  end

  # ==========================================================================
  # Permissions
  # ==========================================================================

  test "only an emergency permission may send an emergency broadcast" do
    ensure_role(Role::MEGAPHONE, "Megaphone")
    grant_role(@sender, Role::MEGAPHONE)
    Current.roles_manager = RoleManager.retrieve(@sender)

    assert Rbs.type_allowed?(Broadcast::TYPE_GENERAL)
    assert_not Rbs.type_allowed?(Broadcast::TYPE_EMERGENCY)
  end

  test "a team permission may call up a team but not everyone" do
    ensure_role(Role::MEGAPHONE_TEAM_ONPLAYA, "Megaphone Team On Playa")
    # The two on-playa permissions are only held while this is on.
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED)
           .update!(value: "true")
    Rails.cache.clear
    grant_role(@sender, Role::MEGAPHONE_TEAM_ONPLAYA)
    Current.roles_manager = RoleManager.retrieve(@sender)

    assert Rbs.type_allowed?(Broadcast::TYPE_POSITION)
    assert_not Rbs.type_allowed?(Broadcast::TYPE_GENERAL)
    assert_not Rbs.type_allowed?(Broadcast::TYPE_EMERGENCY)
  end

  # ==========================================================================
  # Sending
  # ==========================================================================

  test "sending records the broadcast, one message per person, and queues the rest" do
    listener = reachable(callsign: "Listener")
    PersonPosition.create!(person_id: listener.id, position_id: positions(:ood_position).id)

    criteria = { alert_id: Alert::SHIFT_MUSTER, statuses: [Person::ACTIVE],
                 position_ids: [positions(:ood_position).id],
                 position_signed_up: Rbs::SIGNED_UP_ANY,
                 send_sms: true, send_email: true, send_clubhouse: true }

    result = nil
    assert_enqueued_jobs 3 do
      result = Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                            message: { sms_message: "Muster now", subject: "Muster",
                                       message: "Please come in.", expires_at: nil })
    end

    broadcast = result.broadcast

    assert_equal @sender.id, broadcast.sender_id
    assert_equal Alert::SHIFT_MUSTER, broadcast.alert_id
    assert_equal 1, broadcast.recipient_count
    assert broadcast.sent_sms
    assert broadcast.sent_email
    assert broadcast.sent_clubhouse
    assert_equal 1, result.texts_queued
    assert_equal [Broadcast::STATUS_QUEUED], text_statuses(broadcast), "the job sends it"
    assert_enqueued_with(job: RbsTransmitSmsJob, args: [broadcast.id, true])
  end

  test "a short broadcast sends its one message as the email subject" do
    reachable(callsign: "Dusty", on_site: true)

    result = Rbs.transmit(type: Broadcast::TYPE_RECRUIT_DIRT, sender: @sender, criteria: {},
                          message: { sms_message: "More Rangers needed", subject: nil,
                                     message: nil, expires_at: nil })

    assert_equal "More Rangers needed", result.broadcast.subject
    assert result.broadcast.sent_sms
    assert result.broadcast.sent_email
    assert_not result.broadcast.sent_clubhouse
  end

  test "an on-shift broadcast sends no email" do
    on_duty = reachable(callsign: "Working")
    on_shift(on_duty)

    result = Rbs.transmit(type: Broadcast::TYPE_ONSHIFT, sender: @sender, criteria: {},
                          message: { sms_message: "Repeater is down", subject: nil,
                                     message: nil, expires_at: nil })

    assert result.broadcast.sent_sms
    assert_not result.broadcast.sent_email
  end

  test "the sandbox records a text as sent without handing it to Twilio" do
    reachable(callsign: "Listener")
    result = nil

    fake = through_twilio { result = send_general_text }

    assert_empty fake.asked, "the sandbox must not reach Twilio"
    assert_equal [Broadcast::STATUS_SENT], text_statuses(result.broadcast).uniq
  end

  test "every text Twilio takes is sent, keeping the SID Twilio gave it" do
    3.times { |n| reachable(callsign: "Heard#{n}") }
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    result = nil

    fake = through_twilio { result = send_general_text }

    rows = BroadcastMessage.where(broadcast_id: result.broadcast.id, address_type: "sms")

    assert_operator result.texts_queued, :>=, 3
    assert_equal result.texts_queued, fake.created_texts.size, "one request a person"
    assert_equal [Broadcast::STATUS_SENT], rows.distinct.pluck(:status)
    assert_equal rows.count, rows.distinct.count(:message_id)
    assert_equal [Rbs.send(:sms_body, "Hello")], fake.created_texts.pluck(:body).uniq
    assert_equal 0, result.broadcast.reload.sms_failed
  end

  test "every text Twilio refuses is a counted failure, never raised at the sender" do
    3.times { |n| reachable(callsign: "Listener#{n}") }
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    refusing = FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.refusal(21408, "Permission to send an SMS has not been enabled for the region") })
    result = nil

    through_twilio(refusing) { result = send_general_text }

    assert_equal [Broadcast::STATUS_SERVICE_FAIL], text_statuses(result.broadcast).uniq
    assert_equal result.texts_queued, result.broadcast.reload.sms_failed
    assert_predicate result.broadcast, :retryable?
  end

  # It may have gone out, so it is never sent again, and a Retry leaves it be.
  test "a text Twilio may have taken without answering is send-unconfirmed" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    result = nil

    through_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.read_timeout })) do
      result = send_general_text
    end

    row = BroadcastMessage.find_by!(broadcast_id: result.broadcast.id, person_id: listener.id, address_type: "sms")

    assert_equal [Broadcast::STATUS_SEND_UNCONFIRMED, nil], [row.status, row.message_id]
    assert_not_includes result.broadcast.failed_messages, row
  end

  test "a text Twilio turns away for being asked too fast is asked again, and goes" do
    criteria = only_listener(send_sms: true)
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    too_fast = FakeTwilioClient.refusal(20429, "Too Many Requests", status: 429)
    result = nil

    fake = through_twilio(FakeTwilioClient.new(errors: { message_create: [too_fast] })) do
      result = Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                            message: { sms_message: "Muster now", subject: nil, message: nil, expires_at: nil })
    end

    assert_equal 2, fake.asked.count(:message_create)
    assert_equal [[Broadcast::STATUS_SENT, format("SM%032d", 1)]],
                 BroadcastMessage.where(broadcast_id: result.broadcast.id, address_type: "sms").pluck(:status, :message_id)
  end

  test "each thread of a broadcast's job sends with a Twilio client of its own" do
    (Rbs::SMS_THREADS + 2).times { |n| reachable(callsign: "Heard#{n}") }
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    configure_twilio
    clients = []
    result = nil
    original = TwilioAccount.method(:build_client)
    TwilioAccount.define_singleton_method(:build_client) { |*| FakeTwilioClient.new.tap { |client| clients << client } }
    begin
      perform_enqueued_jobs { result = send_general_text }
    ensure
      TwilioAccount.define_singleton_method(:build_client, original)
    end

    assert_equal Rbs::SMS_THREADS, clients.size, "one client a thread, kept for the run"
    assert_equal result.texts_queued, clients.sum { |client| client.created_texts.size }
    assert clients.all? { |client| client.created_texts.any? }
  end

  # Two people asking at the same time must not see each other's shifts.
  test "the shift list is not kept between callers" do
    slot = event_slot(positions(:ood_position))
    sign_up(reachable(callsign: "Signee"), slot)

    first = Rbs.slots_for_position(positions(:ood_position).id, team_only: false).map(&:id)
    second_slot = event_slot(positions(:ood_position), begins: @event_start + 3.days)
    sign_up(reachable(callsign: "Later"), second_slot)
    second = Rbs.slots_for_position(positions(:ood_position).id, team_only: false).map(&:id)

    assert_includes first, slot.id
    assert_includes second, second_slot.id, "a list held between calls would miss the new shift"
  end

  test "text credentials that are not configured fail every text once, not the page" do
    reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)

    # No fake: the real service is asked for credentials the tests do not
    # have, which raises something other than a texting error.
    result = nil
    perform_enqueued_jobs { result = send_general_text }

    assert_equal [Broadcast::STATUS_SERVICE_FAIL], text_statuses(result.broadcast).uniq
    assert_equal result.texts_queued, result.broadcast.reload.sms_failed
    assert_equal 1, ErrorLog.where(error_type: "sms-exception").count, "logged once, not once a text"
  end

  # A deploy stops the job at its checkpoint with an Exception, not a
  # StandardError: the texts not yet sent stay queued for it to pick up again.
  # An error leaves them failed, for a Retry, and the round it stopped after
  # stays as it was written.
  test "a run stopped part-way never leaves a text to go twice, nor one stuck queued" do
    # Two whole rounds and some over, so the second stop leaves texts unsent.
    ((2 * Rbs::SMS_THREADS) + 1).times { |n| reachable(callsign: "Heard#{n}") }
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    configure_twilio
    deploy = Class.new(Exception)
    broadcast = nil

    with_fake_twilio(FakeTwilioClient.new) do
      broadcast = send_general_text.broadcast
      assert_raises(deploy) { Rbs.deliver_queued_sms(broadcast.id, false) { raise deploy } }

      assert_equal Rbs::SMS_THREADS, text_statuses(broadcast).count(Broadcast::STATUS_SENT)
      assert_includes text_statuses(broadcast), Broadcast::STATUS_QUEUED

      assert_raises(RuntimeError) { Rbs.deliver_queued_sms(broadcast.id, false) { raise "stopped" } }
    end

    assert_not_includes text_statuses(broadcast), Broadcast::STATUS_QUEUED
    assert_includes text_statuses(broadcast), Broadcast::STATUS_SERVICE_FAIL
    assert_equal BroadcastMessage.count_fail(broadcast.id, "sms"), broadcast.reload.sms_failed
  end

  # Held email needs no SES account, so none is built: a dev machine has none.
  test "the sandbox delivers no email but still records one per person" do
    listening("Listener")

    result = nil
    with_ses do |calls|
      without_ses_account { perform_enqueued_jobs { result = send_email } }

      assert_empty calls
    end

    rows = BroadcastMessage.where(broadcast_id: result.broadcast.id, address_type: "email")

    # Sent, not failed: email that went the SES way by mistake would fail on
    # the missing account and still leave one row.
    assert_equal [Broadcast::STATUS_SENT], rows.pluck(:status)
    assert_equal 0, MailLog.where(broadcast_id: result.broadcast.id).count
  end

  test "the sandbox creates no Clubhouse message but still records one" do
    criteria = only_listener(send_clubhouse: true)
    listener = Person.find_by(callsign: "Listener")

    assert_no_turbo_stream_broadcasts listener do
      perform_enqueued_jobs do
        result = Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                              message: { sms_message: nil, subject: "Hello", message: "Body",
                                         expires_at: nil })

        assert_equal 0, PersonMessage.where(broadcast_id: result.broadcast.id).count
        assert_equal 1, BroadcastMessage.where(broadcast_id: result.broadcast.id,
                                               address_type: "clubhouse").count
      end
    end
  end

  test "a Clubhouse message is delivered when the sandbox is off" do
    criteria = only_listener(send_clubhouse: true)
    listener = Person.find_by(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_CLUBHOUSE_SANDBOX)

    perform_enqueued_jobs do
      result = Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                            message: { sms_message: nil, subject: "Hello", message: "Body",
                                       expires_at: nil })

      message = PersonMessage.find_by(broadcast_id: result.broadcast.id)

      assert_not_nil message
      assert_equal listener.id, message.person_id
      assert_equal PersonMessage::SENDER_TYPE_RBS, message.sender_type
      # Its recipient's member row, never read.
      assert_equal [[listener.id, nil]], message.members.pluck(:person_id, :last_read_message_id)
    end
  end

  # PersonMessage#announce_to_recipient runs for the copies the job saves too,
  # and renders nothing from Current: the job runs here with nobody in it.
  test "each Clubhouse copy of a broadcast updates its recipient's navbar live" do
    criteria = only_listener(send_clubhouse: true)
    listener = Person.find_by(callsign: "Listener")
    hearer = listening("Hearer")
    sandbox_off(Setting::BROADCAST_CLUBHOUSE_SANDBOX)

    Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                 message: { sms_message: nil, subject: "Hello", message: "Body", expires_at: nil })
    Current.person = nil
    perform_enqueued_jobs

    [listener, hearer].each do |person|
      streams = capture_turbo_stream_broadcasts(person)
      assert_equal %w[navbar-messages live-region], streams.map { |stream| stream["target"] }, person.callsign
      assert_equal "Ranger Broadcasting Service sent you a message.", streams.last.text.strip
    end
  end

  # ==========================================================================
  # Email through Amazon SES
  # ==========================================================================

  # The sandbox tests above can only show that nothing was delivered, which is
  # equally true of an email path that is simply broken. This one sends for
  # real, as far as SES, and checks what SES was asked to send.
  test "a broadcast email goes to SES as written and is recorded under the id SES gave it" do
    listener = listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    subject = %(Rain & wind: don't "wait" <now>)
    body = "Bring <b>water</b>. Map: https://example.com/map"

    result = nil
    with_ses do |calls|
      perform_enqueued_jobs { result = send_email(subject:, message: body) }

      assert_equal 1, calls.size
      call = calls.first

      assert_equal %i[bulk_email_entries default_content from_email_address], call.keys.sort,
                   "no configuration set (decision 5), and nothing else"
      mail = RbsMailer.broadcast(subject:, rbs_message: body, alert: Alert.find(Alert::SHIFT_MUSTER),
                                 expires_at: nil).message
      data = ses_template_data(call)

      assert_equal "Ranger Clubhouse <#{::EmailAddresses::DO_NOT_REPLY}>", call[:from_email_address]
      assert_equal ["Listener (Listener Test)"], ses_to_lines(call).map { |line| Mail::Address.new(line).display_name }
      assert_equal [listener.email], ses_addresses(call)
      assert_equal({ subject: "{{subject}}", html: "{{html}}" }, call[:default_content][:template][:template_content])
      assert_equal({ "subject" => mail.subject, "html" => (mail.html_part || mail).decoded }, data)
      assert_equal subject, data["subject"], "the subject must reach SES as typed, not escaped"
      assert_includes data["html"], "<b>water</b>", "the body must reach SES as HTML, not escaped"
    end

    row = email_row(result.broadcast, listener)
    log = MailLog.find_by!(broadcast_id: result.broadcast.id)

    assert_equal Broadcast::STATUS_SENT, row.status
    assert_equal "ses-#{listener.email}", row.message_id
    assert_equal 1, MailLog.where(broadcast_id: result.broadcast.id).count
    assert_equal ["ses-#{listener.email}", listener.email, "do-not-reply@burningman.org", listener.id, @sender.id, true],
                 [log.message_id, log.to_email, log.from_email, log.person_id, log.sender_id, log.was_sent]
    assert_equal 0, result.broadcast.reload.email_failed
    assert_equal log, MailLog.mark_as_delivered(listener.email, "ses-#{listener.email}"),
                 "SES's delivery report must find the row by the id SES gave the email"
  end

  test "a broadcast goes to SES in calls no bigger than the send rate" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("2")

    result = nil
    without_pacing do |waits|
      with_ses do |calls|
        perform_enqueued_jobs { result = send_email }

        assert_equal [2, 1], calls.map { |call| call[:bulk_email_entries].size }
      end

      assert_equal 1, waits.size, "the second call waits for the first"
    end

    # Each answer is worked out from its own address, so an id that lands on
    # the wrong person's row would show here.
    people.each do |person|
      assert_equal "ses-#{person.email}", email_row(result.broadcast, person).message_id
      assert_equal "ses-#{person.email}",
                   MailLog.find_by!(broadcast_id: result.broadcast.id, person_id: person.id).message_id
    end
  end

  test "a rate left blank, or nonsense, still sends forty a call, and never more than fifty" do
    assert_equal 40, Rbs.send(:ses_batch_size), "no setting at all"

    set_send_rate("")

    assert_equal 40, Rbs.send(:ses_batch_size), "a cleared setting reads as 0, not one a second"

    set_send_rate("0")

    assert_equal 40, Rbs.send(:ses_batch_size)

    set_send_rate("100")

    assert_equal Rbs::SES_BATCH_LIMIT, Rbs.send(:ses_batch_size)
  end

  test "only the people SES took are recorded as sent" do
    taken = listening("Able")
    refused = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    refuse_baker = SesTestHelper.refusing(
      refused.email => { status: "MESSAGE_REJECTED", error: "Email address is not verified." }
    )

    result = nil
    with_ses(refuse_baker) { perform_enqueued_jobs { result = send_email } }

    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, taken).status
    assert_equal "message-rejected", email_row(result.broadcast, refused).status
    assert_equal [taken.id], MailLog.where(broadcast_id: result.broadcast.id).pluck(:person_id)
    assert_equal 1, result.broadcast.reload.email_failed

    logged = ErrorLog.where(error_type: "rbs-email-not-accepted").last.data

    assert_equal [{ "person_id" => refused.id, "status" => "MESSAGE_REJECTED",
                    "error" => "Email address is not verified." }], logged["refused"],
                 "SES's own words are kept in the log; the row keeps only the status"
  end

  test "an answer that does not match the call fails everyone in it, and says so" do
    first = listening("Able")
    second = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    one_answer = ->(_context) { { bulk_email_entry_results: [{ status: "SUCCESS", message_id: "ses-one" }] } }

    result = nil
    assert_difference -> { ErrorLog.where(error_type: "rbs-email-not-accepted").count }, 1 do
      with_ses(one_answer) { perform_enqueued_jobs { result = send_email } }
    end

    assert_equal [Broadcast::STATUS_SEND_UNCONFIRMED] * 2,
                 [email_row(result.broadcast, first).status, email_row(result.broadcast, second).status],
                 "SES took the call, so either of them may have been sent"
    assert_equal 0, MailLog.where(broadcast_id: result.broadcast.id).count
  end

  test "after three lasting failures in a row, the rest of the broadcast is not sent" do
    people = %w[Able Baker Charlie Delta Echo].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    paused = ->(_context) { raise Aws::SESV2::Errors::SendingPausedException.new(nil, "Sending paused") }

    result = nil
    without_pacing do
      with_ses(paused) do |calls|
        perform_enqueued_jobs { result = send_email }

        assert_equal Rbs::SES_FAILURES_BEFORE_GIVING_UP, calls.size
      end
    end

    assert_equal ["account-sending-paused"] * 3 + [Broadcast::STATUS_SERVICE_FAIL] * 2,
                 people.map { |person| email_row(result.broadcast, person).status },
                 "the three tried carry SES's reason; the two never tried are plain failures"
    assert_equal 3, ErrorLog.where(error_type: "rbs-email-exception").count
    assert_equal [{ "broadcast_id" => result.broadcast.id, "people_not_sent" => 2 }],
                 ErrorLog.where(error_type: "rbs-email-given-up").map(&:data)
  end

  test "an account SES refuses for everyone counts as a lasting failure too" do
    %w[Able Baker Charlie Delta].each { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    over_quota = lambda do |context|
      { bulk_email_entry_results: context.params[:bulk_email_entries].map { { status: "ACCOUNT_DAILY_QUOTA_EXCEEDED" } } }
    end

    without_pacing do
      with_ses(over_quota) do |calls|
        perform_enqueued_jobs { send_email }

        assert_equal 3, calls.size
      end
    end
  end

  # A blip -- a dropped uplink, SES asked too fast, a fault on its side -- may
  # be over by the next call, so it never writes off the rest of a broadcast.
  test "failures that may pass never stop a broadcast" do
    people = %w[Able Baker Charlie Delta Echo].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    errors = [
      Seahorse::Client::NetworkingError.new(Errno::ECONNREFUSED.new),
      Aws::SESV2::Errors::TooManyRequestsException.new(nil, "Slow down"),
      Seahorse::Client::NetworkingError.new(Errno::ECONNRESET.new),
      Seahorse::Client::NetworkingError.new(SocketError.new)
    ]
    blip = ->(context) { errors.empty? ? SesTestHelper::ACCEPT_ALL.call(context) : raise(errors.shift) }

    result = nil
    without_pacing do
      with_ses(blip) do |calls|
        perform_enqueued_jobs { result = send_email }

        assert_equal 5, calls.size
      end
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, "account-throttled", Broadcast::STATUS_SEND_UNCONFIRMED,
                  Broadcast::STATUS_SERVICE_FAIL, Broadcast::STATUS_SENT],
                 people.map { |person| email_row(result.broadcast, person).status }
    assert_equal 0, ErrorLog.where(error_type: "rbs-email-given-up").count
  end

  test "a call that sends somebody starts the count of lasting failures over" do
    people = %w[Able Baker Charlie Delta Echo Foxtrot].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    # Two lasting failures, a success, two more, a success: never three in a row.
    calls_so_far = 0
    every_third_works = lambda do |context|
      calls_so_far += 1
      raise Aws::SESV2::Errors::SendingPausedException.new(nil, "Sending paused") unless (calls_so_far % 3).zero?

      SesTestHelper::ACCEPT_ALL.call(context)
    end

    result = nil
    without_pacing { with_ses(every_third_works) { perform_enqueued_jobs { result = send_email } } }

    assert_equal 6, calls_so_far, "the sixth person is still tried"
    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, people.last).status
  end

  # The emails SES took went out, whatever happens after: recording one of
  # them as failed would let a Retry send it a second time.
  test "an answer from SES is never turned into a failure" do
    taken = listening("Able")
    refused = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    refuse_baker = SesTestHelper.refusing(refused.email => "MESSAGE_REJECTED")
    original = ErrorLog.method(:record)
    ErrorLog.define_singleton_method(:record) { |*, **| raise ActiveRecord::StatementInvalid, "lost connection" }

    result = send_email
    with_ses(refuse_baker) { perform_enqueued_jobs }

    assert_equal [[Broadcast::STATUS_SENT, "ses-#{taken.email}"], ["message-rejected", nil]],
                 [taken, refused].map { |person| email_row(result.broadcast, person).slice(:status, :message_id).values },
                 "a log that cannot be written stops nothing SES answered from being written down"
  ensure
    ErrorLog.define_singleton_method(:record, original)
  end

  # Each of these passes the pattern Person checks, or reads as an address to
  # it, but SES or the mail library would refuse it -- and the mail library
  # refusing one used to fail everyone in the call with it. The last four are
  # outside the form AWS documents, and none could be delivered.
  test "an address SES could not take is never handed to it" do
    good = listening("Able")
    bad = {
      "Baker" => "not-an-address",
      "Charlie" => "...@example.com",
      "Delta" => "john..doe@example.com",
      "Echo" => ".john@example.com",
      "Foxtrot" => "john.@example.com",
      "Golf" => "a@b",
      "Hotel" => "a@1.2.3.4",
      "India" => "a@b.123",
      "Juliet" => "a@b.c"
    }.map { |callsign, email| listening(callsign).tap { |person| person.update_columns(email:) } }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = nil
    with_ses do |calls|
      perform_enqueued_jobs { result = send_email }

      assert_equal [good.email], calls.flat_map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, good).status
    bad.each do |person|
      assert_equal Broadcast::STATUS_INVALID_PARAMETER, email_row(result.broadcast, person).status, person.email
    end
  end

  # AWS documents UserName@[SubDomain.]Domain.TopLevelDomain. Every real
  # top-level domain fits it, an internationalised one written in punycode too.
  test "an address in the form AWS documents is taken, and one outside it is not" do
    {
      "name@example.com" => true,
      "First.Last@Sub.Example.ORG" => true,
      "a@example.museum" => true,
      "a@example.xn--p1ai" => true,
      "a@xn--bcher-kva.example" => true,
      "a@b" => false,
      "a@1.2.3.4" => false,
      "a@b.123" => false,
      "a@b.c" => false
    }.each { |address, taken| assert_equal taken, Rbs.send(:sendable_address?, address), address }
  end

  test "a line break or control character in a name never reaches the To line" do
    person = listening("Listener")
    person.update_columns(first_name: "New\r\nline", last_name: "Sm\u0000ith")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      perform_enqueued_jobs { send_email }

      line = ses_to_lines(calls.first).first

      assert_no_match(/[[:cntrl:]]/, line)
      assert_equal "Listener (New line Sm ith)", Mail::Address.new(line).display_name
    end
  end

  test "a callsign with brackets, or a name outside plain ASCII, reaches SES as a name" do
    bracketed = listening("Hubcap (NR)")
    bracketed.update_columns(email: "hubcap@example.com", first_name: "Bob", last_name: "Smith")
    accented = listening("Zorro")
    accented.update_columns(first_name: "José", last_name: "Núñez")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      perform_enqueued_jobs { send_email }

      lines = calls.flat_map { |call| ses_to_lines(call) }

      assert lines.all?(&:ascii_only?), "a name outside ASCII must be encoded"
      assert_equal({ "hubcap@example.com" => "Hubcap (NR) (Bob Smith)",
                     "zorro@example.com" => "Zorro (José Núñez)" },
                   lines.to_h { |line| [Mail::Address.new(line).address, Mail::Address.new(line).display_name] })
    end
  end

  test "email goes to Rangers only where that is switched on for real" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    assert_equal :live, Rbs.email_mode
    with_rangers_emailed(false) { assert_equal :held, Rbs.email_mode }
    # What an environment that never set it reads: an empty set of options,
    # which Ruby counts as true.
    with_rangers_emailed(ActiveSupport::OrderedOptions.new) { assert_equal :held, Rbs.email_mode }
  end

  test "the sandbox and the training server hold email back" do
    assert_equal :held, Rbs.email_mode, "the sandbox is on in the fixtures"

    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Current.groundhog_day_time = Current.time

    assert_equal :held, Rbs.email_mode
  ensure
    Current.groundhog_day_time = nil
  end

  test "email held back is recorded as sent and never reaches SES" do
    person = listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = nil
    with_rangers_emailed(false) do
      with_ses do |calls|
        without_ses_account { perform_enqueued_jobs { result = send_email } }

        assert_empty calls
      end
    end

    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, person).status
    assert_equal 0, MailLog.where(broadcast_id: result.broadcast.id).count
  end

  test "email held back is recorded as sent, and an email with no address as invalid" do
    malformed = listening("Able")
    malformed.update_columns(email: "not-an-address")
    missing = listening("Baker")

    result = send_email
    # Cleared after the sender pressed Send and before the email went.
    missing.update_columns(email: "")
    perform_enqueued_jobs

    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, malformed).status
    assert_equal Broadcast::STATUS_INVALID_PARAMETER, email_row(result.broadcast, missing).status
  end

  test "an SES call waits until a second has passed since the last one began" do
    waits = []
    Rbs.define_singleton_method(:sleep) { |seconds| waits << seconds }
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    assert_operator Rbs.send(:pace, nil), :>=, now, "the first call goes at once"
    assert_empty waits

    Rbs.send(:pace, now)

    assert_equal 1, waits.size
    assert_in_delta 1.0, waits.first, 0.1

    Rbs.send(:pace, now - 2.0)

    assert_equal 1, waits.size, "a call a second after the last one need not wait"
  ensure
    Rbs.singleton_class.remove_method(:sleep)
  end

  test "a subject typed over several lines reaches SES as one line" do
    listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      perform_enqueued_jobs { send_email(subject: "Line one\r\nLine two") }

      assert_equal "Line one Line two", ses_template_data(calls.first)["subject"]
    end
  end

  # A subject that comes out blank -- an edited template, say -- still has to
  # fill the template's {{subject}}, or SES takes the email and never sends it.
  test "a blank subject still reaches SES" do
    listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      perform_enqueued_jobs { send_email(subject: "") }

      assert_equal "", ses_template_data(calls.first)["subject"]
    end
  end

  test "no SES client in the tests can reach Amazon" do
    assert Aws::SESV2::Client.new.config.stub_responses
  end

  test "the SES client makes each call only once" do
    config = Rbs.send(:ses_client).config

    assert_equal 0, config.retry_limit
    assert_equal 1, config.max_attempts
    assert_equal [5, 20], [config.http_open_timeout, config.http_read_timeout],
                 "inside production's 30 s shutdown_timeout, so a deploy never cuts a call off"
    assert_equal Aws::Log::Formatter.short.pattern, config.log_formatter.pattern,
                 "the SDK logs every call to the Rails log; the short line leaves out the addresses and the body"
  end

  # ==========================================================================
  # Why an email did not go
  # ==========================================================================

  test "every status fits the column, and every one reads as words" do
    assert Broadcast::MESSAGE_STATUSES.all? { |status| status.length <= 32 }, "broadcast_message.status is varchar(32)"
    assert_equal 14, Broadcast::EMAIL_FAIL_STATUSES.size
    assert_empty Broadcast::EMAIL_FAIL_STATUSES - Broadcast::MESSAGE_STATUSES, "the message log must filter by them"

    labels = Communication::RbsHelper::MESSAGE_STATUS_LABELS
    variants = Communication::RbsHelper::MESSAGE_STATUS_VARIANTS

    assert_empty Broadcast::MESSAGE_STATUSES - labels.keys
    assert Broadcast::EMAIL_FAIL_STATUSES.all? { |status| variants[status] == :error }
    assert_empty [Broadcast::STATUS_VERIFY, Broadcast::STATUS_HELP, Broadcast::STATUS_STATS, Broadcast::STATUS_NEXT,
                  Broadcast::STATUS_NO_CONTACT] & variants.keys,
                 "these keep the :secondary fallback; a new colour needs the user's approval"
    assert_equal labels.values.uniq, labels.values, "two statuses with one label could not be told apart"
  end

  test "Retry resends every failure but an invalid address and an email SES may have sent" do
    assert_equal 13, Broadcast::RETRYABLE_STATUSES.size
    assert_includes Broadcast::RETRYABLE_STATUSES, Broadcast::STATUS_SERVICE_FAIL
    assert_includes Broadcast::RETRYABLE_STATUSES, "message-rejected", "often account setup, which a retry fixes"
    assert_empty [Broadcast::STATUS_INVALID_PARAMETER, Broadcast::STATUS_SEND_UNCONFIRMED] &
                 Broadcast::RETRYABLE_STATUSES
    assert_empty Broadcast::RETRYABLE_STATUSES - Broadcast::FAILURE_STATUSES
  end

  test "each person SES did not take carries SES's own reason" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    mixed = SesTestHelper.refusing(people[1].email => "ACCOUNT_THROTTLED", people[2].email => "SOMETHING_NEW")

    result = nil
    with_ses(mixed) { perform_enqueued_jobs { result = send_email } }

    assert_equal [Broadcast::STATUS_SENT, "account-throttled", Broadcast::STATUS_FAILED],
                 people.map { |person| email_row(result.broadcast, person).status }
    assert_equal [people[0].id], MailLog.where(broadcast_id: result.broadcast.id).pluck(:person_id)
    assert_equal 2, result.broadcast.reload.email_failed
  end

  # One test for each way a whole call can go wrong.
  {
    "SES asked too fast" => [Aws::SESV2::Errors::TooManyRequestsException.new(nil, "Slow down"), "account-throttled"],
    "a request SES turned away" => [Aws::SESV2::Errors::BadRequestException.new(nil, "Bad"),
                                    Broadcast::STATUS_SERVICE_FAIL],
    "a fault at SES's end" => [{ status_code: 500, headers: { "x-amzn-ErrorType" => "InternalFailure" }, body: "{}" },
                               Broadcast::STATUS_SEND_UNCONFIRMED],
    "an answer that never came" => [Seahorse::Client::NetworkingError.new(Net::ReadTimeout.new),
                                    Broadcast::STATUS_SEND_UNCONFIRMED],
    "a connection never made" => [Seahorse::Client::NetworkingError.new(Net::OpenTimeout.new),
                                  Broadcast::STATUS_SERVICE_FAIL],
    "a host that cannot be reached" => [Seahorse::Client::NetworkingError.new(Errno::EHOSTUNREACH.new),
                                        Broadcast::STATUS_SERVICE_FAIL],
    "a network that cannot be reached" => [Errno::ENETUNREACH.new, Broadcast::STATUS_SERVICE_FAIL],
    "an SES limit reached" => [Aws::SESV2::Errors::LimitExceededException.new(nil, "Limit"), "account-throttled"],
    "no SES keys" => [Aws::Errors::MissingCredentialsError.new, Broadcast::STATUS_SERVICE_FAIL],
    "a call the SDK would not make" => [ArgumentError.new("bad parameter"), Broadcast::STATUS_SERVICE_FAIL],
    "something SES could not find" => [Aws::SESV2::Errors::NotFoundException.new(nil, "Not found"),
                                       Broadcast::STATUS_SERVICE_FAIL],
    "SES rejected the message" => [Aws::SESV2::Errors::MessageRejected.new(nil, "Rejected"), "message-rejected"],
    "a suspended account" => [Aws::SESV2::Errors::AccountSuspendedException.new(nil, "Suspended"),
                              "account-suspended"],
    "an unverified sending domain" => [Aws::SESV2::Errors::MailFromDomainNotVerifiedException.new(nil, "Unverified"),
                                       "mail-from-domain-not-verified"],
    "anything else the call raises" => [RuntimeError.new("boom"), Broadcast::STATUS_SEND_UNCONFIRMED]
  }.each do |what, (answer, status)|
    test "#{what} records #{status} for everyone in the call" do
      people = %w[Able Baker].map { |callsign| listening(callsign) }
      sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
      responder = ->(_context) { answer.is_a?(Exception) ? raise(answer) : answer }

      result = nil
      with_ses(responder) { perform_enqueued_jobs { result = send_email } }

      assert_equal [status] * 2, people.map { |person| email_row(result.broadcast, person).status }
      assert_equal 2, result.broadcast.reload.email_failed
    end
  end

  test "a broadcast whose only failures are bad addresses still reads as failed" do
    listening("Able").update_columns(email: "not-an-address")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = nil
    with_ses { perform_enqueued_jobs { result = send_email } }

    broadcast = result.broadcast.reload

    assert_equal 1, broadcast.email_failed
    assert_predicate broadcast, :failed?
    assert_includes Broadcast.with_failures, broadcast
  end

  test "a retry of an email with no address on file never reaches SES, and says why" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener, address: "")

    with_ses do |calls|
      send_again(broadcast)

      assert_empty calls
    end

    assert_equal Broadcast::STATUS_INVALID_PARAMETER, failed.reload.status
  end

  # ==========================================================================
  # Email to a test address
  # ==========================================================================

  UNUSABLE_TEST_ADDRESSES = [
    "test@example.com", "test+??@example.com", "test+?@exa?mple.com", "test+?",
    "a+?@example.com, b+?@example.com", "?.@example.com", "#{"x" * 60}+?@example.com", "rbs-?@invalid"
  ].freeze

  test "a test address is a pattern with the person's id in place of its ?" do
    assert_equal "test+2@example.com", Rbs.test_address("test+?@example.com", 2)
    assert_equal "test+rbs-8@example.com", Rbs.test_address(" test+rbs-?@example.com ", 8)
    assert_equal "8@example.com", Rbs.test_address("?@example.com", 8)
    assert_equal "a8b@example.com", Rbs.test_address("a?b@example.com", 8), "the ? can sit anywhere before the @"
    assert_equal "8.tag@example.com", Rbs.test_address("?.tag@example.com", 8)
    assert_equal "success+8@simulator.amazonses.com", Rbs.test_address("success+?@simulator.amazonses.com", 8)

    [*UNUSABLE_TEST_ADDRESSES, ""].each do |pattern|
      assert_nil Rbs.test_address(pattern, 8), "#{pattern.inspect} is no usable test address"
    end
  end

  test "a test address sends email through SES, and never to a Ranger" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    assert_equal :test, Rbs.email_mode

    UNUSABLE_TEST_ADDRESSES.each do |pattern|
      set_test_address(pattern)

      assert_equal :misconfigured, Rbs.email_mode, "#{pattern.inspect} would send nowhere"
      assert_nil RbsSandbox.email_test_address, pattern.inspect
    end
  end

  # Clearing the field on the settings page stores "", and that is how test
  # mode is switched off when it is over.
  test "a test address cleared to blank is off" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    ["", "  "].each do |blank|
      set_test_address(blank)

      assert_equal :live, Rbs.email_mode, blank.inspect
      assert_nil RbsSandbox.email_test_address
    end
  end

  test "the sandbox and the training server still hold email with a test address set" do
    set_test_address("test+?@example.com")

    assert_equal :held, Rbs.email_mode, "the sandbox is on in the fixtures"

    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Current.groundhog_day_time = Current.time

    assert_equal :held, Rbs.email_mode
  ensure
    Current.groundhog_day_time = nil
  end

  test "with a test address, each email goes to it with the person's id, and that is what is recorded" do
    able = listening("Able")
    baker = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+rbs-?@example.com")
    refuse_baker = SesTestHelper.refusing("test+rbs-#{baker.id}@example.com" => "MESSAGE_REJECTED")

    result = nil
    with_ses(refuse_baker) do |calls|
      perform_enqueued_jobs { result = send_email }

      assert_equal ["test+rbs-#{able.id}@example.com", "test+rbs-#{baker.id}@example.com"],
                   ses_addresses(calls.first)
      assert_equal "Able (Able Test)", Mail::Address.new(ses_to_lines(calls.first).first).display_name,
                   "the name on the copy is still the Ranger's"
    end

    assert_equal ["test+rbs-#{able.id}@example.com", Broadcast::STATUS_SENT],
                 [email_row(result.broadcast, able).address, email_row(result.broadcast, able).status]
    assert_equal ["test+rbs-#{baker.id}@example.com", "message-rejected"],
                 [email_row(result.broadcast, baker).address, email_row(result.broadcast, baker).status],
                 "a failed email in test mode still records the test address"
    assert_equal ["test+rbs-#{able.id}@example.com"], MailLog.where(broadcast_id: result.broadcast.id).pluck(:to_email)
  end

  test "a test address is used where sending to Rangers is not switched on" do
    person = listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    with_rangers_emailed(false) do
      with_ses do |calls|
        perform_enqueued_jobs { send_email }

        assert_equal ["test+#{person.id}@example.com"], calls.flat_map { |call| ses_addresses(call) }
      end
    end
  end

  # A job starts with a fresh Current, so the training server is marked the
  # way a real one is: by its environment.
  test "with a test address set, the sandbox and the training server still send nothing" do
    person = listening("Listener")
    set_test_address("test+?@example.com")

    with_ses do |calls|
      perform_enqueued_jobs { send_email }

      sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
      with_env(GroundHogDay::ENVIRONMENT_VAR => Current.time.to_s) { perform_enqueued_jobs { send_email } }

      assert_empty calls
    end

    assert_equal [Broadcast::STATUS_SENT] * 2,
                 BroadcastMessage.where(person_id: person.id, address_type: "email").pluck(:status)
  end

  # Test mode mirrors a real send: an address SES would refuse fails in the
  # test too, so a test turns up what the real thing would.
  test "with a test address, a Ranger's own unusable address still fails" do
    good = listening("Able")
    bad = listening("Baker")
    bad.update_columns(email: "...@example.com")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")

    result = nil
    with_ses do |calls|
      perform_enqueued_jobs { result = send_email }

      assert_equal ["test+#{good.id}@example.com"], calls.flat_map { |call| ses_addresses(call) }
    end

    assert_equal ["test+#{bad.id}@example.com", Broadcast::STATUS_INVALID_PARAMETER],
                 [email_row(result.broadcast, bad).address, email_row(result.broadcast, bad).status]
  end

  test "a test address that cannot be used sends nothing, and leaves no address to retry" do
    person = listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+??@example.com")

    result = nil
    assert_difference -> { ErrorLog.where(error_type: "rbs-email-not-sent").count }, 1 do
      with_ses do |calls|
        perform_enqueued_jobs { result = send_email }

        assert_empty calls
      end
    end

    row = email_row(result.broadcast, person)

    assert_equal ["", Broadcast::STATUS_SERVICE_FAIL], [row.address, row.status]
    assert_equal 1, result.broadcast.reload.email_failed
  end

  test "a retried email goes to the test address while one is set, and records it" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    broadcast, failed = failed_email(listener)
    test_address = "test+#{listener.id}@example.com"

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [[test_address]], calls.map { |call| ses_addresses(call) }, "never the Ranger's own address"
    end

    failed.reload

    assert_equal [Broadcast::STATUS_SENT, test_address, "ses-#{test_address}"],
                 [failed.status, failed.address, failed.message_id]
    assert_equal [test_address], MailLog.where(broadcast_id: broadcast.id).pluck(:to_email)
  end

  test "a retried email is held where sending to Rangers is not switched on" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)

    with_rangers_emailed(false) do
      with_ses do |calls|
        send_again(broadcast)

        assert_empty calls
      end
    end

    assert_equal Broadcast::STATUS_SENT, failed.reload.status
  end

  test "a retried text carries the same words as the first attempt" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE,
                                  sms_message: "Repeater down, report to HQ",
                                  subject: "Repeater down", recipient_count: 1,
                                  sent_sms: true, sms_failed: 1)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: listener.id,
                             address_type: "sms", address: listener.sms_number,
                             direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)

    fake = through_twilio { Rbs.retry_broadcast(broadcast, @sender.id) }

    assert_equal 1, fake.created_texts.size
    assert_includes fake.created_texts.first[:body], Rbs::SMS_SUFFIX.strip,
                    "a retried text must still say how to stop them"
  end

  test "a retry leaves the email count at the recount, and the Retry armed, until the job runs" do
    broadcast, = failed_email(reachable(callsign: "Listener"))
    broadcast.update!(email_failed: 5)

    Rbs.retry_broadcast(broadcast, @sender.id)

    assert_equal BroadcastMessage.count_fail(broadcast.id, "email"), broadcast.reload.email_failed
    assert_predicate broadcast, :retryable?,
                     "the button reads the rows; the shared lock and the per-batch reload stop a second click " \
                     "from sending twice"
  end

  # A Clubhouse-message broadcast keeps everyone it matched, whether or not any
  # other channel can reach them -- which is how someone with no address on
  # file reaches the email job at all.
  test "a person with no email on file does not stop the rest of the broadcast" do
    criteria = only_listener(send_email: true, send_clubhouse: true)
    Person.find_by(callsign: "Listener").update_columns(email: nil)

    perform_enqueued_jobs do
      result = Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria:,
                            message: { sms_message: nil, subject: "Hello", message: "Body",
                                       expires_at: nil })

      assert_equal 1, BroadcastMessage.where(broadcast_id: result.broadcast.id,
                                             address_type: "email").count
    end
  end

  test "recipients come back in callsign order" do
    %w[Zululu Alphabet Mikado].each { |callsign| reachable(callsign:) }

    people = Rbs.retrieve_recipients(Broadcast::TYPE_GENERAL,
                                     alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE],
                                     on_site: false, attending: false, training: Rbs::TRAINING_ANY,
                                     send_sms: true, send_email: true)
    listed = people.map { |person| person.callsign.to_s.downcase }

    assert_equal listed.sort, listed, "the review page is read in callsign order"
  end

  test "a Ranger who asked us to stop is not texted again" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_text(listener)
    listener.update!(sms_stopped: true)
    # Without this the sandbox answers before the service is ever asked, and an
    # empty call list would prove nothing.
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)

    fake = through_twilio { Rbs.retry_broadcast(broadcast, @sender.id) }

    assert_empty fake.created_texts, "a stopped number must not be handed to Twilio again"

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_not broadcast.retryable?
  end

  test "a Ranger who may no longer be messaged is not emailed again" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_email(listener)
    listener.update!(status: Person::DISMISSED)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      send_again(broadcast)

      assert_empty calls
    end

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_not broadcast.retryable?
  end

  # The row stays a failure, and is counted as one, though no Retry sends it.
  test "a message whose person is gone is not sent again, and stays a counted failure" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(Person.new(id: Person.maximum(:id) + 1, email: "gone@example.com"))

    assert_not broadcast.retryable?

    with_ses do |calls|
      send_again(broadcast)

      assert_empty calls
    end

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_equal [1, 1], [BroadcastMessage.count_fail(broadcast.id, "email"), broadcast.reload.email_failed]
  end

  test "a text to a number that is no longer confirmed is not sent again, and stays a counted failure" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_text(listener)
    listener.update!(sms_verified: false)
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)

    assert_not broadcast.retryable?

    fake = through_twilio { Rbs.retry_broadcast(broadcast, @sender.id) }

    assert_empty fake.created_texts
    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_equal [1, 1], [BroadcastMessage.count_fail(broadcast.id, "sms"), broadcast.reload.sms_failed]
  end

  test "a text to a number the Ranger has since changed is not sent again" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_text(listener)
    # Past the save callback, which would unconfirm the new number: the number
    # is all that differs.
    listener.update_columns(sms_number: "+14155559999")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)

    assert_not broadcast.retryable?

    fake = through_twilio { Rbs.retry_broadcast(broadcast, @sender.id) }

    assert_empty fake.created_texts, "never the old number, and never the new one either"

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
  end

  test "a Ranger who may be messaged again is sent their message on the next Retry" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)
    listener.update!(status: Person::DISMISSED)

    assert_not broadcast.retryable?

    listener.update!(status: Person::ACTIVE)

    assert_predicate broadcast, :retryable?
    with_ses do |calls|
      send_again(broadcast)

      assert_equal [[listener.email]], calls.map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, failed.reload.status
  end

  # The job reads each batch again through the same rule as the button.
  test "a Ranger dismissed between the Retry click and the job is not emailed, and stays failed" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)

    assert_enqueued_jobs(1, only: RbsRetryEmailJob) { Rbs.retry_broadcast(broadcast, @sender.id) }
    listener.update!(status: Person::DISMISSED)

    with_ses do |calls|
      perform_enqueued_jobs

      assert_empty calls
    end

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_equal 1, broadcast.reload.email_failed
  end

  test "a retry's result lists only the people it sent to again" do
    broadcast, = failed_email(reachable(callsign: "Able"))
    failed_row(broadcast, reachable(callsign: "Baker", status: Person::DISMISSED), Broadcast::STATUS_SERVICE_FAIL)
    failed_text_row(broadcast, reachable(callsign: "Charlie", stopped: true))

    result = Rbs.retry_broadcast(broadcast, @sender.id)
    statuses = result.people.flat_map { |person| [person.sms_status, person.email_status] }

    assert_equal ["Able"], result.people.map(&:callsign)
    assert_equal [false, true, 1], [result.sent_sms, result.sent_email, result.emails_queued]
    assert_not_includes statuses, Rbs::SMS_STATUS_NO_CONTACT, "no one reads \"opted out\""
  end

  test "the failures a Retry sends and the ones it won't make up every failure" do
    broadcast, retried = failed_email(reachable(callsign: "Able"))
    unconfirmed = failed_row(broadcast, reachable(callsign: "Baker"), Broadcast::STATUS_SEND_UNCONFIRMED)
    dismissed = failed_row(broadcast, reachable(callsign: "Charlie", status: Person::DISMISSED),
                           Broadcast::STATUS_SERVICE_FAIL)
    changed = failed_text_row(broadcast, reachable(callsign: "Dog"), address: "+14155559999")
    failed_row(broadcast, reachable(callsign: "Easy"), Broadcast::STATUS_SENT)
    failed_row(broadcast, reachable(callsign: "Fox"), Broadcast::STATUS_BOUNCED)
    gone = failed_row(broadcast, Person.new(id: Person.maximum(:id) + 1, email: "gone@example.com"),
                      Broadcast::STATUS_SERVICE_FAIL)

    assert_equal [retried.id], broadcast.failed_messages.pluck(:id)
    assert_equal [unconfirmed, dismissed, changed, gone].map(&:id).sort, broadcast.unretryable_messages.pluck(:id).sort
    assert_equal BroadcastMessage.count_fail(broadcast.id, "email") + BroadcastMessage.count_fail(broadcast.id, "sms"),
                 broadcast.failed_messages.count + broadcast.unretryable_messages.count
  end

  test "a broadcast counts every text and email its send tried, and none it skipped" do
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE, sms_message: "Hello",
                                  subject: "Hello", email_message: "Body", recipient_count: 7,
                                  sent_sms: true, sent_email: true)
    able = reachable(callsign: "Able")
    baker = reachable(callsign: "Baker")
    charlie = reachable(callsign: "Charlie")
    failed_row(broadcast, able, Broadcast::STATUS_SENT)
    failed_row(broadcast, baker, Broadcast::STATUS_BOUNCED)
    failed_row(broadcast, charlie, Broadcast::STATUS_SERVICE_FAIL)
    failed_row(broadcast, reachable(callsign: "Dog"), Broadcast::STATUS_SEND_UNCONFIRMED)
    failed_row(broadcast, reachable(callsign: "Easy"), Rbs::EMAIL_STATUS_NO_CONTACT)
    failed_row(broadcast, reachable(callsign: "Fox"), Rbs::EMAIL_STATUS_SUPPRESSED)
    failed_row(broadcast, Person.new(id: Person.maximum(:id) + 1, email: "gone@example.com"), Broadcast::STATUS_SENT)
    [[able, Broadcast::STATUS_SENT], [baker, Broadcast::STATUS_BLOCKED],
     [charlie, Broadcast::STATUS_SERVICE_FAIL]].each do |person, status|
      BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: person.id, address_type: "sms",
                               address: person.sms_number, direction: "outbound", status:)
    end
    BroadcastMessage.record(broadcast.id, Broadcast::STATUS_SENT, able.id, "clubhouse", able.callsign, "outbound")

    counts = assert_queries_count(1) { broadcast.attempted_counts }

    assert_equal({ "sms" => 3, "email" => 5, "clubhouse" => 1 }, counts)
    assert_empty Broadcast::FAILURE_STATUSES - Broadcast::ATTEMPTED_STATUSES, "Failed stays part of Texts plus Emails"
  end

  # ==========================================================================
  # Sending the failures again
  # ==========================================================================

  test "sending again reaches only the messages that failed" do
    listener = reachable(callsign: "Listener")
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE,
                                  sms_message: "Try again", subject: "Try again",
                                  email_message: "Body", recipient_count: 2,
                                  sent_sms: true, sent_email: false, sent_clubhouse: false,
                                  sms_failed: 1)
    failed = BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: listener.id,
                                      address_type: "sms", address: listener.sms_number,
                                      direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)
    already_sent = BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: listener.id,
                                            address_type: "sms", address: listener.sms_number,
                                            direction: "outbound", status: Broadcast::STATUS_SENT)

    result = nil
    perform_enqueued_jobs { result = Rbs.retry_broadcast(broadcast, @sender.id) }

    assert_equal Broadcast::STATUS_SENT, failed.reload.status, "held by the sandbox, as sent"
    assert_equal Broadcast::STATUS_SENT, already_sent.reload.status
    assert_equal 0, broadcast.reload.sms_failed
    assert_equal @sender.id, broadcast.retry_person_id
    assert_not_nil broadcast.retry_at
    assert_equal 1, result.texts_queued
  end

  # The click queues the texts and the job sends them, as on a send: until it
  # runs they are neither failures nor sent.
  test "sending a text again queues it for the job that sends a broadcast's first texts" do
    broadcast, failed = failed_text(reachable(callsign: "Listener"))

    Rbs.retry_broadcast(broadcast, @sender.id)

    assert_equal Broadcast::STATUS_QUEUED, failed.reload.status
    assert_equal 0, broadcast.reload.sms_failed
    assert_not_predicate broadcast, :retryable?
    assert_enqueued_with(job: RbsTransmitSmsJob, args: [broadcast.id, true])
  end

  test "sending again leaves the failure counted when it fails once more" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    broadcast = Broadcast.create!(sender_id: @sender.id, alert_id: Alert::SHIFT_CHANGE,
                                  sms_message: "Try again", subject: "Try again",
                                  recipient_count: 1, sent_sms: true, sms_failed: 1)
    BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: listener.id,
                             address_type: "sms", address: listener.sms_number,
                             direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)

    through_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.refusal(21211, "Invalid 'To' Phone Number") })) do
      Rbs.retry_broadcast(broadcast, @sender.id)
    end

    assert_equal 1, broadcast.reload.sms_failed
  end

  test "sending an email again delivers nothing while the sandbox is on" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_email(listener)

    with_ses do |calls|
      send_again(broadcast)

      assert_empty calls, "the sandbox must not deliver a retried email"
    end

    assert_equal Broadcast::STATUS_SENT, failed.reload.status
  end

  test "sending an email again goes through SES to the address it was meant for" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener, address: "listener-then@example.com")

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [["listener-then@example.com"]], calls.map { |call| ses_addresses(call) },
                   "the address it failed at, not whatever is on file now"
    end

    failed.reload

    assert_equal [Broadcast::STATUS_SENT, "ses-listener-then@example.com"], [failed.status, failed.message_id]
    assert_equal ["ses-listener-then@example.com"], MailLog.where(broadcast_id: broadcast.id).pluck(:message_id)
    assert_equal 0, broadcast.reload.email_failed
  end

  test "an email first sent to the test address goes there again on a live retry" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, = failed_email(listener, address: "test+#{listener.id}@example.com")

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [["test+#{listener.id}@example.com"]], calls.map { |call| ses_addresses(call) }
    end
  end

  test "with a test address set, a retry still sends nothing while the sandbox or the training server holds email" do
    listener = reachable(callsign: "Listener")
    set_test_address("test+?@example.com")
    held, held_row = failed_email(listener)

    with_ses do |calls|
      send_again(held)

      sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
      with_env(GroundHogDay::ENVIRONMENT_VAR => Current.time.to_s) do
        training, = failed_email(listener)
        send_again(training)
      end

      assert_empty calls
    end

    assert_equal Broadcast::STATUS_SENT, held_row.reload.status
  end

  test "a retry while the test address cannot be used sends nothing and keeps the row's address" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test@example.com")
    broadcast, failed = failed_email(listener)

    assert_difference -> { ErrorLog.where(error_type: "rbs-email-not-sent").count }, 1 do
      with_ses do |calls|
        send_again(broadcast)

        assert_empty calls
      end
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, listener.email], [failed.reload.status, failed.address],
                 "once the test is over, a Retry must still know where the email was meant to go"
  end

  test "an email sent since the Retry was pressed is not sent again" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)

    Rbs.retry_broadcast(broadcast, @sender.id)
    failed.update!(status: Broadcast::STATUS_SENT)

    with_ses do |calls|
      perform_enqueued_jobs

      assert_empty calls
    end
  end

  test "a retried email with an address SES could not take stays failed while the rest go" do
    good = reachable(callsign: "Able")
    blank = reachable(callsign: "Baker")
    malformed = reachable(callsign: "Charlie")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, good_row = failed_email(good)
    blank_row = failed_row(broadcast, blank, Broadcast::STATUS_SERVICE_FAIL, address: "")
    malformed_row = failed_row(broadcast, malformed, Broadcast::STATUS_SERVICE_FAIL, address: "...@example.com")

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [good.email], calls.flat_map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, good_row.reload.status
    assert_equal [Broadcast::STATUS_INVALID_PARAMETER] * 2, [blank_row.reload.status, malformed_row.reload.status]
    assert_equal "...@example.com", malformed_row.address
  end

  test "a broadcast whose failures cannot be retried still reads as failed, with nothing to send again" do
    able = reachable(callsign: "Able")
    broadcast, = failed_email(able, status: Broadcast::STATUS_INVALID_PARAMETER)
    failed_row(broadcast, reachable(callsign: "Baker"), Broadcast::STATUS_SEND_UNCONFIRMED)
    broadcast.update!(email_failed: BroadcastMessage.count_fail(broadcast.id, "email"))

    assert_equal 2, broadcast.email_failed
    assert_predicate broadcast, :failed?
    assert_includes Broadcast.with_failures, broadcast
    assert_includes DailyReportJob.new.send(:failed_broadcasts), broadcast
    assert_not broadcast.retryable?

    assert_no_enqueued_jobs(only: RbsRetryEmailJob) { Rbs.retry_broadcast(broadcast, @sender.id) }
  end

  test "a retry resends only what can go again, and leaves the rest as it was" do
    able = reachable(callsign: "Able")
    baker = reachable(callsign: "Baker")
    charlie = reachable(callsign: "Charlie")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, retried = failed_email(able)
    invalid = failed_row(broadcast, baker, Broadcast::STATUS_INVALID_PARAMETER)
    unconfirmed = failed_row(broadcast, charlie, Broadcast::STATUS_SEND_UNCONFIRMED)

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [able.email], calls.flat_map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, retried.reload.status
    assert_equal [[Broadcast::STATUS_INVALID_PARAMETER, baker.email, nil],
                  [Broadcast::STATUS_SEND_UNCONFIRMED, charlie.email, nil]],
                 [invalid, unconfirmed].map { |row| row.reload.slice(:status, :address, :message_id).values }
    assert_equal 2, broadcast.reload.email_failed
    assert_not broadcast.retryable?
  end

  test "an email SES throttled or rejected goes again, and records what happened this time" do
    able = reachable(callsign: "Able")
    baker = reachable(callsign: "Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, throttled = failed_email(able, status: "account-throttled")
    rejected = failed_row(broadcast, baker, "message-rejected")

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [able.email, baker.email].sort, calls.flat_map { |call| ses_addresses(call) }.sort
    end

    assert_equal [[Broadcast::STATUS_SENT, "ses-#{able.email}"], [Broadcast::STATUS_SENT, "ses-#{baker.email}"]],
                 [throttled, rejected].map { |row| row.reload.slice(:status, :message_id).values }
    assert_equal 0, broadcast.reload.email_failed
  end

  test "two Retry clicks queue two runs that take turns, and the second sends nothing again" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, = failed_email(listener)

    with_ses do |calls|
      assert_enqueued_jobs(2, only: RbsRetryEmailJob) { 2.times { Rbs.retry_broadcast(broadcast, @sender.id) } }
      perform_enqueued_jobs

      assert_equal 1, calls.size, "the second run must find the email already sent"
    end
  end

  test "a send and a retry share one lock, so only one email job runs at a time" do
    transmit = RbsTransmitEmailJob.new(1, Alert::SHIFT_CHANGE, @sender.id, [], "Hello", "Body", nil)
    retry_job = RbsRetryEmailJob.new(1, [2])

    # The test adapter ignores the lock, so its settings are what can be checked.
    assert_equal "rbs-email/rbs-email", transmit.concurrency_key
    assert_equal transmit.concurrency_key, retry_job.concurrency_key
    assert_equal [1, 3.hours], [RbsTransmitEmailJob.concurrency_limit, RbsTransmitEmailJob.concurrency_duration]
    assert_equal [1, 3.hours], [RbsRetryEmailJob.concurrency_limit, RbsRetryEmailJob.concurrency_duration]
    assert_equal [false, false], [RbsTransmitEmailJob, RbsRetryEmailJob].map(&:resume_errors_after_advancing),
                 "an error must never resume a job whose stopped batch may have gone"
  end

  # ==========================================================================
  # A job never sends less safely than when it was queued
  # ==========================================================================

  test "a queued job sends in the mode it was queued in, or a safer one" do
    {
      [nil, :live] => :live, ["", :test] => :test, [nil, :held] => :held, [nil, :misconfigured] => :misconfigured,
      ["live", :live] => :live, ["test", :test] => :test, ["held", :held] => :held,
      ["misconfigured", :misconfigured] => :misconfigured,
      ["held", :live] => :held, ["held", :test] => :held, ["held", :misconfigured] => :held,
      ["live", :held] => :held, ["test", :held] => :held, ["misconfigured", :held] => :held,
      ["live", :test] => :test, ["misconfigured", :test] => :test,
      ["test", :live] => :misconfigured, ["misconfigured", :live] => :misconfigured,
      ["live", :misconfigured] => :misconfigured, ["test", :misconfigured] => :misconfigured
    }.each do |(queued, now), mode|
      assert_equal mode, Rbs.effective_email_mode(queued, now), "queued #{queued.inspect}, now #{now}"
    end
  end

  test "Send and Retry record the mode, and a job queued before it was recorded still runs" do
    listener = listening("Able")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)

    send_email
    Rbs.retry_broadcast(broadcast, @sender.id)

    assert_equal [["live"], ["live"]], enqueued_jobs.map { |job| job[:args].last(1) }
    send_job = enqueued_jobs.find { |job| job[:job] == RbsTransmitEmailJob }
    clear_enqueued_jobs

    with_ses do |calls|
      # Without its last argument, the Send job is one queued before the mode was recorded.
      RbsTransmitEmailJob.perform_now(*ActiveJob::Arguments.deserialize(send_job[:args])[0...-1])
      RbsRetryEmailJob.perform_now(broadcast.id, [failed.id])

      assert_equal [[listener.email], [listener.email]], calls.map { |call| ses_addresses(call) }
    end
  end

  test "a broadcast queued for the test inbox sends nothing once the test address is cleared" do
    listener = listening("Able")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    result = send_email
    set_test_address("")

    with_ses do |calls|
      perform_enqueued_jobs

      assert_empty calls
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, ""],
                 email_row(result.broadcast, listener).slice(:status, :address).values,
                 "no address left behind for a live Retry to reach the Ranger with"
    assert_equal [result.broadcast.id, 1, "test", "live"],
                 ErrorLog.where(error_type: "rbs-email-not-sent").last.data
                         .values_at("broadcast_id", "people_not_sent", "queued", "now")
  end

  test "a retry queued for the test inbox sends nothing once the test address is cleared" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    broadcast, failed = failed_email(listener, status: "account-throttled")
    Rbs.retry_broadcast(broadcast, @sender.id)
    set_test_address("")

    assert_difference -> { ErrorLog.where(error_type: "rbs-email-not-sent").count }, 1 do
      with_ses do |calls|
        perform_enqueued_jobs

        assert_empty calls
      end
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, listener.email], [failed.reload.status, failed.address]
    assert_equal [broadcast.id, 1, "test", "live"],
                 ErrorLog.where(error_type: "rbs-email-not-sent").last.data
                         .values_at("broadcast_id", "people_not_sent", "queued", "now")
  end

  test "a broadcast queued to go to Rangers goes to the test address once one is set" do
    listener = listening("Able")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    send_email
    set_test_address("test+?@example.com")

    with_ses do |calls|
      perform_enqueued_jobs

      assert_equal [["test+#{listener.id}@example.com"]], calls.map { |call| ses_addresses(call) }
    end
  end

  test "turning the sandbox on mid-broadcast holds what has not gone yet" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    sandbox_on_during_first_call = lambda do |context|
      sandbox_on(Setting::BROADCAST_MAIL_SANDBOX)
      SesTestHelper::ACCEPT_ALL.call(context)
    end

    result = nil
    without_pacing do
      with_ses(sandbox_on_during_first_call) do |calls|
        perform_enqueued_jobs { result = send_email }

        assert_equal 1, calls.size
      end
    end

    rows = people.map { |person| email_row(result.broadcast, person) }

    assert_equal [Broadcast::STATUS_SENT] * 3, rows.map(&:status), "the two not yet gone are recorded held"
    assert_equal ["ses-#{people[0].email}", nil, nil], rows.map(&:message_id)
  end

  test "a run held at the start and let go part-way sends the rest through a client built then" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    set_send_rate("1")
    result = send_email
    sandbox = Setting.find_by(name: Setting::BROADCAST_MAIL_SANDBOX)
    sandbox.update!(value: "true")

    events = []
    record = Rbs.method(:record_email_batch)
    build = Rbs.method(:ses_client)
    # The first record is of the people who want no email -- none here.
    record_then_let_go = lambda do |*args|
      record.call(*args)
      next if args.last.empty?

      events << :recorded
      sandbox.update!(value: "false") if events.count(:recorded) == 1
    end
    counted_build = lambda do
      events << :client
      build.call
    end

    without_pacing do
      with_ses do |calls|
        standing_in_for(:record_email_batch, record_then_let_go) do
          standing_in_for(:ses_client, counted_build) { perform_enqueued_jobs }
        end

        assert_equal [["test+#{people[1].id}@example.com"], ["test+#{people[2].id}@example.com"]],
                     calls.map { |call| ses_addresses(call) }
      end
    end

    assert_equal [:recorded, :client, :recorded, :recorded], events, "built by the first batch that sends, once"
    rows = people.map { |person| email_row(result.broadcast, person) }

    assert_equal [Broadcast::STATUS_SENT] * 3, rows.map(&:status)
    assert_equal [nil, "ses-test+#{people[1].id}@example.com", "ses-test+#{people[2].id}@example.com"],
                 rows.map(&:message_id)
  end

  # ==========================================================================
  # No silent failures
  # ==========================================================================

  # A template that parses, so it saves, and still raises once it is drawn.
  def break_template
    template = MailTemplate.find_by!(tag: "rbs_mailer/broadcast")
    fixed = template.body
    template.update!(body: "{{ 1 | divided_by: 0 }}")
    # Built templates are kept per row version, so the mended one is new.
    -> { template.update!(body: fixed, updated_at: 1.minute.from_now) }
  end

  test "an email that will not draw stops the broadcast at once, says so once, and can be sent again" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    mend = break_template

    result = nil
    with_ses do |calls|
      perform_enqueued_jobs { result = send_email }

      assert_empty calls
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL] * 3, people.map { |person| email_row(result.broadcast, person).status }
    assert_equal 3, result.broadcast.reload.email_failed
    assert_equal 1, ErrorLog.where(error_type: "rbs-email-exception").count, "one log, not one per batch"
    assert_equal 0, ErrorLog.where(error_type: "rbs-email-given-up").count

    mend.call
    with_ses do |calls|
      without_pacing { send_again(result.broadcast) }

      assert_equal people.map(&:email), calls.flat_map { |call| ses_addresses(call) }
    end

    assert_equal 0, result.broadcast.reload.email_failed
  end

  test "an email that will not draw in test mode keeps the test address, so no later Retry reaches the Ranger" do
    listener = listening("Able")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    mend = break_template

    result = nil
    with_ses { perform_enqueued_jobs { result = send_email } }

    row = email_row(result.broadcast, listener)

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, "test+#{listener.id}@example.com"], [row.status, row.address]

    mend.call
    set_test_address("")
    with_ses do |calls|
      send_again(result.broadcast)

      assert_equal [["test+#{listener.id}@example.com"]], calls.map { |call| ses_addresses(call) },
                   "live now, and still only the test inbox"
    end
  end

  test "no SES account stops the broadcast at once and says so once" do
    people = %w[Able Baker].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")

    result = nil
    with_ses do |calls|
      without_ses_account { perform_enqueued_jobs { result = send_email } }

      assert_empty calls
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL] * 2, people.map { |person| email_row(result.broadcast, person).status }
    assert_equal 2, result.broadcast.reload.email_failed
    assert_match(/region/i, ErrorLog.where(error_type: "rbs-email-exception").sole.data.dig("exception", "message"))
  end

  test "a retry that cannot draw or send its email leaves the failures counted and the Retry armed" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(reachable(callsign: "Listener"), status: "account-throttled")

    without_ses_account { send_again(broadcast) }

    assert_equal Broadcast::STATUS_SERVICE_FAIL, failed.reload.status
    assert_equal 1, broadcast.reload.email_failed
    assert_predicate broadcast, :retryable?
  end

  test "a send stopped part-way leaves no one without a row, and never leaves a call SES took to send again" do
    able = listening("Able")
    baker = listening("Baker")
    charlie = listening("Charlie")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    refuse_able = SesTestHelper.refusing(able.email => "MESSAGE_REJECTED")
    # Able's batch is written down; Baker's, which SES took, is lost once.
    bakers_batch = ->(outcomes) { outcomes.any? { |person, _address, _status, id| person.id == baker.id && id } }

    result = send_email
    without_pacing do
      with_ses(refuse_able) do |calls|
        losing_batch(picks: bakers_batch) do
          assert_raises(ActiveRecord::StatementInvalid) { perform_enqueued_jobs }
        end

        assert_equal 2, calls.size, "stopped after Baker's call; Charlie's was never made"
      end
    end

    logged = ErrorLog.where(error_type: "rbs-email-unrecorded").sole.data

    assert_equal [[baker.id], { baker.id.to_s => "ses-#{baker.email}" }], logged.values_at("person_ids", "ses_ids")
    assert_equal ["message-rejected", Broadcast::STATUS_SEND_UNCONFIRMED, Broadcast::STATUS_SERVICE_FAIL],
                 [able, baker, charlie].map { |person| email_row(result.broadcast, person).status },
                 "Baker may have been sent, so never again; Charlie was never reached, so a Retry can"
    assert_equal 3, result.broadcast.reload.email_failed, "the page reads failed, never Delivered"
    assert_equal [able.id, charlie.id].sort, result.broadcast.failed_messages.pluck(:person_id).sort
  end

  test "a retry stopped part-way never leaves a call SES took to send again" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, failed = failed_email(listener)

    Rbs.retry_broadcast(broadcast, @sender.id)
    with_ses do
      losing_batch(:record_retried_batch) do
        assert_raises(ActiveRecord::StatementInvalid) { perform_enqueued_jobs }
      end
    end

    assert_equal Broadcast::STATUS_SEND_UNCONFIRMED, failed.reload.status
    assert_equal 1, ErrorLog.where(error_type: "rbs-email-unrecorded").count
    assert_equal 1, broadcast.reload.email_failed
    assert_not broadcast.retryable?, "SES took it, so a second Retry must not send it again"
  end

  test "a send stopped while email is held records the rest held, never for a later Retry to send" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    sandbox_on_during_first_call = lambda do |context|
      sandbox_on(Setting::BROADCAST_MAIL_SANDBOX)
      SesTestHelper::ACCEPT_ALL.call(context)
    end
    bakers_batch = ->(outcomes) { outcomes.any? { |person, *| person.id == people[1].id } }

    result = send_email
    without_pacing do
      with_ses(sandbox_on_during_first_call) do
        losing_batch(picks: bakers_batch) do
          assert_raises(ActiveRecord::StatementInvalid) { perform_enqueued_jobs }
        end
      end
    end

    assert_equal [Broadcast::STATUS_SENT] * 3, people.map { |person| email_row(result.broadcast, person).status }
    assert_not result.broadcast.reload.retryable?, "held is never a failure a live Retry would send to the Ranger"
    assert_equal 0, result.broadcast.email_failed
  end

  test "a call SES only partly took, then lost, leaves the people it refused to send again" do
    able = listening("Able")
    baker = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    refuse_able = SesTestHelper.refusing(able.email => "MESSAGE_REJECTED")

    result = send_email
    with_ses(refuse_able) do
      losing_batch(picks: ->(outcomes) { outcomes.any? }) do
        assert_raises(ActiveRecord::StatementInvalid) { perform_enqueued_jobs }
      end
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, Broadcast::STATUS_SEND_UNCONFIRMED],
                 [able, baker].map { |person| email_row(result.broadcast, person).status },
                 "SES refused Able, so a Retry may try again; it took Baker, so never again"
  end

  test "a failed call whose log cannot be written still records what happened, and the send goes on" do
    people = %w[Able Baker].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    first = true
    never_connects_first = lambda do |context|
      if first
        first = false
        raise Seahorse::Client::NetworkingError, Net::OpenTimeout.new
      end
      SesTestHelper::ACCEPT_ALL.call(context)
    end
    original = ErrorLog.method(:record_exception)
    ErrorLog.define_singleton_method(:record_exception) { |*, **| raise ActiveRecord::ConnectionTimeoutError, "busy" }

    result = send_email
    without_pacing { with_ses(never_connects_first) { perform_enqueued_jobs } }

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, Broadcast::STATUS_SENT],
                 people.map { |person| email_row(result.broadcast, person).status }
  ensure
    ErrorLog.define_singleton_method(:record_exception, original)
  end

  test "the count is kept as each batch is written down, not only at the end" do
    people = %w[Able Baker].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    result = nil
    counted = []
    refuse = SesTestHelper.refusing(people[0].email => "MESSAGE_REJECTED")
    refuse_first = lambda do |context|
      counted << result.broadcast.reload.email_failed
      refuse.call(context)
    end

    result = send_email
    without_pacing { with_ses(refuse_first) { perform_enqueued_jobs } }

    assert_equal [0, 1], counted, "Able's refusal is counted before Baker's call"
  end

  test "winding up a run never hides what stopped it" do
    failing = ->(*) { raise ActiveRecord::ConnectionNotEstablished, "gone" }

    standing_in_for(:recount_email_failed, failing) do
      assert_nothing_raised { Rbs.send(:wind_up, nil, 1, stopped_by: RuntimeError.new("the real one")) }
      assert_raises(ActiveRecord::ConnectionNotEstablished) { Rbs.send(:wind_up, nil, 1, stopped_by: nil) }
    end
  end

  test "whether email may go out is read from the setting itself, never a stale copy" do
    with_cache_store do |cache|
      cache.write(Setting::BROADCAST_MAIL_SANDBOX, "false")
      cache.write(Setting::BROADCAST_MAIL_TEST_ADDRESS, "test+?@example.com")

      assert_equal :held, Rbs.email_mode, "the sandbox is on in the table"
      assert_equal "", Rbs.test_address_pattern
    end
  end

  # ==========================================================================
  # No duplicate sends
  # ==========================================================================

  test "a send stopped between batches picks up after the last one, sends no one twice, and counts honestly" do
    people = %w[Able Baker Charlie].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    refuse_able = SesTestHelper.refusing(people[0].email => "MESSAGE_REJECTED")
    result = send_email

    without_pacing do
      with_ses(refuse_able) do |calls|
        interrupt_job_during_step(RbsTransmitEmailJob, :deliver) { perform_enqueued_jobs }

        assert_equal 1, calls.size, "stopped at the first checkpoint"
        assert_equal 1, result.broadcast.reload.email_failed, "counted on the way out"

        perform_enqueued_jobs

        assert_equal people.map(&:email), calls.flat_map { |call| ses_addresses(call) }
      end
    end

    assert_equal 3, BroadcastMessage.where(broadcast_id: result.broadcast.id, address_type: "email").count
    assert_equal BroadcastMessage.count_fail(result.broadcast.id, "email"), result.broadcast.reload.email_failed
  end

  test "a retry stopped between batches picks up after the last one, and sends no one twice" do
    people = %w[Able Baker Charlie].map { |callsign| reachable(callsign:) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    broadcast, = failed_email(people[0])
    people.drop(1).each { |person| failed_row(broadcast, person, Broadcast::STATUS_SERVICE_FAIL) }
    Rbs.retry_broadcast(broadcast, @sender.id)

    without_pacing do
      with_ses do |calls|
        interrupt_job_during_step(RbsRetryEmailJob, :deliver) { perform_enqueued_jobs }

        assert_equal 1, calls.size, "stopped at the first checkpoint"
        assert_equal 2, broadcast.reload.email_failed, "counted on the way out"

        perform_enqueued_jobs

        assert_equal people.map(&:email).sort, calls.flat_map { |call| ses_addresses(call) }.sort
      end
    end

    assert_equal 0, broadcast.reload.email_failed
  end

  test "a send run again sends only to those it has not already written down" do
    able = listening("Able")
    baker = listening("Baker")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    result = send_email
    # What an earlier run of the same job got as far as writing down.
    BroadcastMessage.record_outbound(result.broadcast.id, "email", [{ person_id: able.id, address: able.email,
                                                                      status: Broadcast::STATUS_SENT, message_id: "ses-earlier" }])

    with_ses do |calls|
      perform_enqueued_jobs

      assert_equal [[baker.email]], calls.map { |call| ses_addresses(call) }
    end

    assert_equal 1, BroadcastMessage.where(broadcast_id: result.broadcast.id, person_id: able.id).count
  end

  # ==========================================================================
  # Corners the plan audit found untested
  # ==========================================================================

  test "an email with a plain-text part sends that part too, through its own placeholder" do
    listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    MailTemplate.find_by!(tag: "rbs_mailer/broadcast")
                .update!(text_body: "Plain text: {{ broadcast_subject }}", updated_at: 1.minute.from_now)

    with_ses do |calls|
      perform_enqueued_jobs { send_email(subject: "Muster at HQ") }

      template = calls.first[:default_content][:template]

      assert_equal({ subject: "{{subject}}", html: "{{html}}", text: "{{text}}" }, template[:template_content])
      assert_includes JSON.parse(template[:template_data])["text"], "Plain text: Muster at HQ",
                      "a placeholder with no data behind it makes SES drop the email"
    end
  end

  test "an email whose content cannot be handed to SES stops the broadcast at once, before any call" do
    people = %w[Able Baker].map { |callsign| listening(callsign) }
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_send_rate("1")
    # Reading the From address is the step here that can fail on an odd value.
    no_from = ->(*) { raise NoMethodError, "undefined method 'value' for nil" }

    result = nil
    with_ses do |calls|
      standing_in_for(:ses_content, no_from) { perform_enqueued_jobs { result = send_email } }

      assert_empty calls
    end

    assert_equal [Broadcast::STATUS_SERVICE_FAIL] * 2, people.map { |person| email_row(result.broadcast, person).status }
    assert_equal 1, ErrorLog.where(error_type: "rbs-email-exception").count
  end

  test "a retry stopped before its first batch is written down still leaves an honest count" do
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    broadcast, = failed_email(reachable(callsign: "Listener"))
    Rbs.retry_broadcast(broadcast, @sender.id)
    # As a Retry queued by an earlier Clubhouse left it: zeroed until its job ran.
    broadcast.update_columns(email_failed: 0)

    with_ses do
      losing_batch(:record_retried_batch) do
        assert_raises(ActiveRecord::StatementInvalid) { perform_enqueued_jobs }
      end
    end

    assert_equal 1, broadcast.reload.email_failed, "recounted on the way out, so the page never reads Delivered"
  end

  test "a new-message text says when the message is a group one" do
    assert_match(/\AYou have a new Ranger Clubhouse msg from HQ\. Subject: Hello/, Rbs.send(:notify_text, "HQ", "Hello"))
    assert_match(/\AYou have a new Ranger Clubhouse group msg from Green Dot Cadre\. Subject: Hello/,
                 Rbs.send(:notify_text, "Green Dot Cadre", "Hello", group: true))
  end

  # A new-message text goes through the Messaging Service, never Notify, and
  # its row keeps the SID Twilio gave it.
  test "a new-message text goes through the Messaging Service, its row keeping Twilio's SID" do
    person = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    configure_twilio
    fake = FakeTwilioClient.new

    with_fake_twilio(fake) { Rbs.message_notify(person, @sender.id, "HQ", "Hello", "Body") }

    row = alert_row(person, "sms")

    assert_equal [person.sms_number], fake.created_texts.pluck(:to)
    assert_empty fake.notifications
    assert_equal [Broadcast::STATUS_SENT, format("SM%032d", 1)], [row.status, row.message_id]
    assert_equal 0, row.broadcast.sms_failed
  end

  test "a new-message text Twilio may have taken is send-unconfirmed, and one it refused failed" do
    taken = reachable(callsign: "Taken")
    refused = reachable(callsign: "Refused")
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    configure_twilio

    with_fake_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.read_timeout })) do
      Rbs.message_notify(taken, @sender.id, "HQ", "Hello", "Body")
    end
    with_fake_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.refusal(21610, "Attempt to send to unsubscribed recipient") })) do
      Rbs.message_notify(refused, @sender.id, "HQ", "Hello", "Body")
    end

    assert_equal [Broadcast::STATUS_SEND_UNCONFIRMED, nil, 1],
                 alert_row(taken, "sms").then { |row| [row.status, row.message_id, row.broadcast.sms_failed] }
    assert_equal [Broadcast::STATUS_SERVICE_FAIL, nil, 1],
                 alert_row(refused, "sms").then { |row| [row.status, row.message_id, row.broadcast.sms_failed] }
    assert_equal 2, ErrorLog.where(error_type: "sms-exception").count
  end

  test "the text sandbox holds a new-message text: recorded as sent, and Twilio never asked" do
    person = reachable(callsign: "Listener")
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    configure_twilio
    fake = FakeTwilioClient.new

    with_fake_twilio(fake) { Rbs.message_notify(person, @sender.id, "HQ", "Hello", "Body") }

    assert_empty fake.asked
    assert_equal [Broadcast::STATUS_SENT, nil], alert_row(person, "sms").then { |row| [row.status, row.message_id] }
  end

  test "a new-message alert goes to the test address while one is set" do
    person = reachable(callsign: "Listener")
    bounced = reachable(callsign: "Bounced")
    suppress_email(bounced.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+?@example.com")
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    ActionMailer::Base.deliveries.clear

    with_ses do |calls|
      perform_enqueued_jobs do
        Rbs.message_notify(person, @sender.id, "HQ", "Hello", "Body")
        Rbs.message_notify(bounced, @sender.id, "HQ", "Hello", "Body")
      end

      assert_empty calls, "alerts stay on ActionMailer (decision 6)"
    end

    sent, skipped = alert_row(person), alert_row(bounced)

    assert_equal [["test+#{person.id}@example.com"]], ActionMailer::Base.deliveries.map(&:to)
    assert_equal [Broadcast::STATUS_SENT, "test+#{person.id}@example.com"], [sent.status, sent.address]
    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, bounced.email], [skipped.status, skipped.address],
                 "a skip row keeps the Ranger's own address"
  end

  test "a new-message alert with a test address that can't be used sends nothing and records the failure" do
    person = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    set_test_address("test+??@example.com")
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      Rbs.message_notify(person, @sender.id, "HQ", "Hello", "Body")
    end

    row = alert_row(person)

    assert_equal [Broadcast::STATUS_SERVICE_FAIL, ""], [row.status, row.address]
    assert_equal 1, row.broadcast.email_failed
  end

  # message_notify asks the record itself before it queues the alert, so a
  # suppressed address gets nothing queued and its row says why, as Send's
  # skip rows do. Bounced can't be texted either, and still gets the alert's
  # Broadcast and that row. SuppressedRecipientsInterceptor is the backstop
  # (see below).
  test "a new-message alert to a suppressed address sends nothing, and one to a live address goes" do
    bounced = reachable(callsign: "Bounced", verified: false)
    listener = reachable(callsign: "Listener")
    suppress_email(bounced.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    ActionMailer::Base.deliveries.clear

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      Rbs.message_notify(bounced, @sender.id, "HQ", "Hello", "Body")
    end

    row = alert_row(bounced)

    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, bounced.email, "Body"], [row.status, row.address, row.message]
    assert row.broadcast.sent_email, "the channel chosen, not whether anything went"
    assert_equal 0, row.broadcast.email_failed
    assert_equal 0, row.broadcast.attempted_counts.fetch("email", 0)

    perform_enqueued_jobs { Rbs.message_notify(listener, @sender.id, "HQ", "Hello", "Body") }

    assert_equal [[listener.email]], ActionMailer::Base.deliveries.map(&:to)
    assert_equal Broadcast::STATUS_SENT, alert_row(listener).status
    assert_empty ActionLog.where(event: "email-suppressed"), "the row is the record of the skip"
  end

  test "a new-message alert under the mail sandbox queues nothing, and still records a suppressed address" do
    bounced = reachable(callsign: "Bounced")
    listener = reachable(callsign: "Listener")
    suppress_email(bounced.email)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")

    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      Rbs.message_notify(bounced, @sender.id, "HQ", "Hello", "Body")
      Rbs.message_notify(listener, @sender.id, "HQ", "Hello", "Body")
    end

    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, Broadcast::STATUS_SENT],
                 [bounced, listener].map { |person| alert_row(person).status }
  end

  # A test runs with the query cache on, so each counted block is the first to
  # ask about its address. Quiet takes texts only, and can be texted, so their
  # alert gets past both of message_notify's early returns.
  test "a new-message alert asks the record once when it would email, and not at all when it wouldn't" do
    listener = reachable(callsign: "Listener")
    bounced = reachable(callsign: "Bounced")
    suppress_email(bounced.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    lookup = /FROM `email_suppression`/

    assert_queries_match(lookup, count: 1) { Rbs.message_notify(listener, @sender.id, "HQ", "Hello", "Body") }
    assert_queries_match(lookup, count: 1) { Rbs.message_notify(bounced, @sender.id, "HQ", "Hello", "Body") }

    quiet = reachable(callsign: "Quiet")
    suppress_email(quiet.email)
    alert_id = Rbs.during_event? ? Alert::CLUBHOUSE_NOTIFY_ON_PLAYA : Alert::CLUBHOUSE_NOTIFY_PRE_EVENT
    PersonAlert.create!(person_id: quiet.id, alert_id:, use_sms: true, use_email: false)

    assert_no_queries_match(lookup) { Rbs.message_notify(quiet, @sender.id, "HQ", "Hello", "Body") }
    text = alert_row(quiet, "sms")

    assert_equal Broadcast::STATUS_SENT, text.status
    assert_not BroadcastMessage.exists?(person_id: quiet.id, address_type: "email")
    assert_not text.broadcast.sent_email
  end

  # Passes with or without message_notify's own check: it pins the backstop.
  # An address suppressed after the alert was queued is
  # SuppressedRecipientsInterceptor's, which drops the email and logs the skip,
  # while the row keeps saying sent (accepted, as Send's own case is below).
  test "a new-message alert to an address suppressed after it was queued is dropped at delivery" do
    listener = reachable(callsign: "Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    Setting.find_or_initialize_by(name: Setting::BROADCAST_CLUBHOUSE_NOTIFY).update!(value: "true")
    ActionMailer::Base.deliveries.clear

    Rbs.message_notify(listener, @sender.id, "HQ", "Hello", "Body")
    suppress_email(listener.email)
    perform_enqueued_jobs

    assert_empty ActionMailer::Base.deliveries
    assert_equal 1, ActionLog.where(event: "email-suppressed").count
    assert_equal Broadcast::STATUS_SENT, alert_row(listener).status
  end

  # ==========================================================================
  # Addresses that bounced for good or reported spam (EmailSuppression)
  # ==========================================================================

  # Rangers one kind of broadcast reaches, and the criteria that reach them.
  # All are on site, so the call-ups find them.
  def audience(type, callsigns)
    position = positions(:ood_position)
    people = callsigns.map { |callsign| reachable(callsign:, on_site: true) }

    criteria = case type
               when Broadcast::TYPE_ONSHIFT
                 people.each { |person| on_shift(person) }
                 {}
               when Broadcast::TYPE_POSITION, Broadcast::TYPE_RECRUIT_POSITION
                 people.each { |person| PersonPosition.create!(person_id: person.id, position_id: position.id) }
                 listener_criteria(send_sms: true, send_email: true)
               when Broadcast::TYPE_SLOT
                 slot = event_slot(position)
                 people.each { |person| sign_up(person, slot) }
                 { alert_id: Alert::SHIFT_CHANGE, slot_id: slot.id, send_sms: true, send_email: true }
               when Broadcast::TYPE_GENERAL
                 { alert_id: Alert::SHIFT_CHANGE, statuses: [Person::ACTIVE], on_site: false, attending: false,
                   training: Rbs::TRAINING_ANY, send_sms: true, send_email: true }
               else
                 {} # the emergency and the Dirt call-up reach everyone on site who is off duty
               end
    [people, criteria]
  end

  # A text and an email to everyone listening, so someone email cannot reach
  # is still sent to, and the email job still carries them.
  def send_text_and_email
    Rbs.transmit(type: Broadcast::TYPE_POSITION, sender: @sender, criteria: listener_criteria(send_sms: true, send_email: true),
                 message: { sms_message: "Hello", subject: "Hello", message: "Body", expires_at: nil })
  end

  test "an address that bounced or was reported as spam is not emailed, in every kind of broadcast" do
    Rbs::PAGE_TYPES.each_with_index do |type, index|
      (bounced, spam), criteria = audience(type, ["Bounced#{index}", "Spam#{index}"])
      suppress_email(bounced.email)
      suppress_email(spam.email, reason: EmailSuppression::COMPLAINT)

      listed = Rbs.retrieve_recipients(type, criteria).index_by(&:id)

      [bounced, spam].each do |person|
        found = listed[person.id]

        assert_not_nil found, "#{type} still lists #{person.callsign}, for the text"
        assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, false, true], [found.email_status, found.use_email, found.use_sms],
                     "#{type}: #{person.callsign}"
      end
    end
  end

  test "someone a suppressed address leaves with no way to reach them drops out, as with no address" do
    listener = listening("Listener")
    suppress_email(listener.email)

    assert_empty Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, listener_criteria(send_email: true))

    kept = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, listener_criteria(send_email: true, send_clubhouse: true))

    assert_equal [listener.id, Rbs::EMAIL_STATUS_SUPPRESSED, false], kept.sole.to_h.values_at(:id, :email_status, :use_email),
                 "a Clubhouse message still reaches them"
  end

  # Neither is emailed. The sender is shown the reason that holds whatever the
  # Ranger chooses, and the record keeps an opt-out apart from it.
  test "a suppressed address is named ahead of an opt-out, and an opt-out alone is still recorded as one" do
    both = listening("Both")
    opted_out = listening("OptedOut")
    [both, opted_out].each do |person|
      PersonAlert.create!(person_id: person.id, alert_id: Alert::SHIFT_MUSTER, use_sms: true, use_email: false)
    end
    suppress_email(both.email)

    listed = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, listener_criteria(send_sms: true, send_email: true))

    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, Rbs::EMAIL_STATUS_NO_CONTACT],
                 [both, opted_out].map { |person| listed.find { it.id == person.id }.email_status }

    result = nil
    perform_enqueued_jobs { result = send_text_and_email }

    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, Rbs::EMAIL_STATUS_NO_CONTACT],
                 [both, opted_out].map { |person| email_row(result.broadcast, person).status }
  end

  # Clubhouse 2 stored addresses as typed. update_columns would run Person's
  # normalizer, so the stored case is written in SQL.
  test "an address stored in mixed case is skipped the same way, and recorded as stored" do
    listener = listening("Listener")
    Person.where(id: listener.id).update_all("email = 'Listener@Example.COM'")
    suppress_email("listener@example.com")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    criteria = listener_criteria(send_sms: true, send_email: true)

    assert_equal "Listener@Example.COM", Person.where(id: listener.id).pick(:email)
    assert_equal Rbs::EMAIL_STATUS_SUPPRESSED, Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, criteria).sole.email_status

    result = nil
    with_ses do |calls|
      perform_enqueued_jobs { result = send_text_and_email }

      assert_empty calls
    end

    row = email_row(result.broadcast, listener)

    assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, "Listener@Example.COM"], [row.status, row.address],
                 "RBS does no normalizing of its own"
  end

  # Held, test address, live, and a test address that cannot be used.
  test "a suppressed address is never handed to SES, and its row says why, in every mode" do
    able = listening("Able")
    bounced = listening("Baker")
    spam = listening("Charlie")
    suppress_email(bounced.email)
    suppress_email(spam.email, reason: EmailSuppression::COMPLAINT)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    { live: [able.email], test: ["test+#{able.id}@example.com"], misconfigured: [], held: [] }.each do |mode, sent_to|
      set_test_address("test+?@example.com") if mode == :test
      set_test_address("test@example.com") if mode == :misconfigured
      sandbox_on(Setting::BROADCAST_MAIL_SANDBOX) if mode == :held

      assert_equal mode, Rbs.email_mode

      result = nil
      with_ses do |calls|
        perform_enqueued_jobs { result = send_text_and_email }

        assert_equal sent_to, calls.flat_map { |call| ses_addresses(call) }, mode
      end

      assert_equal 1, result.emails_queued, "#{mode}: only Able is queued"
      [bounced, spam].each do |person|
        row = email_row(result.broadcast, person)

        assert_equal [Rbs::EMAIL_STATUS_SUPPRESSED, person.email, nil], [row.status, row.address, row.message_id],
                     "#{mode}: #{person.callsign}"
      end
      assert_empty MailLog.where(broadcast_id: result.broadcast.id, person_id: [bounced.id, spam.id]), mode
    end
  end

  test "an emergency does not email a suppressed address, and still texts it" do
    quiet = reachable(callsign: "Quiet", on_site: true)
    PersonAlert.create!(person_id: quiet.id, alert_id: Alert::EMERGENCY_BROADCAST, use_sms: false, use_email: false)
    suppress_email(quiet.email, reason: EmailSuppression::COMPLAINT)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX, Setting::BROADCAST_SMS_SANDBOX)

    result = nil
    fake = nil
    with_ses do |calls|
      fake = through_twilio do
        result = Rbs.transmit(type: Broadcast::TYPE_EMERGENCY, sender: @sender, criteria: {},
                              message: { sms_message: "All hands", subject: nil, message: nil, expires_at: nil })
      end

      assert_not_includes calls.flat_map { |call| ses_addresses(call) }, quiet.email
    end

    assert_includes fake.created_texts.pluck(:to), quiet.sms_number,
                    "an emergency overrides the choice not to be texted"

    assert_equal Rbs::EMAIL_STATUS_SUPPRESSED, email_row(result.broadcast, quiet).status
  end

  # An emergency overrides only the choice not to be contacted, so someone with
  # no usable number and no address it may email gets nothing. It still lists
  # them, so its pages can name them, and counts only the people it reaches.
  test "an emergency keeps someone no channel reaches, and leaves them out of the count" do
    heard = reachable(callsign: "Heard", on_site: true)
    alone = reachable(callsign: "Alone", sms: "", on_site: true)
    suppress_email(alone.email)
    # nil, not "": person.email has a unique index.
    blank = reachable(callsign: "Blank", sms: "", on_site: true)
    blank.update_column(:email, nil)

    people = Rbs.retrieve_recipients(Broadcast::TYPE_EMERGENCY, {})
    listed = people.index_by(&:id)

    assert_equal [Rbs::SMS_STATUS_NO_PHONE, Rbs::EMAIL_STATUS_SUPPRESSED, false, false],
                 listed.fetch(alone.id).to_h.values_at(:sms_status, :email_status, :use_sms, :use_email)
    assert_equal [Rbs::SMS_STATUS_NO_PHONE, Rbs::EMAIL_STATUS_NO_ADDRESS, false, false],
                 listed.fetch(blank.id).to_h.values_at(:sms_status, :email_status, :use_sms, :use_email)

    unreached = callsigns(Rbs.unreachable(people, send_clubhouse: false))

    assert_includes unreached, alone.callsign
    assert_includes unreached, blank.callsign
    assert_not_includes unreached, heard.callsign
    assert_equal people.size - 2, Rbs.receiver_estimate(Broadcast::TYPE_EMERGENCY)
  end

  # A Clubhouse-only broadcast lists everyone with neither channel, which is
  # why the caller has to say whether the broadcast sends a Clubhouse message.
  test "a Clubhouse message reaches everyone listed, so no one is unreachable" do
    listener = listening("Listener")
    suppress_email(listener.email)

    kept = Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, listener_criteria(send_email: true, send_clubhouse: true))

    assert_empty Rbs.unreachable(kept, send_clubhouse: true)
    assert_equal [listener.callsign], callsigns(Rbs.unreachable(kept, send_clubhouse: false))
  end

  test "a suppressed address is a reason, not a failure" do
    assert_includes Broadcast::MESSAGE_STATUSES, Rbs::EMAIL_STATUS_SUPPRESSED, "the message log filters by it"
    assert_not_includes Broadcast::FAILURE_STATUSES, Rbs::EMAIL_STATUS_SUPPRESSED
    assert_not_includes Broadcast::RETRYABLE_STATUSES, Rbs::EMAIL_STATUS_SUPPRESSED
    assert_not_equal Broadcast::STATUS_BOUNCED, Rbs::EMAIL_STATUS_SUPPRESSED, "bounced is an email SES reported"

    listening("Able")
    suppress_email(listening("Baker").email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = nil
    with_ses { perform_enqueued_jobs { result = send_text_and_email } }
    broadcast = result.broadcast.reload

    assert_equal 0, broadcast.email_failed
    assert_not broadcast.failed?
    assert_not broadcast.retryable?, "nothing for the Retry button to send"
  end

  # The two statuses broadcast_email records for someone it skips. The message
  # log reads and filters each one, and neither is a failure.
  test "a skip the email send records is one the log can filter by, never a failure" do
    [Rbs::EMAIL_STATUS_SUPPRESSED, Rbs::EMAIL_STATUS_NO_CONTACT].each do |status|
      assert_includes Broadcast::MESSAGE_STATUSES, status, "the message log filters by it"
      assert_not_includes Broadcast::FAILURE_STATUSES, status
      assert_not_includes Broadcast::RETRYABLE_STATUSES, status
      assert_not_includes Broadcast::EMAIL_FAIL_STATUSES, status
    end

    [Rbs::SMS_STATUS_NO_CONTACT, Rbs::EMAIL_STATUS_NO_CONTACT, Broadcast::STATUS_NO_CONTACT].each do |status|
      assert_equal "no-contact", status, "rows already written keep their status"
    end
  end

  # The job carries what Send settled -- an id, and whether email may be used
  # -- and reads why not from the person it loads. A job queued before the
  # reason existed carries the same pairs.
  test "the email job keeps its pairs, and a job queued with them records why it skipped someone" do
    able = listening("Able")
    baker = listening("Baker")
    suppress_email(baker.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = send_text_and_email
    args = ActiveJob::Arguments.deserialize(enqueued_jobs.select { |job| job[:job] == RbsTransmitEmailJob }.sole[:args])
    clear_enqueued_jobs

    assert_equal [[able.id, true], [baker.id, false]], args[3]

    with_ses do |calls|
      RbsTransmitEmailJob.perform_now(*args)

      assert_equal [[able.email]], calls.map { |call| ses_addresses(call) }
    end

    assert_equal [Broadcast::STATUS_SENT, Rbs::EMAIL_STATUS_SUPPRESSED],
                 [able, baker].map { |person| email_row(result.broadcast, person).status }
  end

  # Send works out the recipients the way the preview does. A test runs with
  # the query cache on, so each block must be the first to ask.
  test "a Send and its email job each ask the record once, never once a person" do
    listening("Able")
    suppress_email(listening("Baker").email)
    suppress_email(listening("Charlie").email, reason: EmailSuppression::COMPLAINT)
    lookup = /FROM `email_suppression`/

    assert_queries_match(lookup, count: 1) { send_text_and_email }
    assert_queries_match(lookup, count: 1) { perform_enqueued_jobs }
  end

  test "an address suppressed after Send still gets that one email" do
    listener = listening("Listener")
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    result = send_email
    suppress_email(listener.email)

    with_ses do |calls|
      perform_enqueued_jobs

      assert_equal [[listener.email]], calls.map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, email_row(result.broadcast, listener).status
  end

  test "once the address changes, or its record is cleared, the next preview and send email them" do
    listener = listening("Listener")
    suppression = suppress_email(listener.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)
    preview = -> { Rbs.retrieve_recipients(Broadcast::TYPE_POSITION, listener_criteria(send_email: true)) }

    assert_empty preview.call, "email was their only way to be reached"

    listener.update_columns(email: "listener.new@example.com")

    assert_equal [true], preview.call.map(&:use_email)
    with_ses do |calls|
      perform_enqueued_jobs { send_email }

      assert_equal [["listener.new@example.com"]], calls.map { |call| ses_addresses(call) }
    end

    listener.update_columns(email: suppression.email)

    assert_empty preview.call

    suppression.clear(by: @sender, person: listener)

    assert_equal [true], preview.call.map(&:use_email)
    with_ses do |calls|
      perform_enqueued_jobs { send_email }

      assert_equal [[suppression.email]], calls.map { |call| ses_addresses(call) }
    end
  end

  # A Retry resends only rows SES refused, so it never asks the record. A
  # new-message alert asks it before the alert is queued, with
  # SuppressedRecipientsInterceptor as the backstop (see above).
  test "a Retry still sends to a suppressed address, as before" do
    listener = reachable(callsign: "Listener")
    broadcast, failed = failed_email(listener)
    suppress_email(listener.email)
    sandbox_off(Setting::BROADCAST_MAIL_SANDBOX)

    with_ses do |calls|
      send_again(broadcast)

      assert_equal [[listener.email]], calls.map { |call| ses_addresses(call) }
    end

    assert_equal Broadcast::STATUS_SENT, failed.reload.status
  end

  # ==========================================================================
  # The event dates
  # ==========================================================================

  test "the event runs from two weeks before Labor Day to five days after it" do
    # Pinned to the dates themselves. Asserting the window's own arithmetic --
    # that the end is nineteen days after the start -- holds for any Monday and
    # so says nothing about which Monday was picked.
    labor_days = { 2024 => Date.new(2024, 9, 2), 2025 => Date.new(2025, 9, 1),
                   2026 => Date.new(2026, 9, 7) }

    labor_days.each do |year, labor_day|
      Current.groundhog_day_time = Time.zone.local(year, 6, 1, 12, 0, 0)
      start_date, end_date = Rbs.event_dates

      assert_equal labor_day - 14.days, start_date, "#{year} start"
      assert_equal labor_day + 5.days, end_date, "#{year} end"
    ensure
      Current.groundhog_day_time = nil
    end
  end
end
