# frozen_string_literal: true

require "test_helper"

class GroundHogDayTest < ActiveSupport::TestCase
  include EnvTestHelper

  YEAR = 2026
  MOMENT = "#{YEAR}-09-05 18:00:00"

  setup do
    @person = person(:active_ranger)
    @moment = Time.zone.parse(MOMENT)
  end

  test "the training database file is named for its day" do
    assert_equal "training-2025-08-30.sql.gz", GroundHogDay.training_database_dump_name("2025-08-30 18:00:00")
  end

  # A day that cannot be read used to travel on as nothing, and the first thing
  # to notice was the database it had already been written over.
  test "a day that is not a day is refused" do
    ["not a day", "", "2026-13-45"].each do |value|
      assert_raises(DatabaseDump::Error, "#{value.inspect} should be refused") do
        GroundHogDay.parse_moment(value)
      end
    end

    assert_raises(DatabaseDump::Error) { GroundHogDay.build("yesterday") }
    assert_raises(DatabaseDump::Error) { GroundHogDay.training_database_dump_name("yesterday") }
  end

  # The database keeps its times the way the machine tells them, so a year that
  # begins an hour off reaches back into the last evening of the year before.
  test "build keeps what happened in the last hour of the year" do
    credit = PositionCredit.create!(position_id: position.id, description: "Late shift",
                                    credits_per_hour: 1,
                                    start_time: Time.local(YEAR, 12, 31, 23, 30, 0),
                                    end_time: Time.local(YEAR + 1, 1, 1, 1, 0, 0))

    GroundHogDay.build(@moment)

    assert PositionCredit.exists?(credit.id)
  end

  # Both ways of getting this wrong end in the same place: the task says what is
  # missing and stops, rather than showing a stack trace.
  test "reloading says what is missing instead of falling over" do
    assert_raises(DatabaseDump::Error) { GroundHogDay.reload_training_database! }

    with_env(GroundHogDay::ENVIRONMENT_VAR => "2025-08-30 18:00:00") do
      error = assert_raises(DatabaseDump::Error) { GroundHogDay.reload_training_database! }

      assert_match "training-2025-08-30.sql.gz", error.message
    end
  end

  test "every setting it turns on is one the Clubhouse knows" do
    assert_empty GroundHogDay::TRUE_SETTINGS - Setting::DESCRIPTIONS.keys
  end

  # A shift that had not started when we stopped never happened.
  test "build removes shifts that were still to come" do
    later = create_timesheet(on_duty: @moment + 2.hours, off_duty: @moment + 4.hours)

    GroundHogDay.build(@moment)

    assert_not Timesheet.exists?(later.id)
  end

  # Somebody who was on shift at that moment is still on shift, which is what
  # makes the sign-out pages worth practising on.
  test "build leaves a Ranger who was on shift still on it" do
    entry = create_timesheet(on_duty: @moment - 2.hours, off_duty: @moment + 2.hours)

    GroundHogDay.build(@moment)
    entry.reload

    assert_nil entry.off_duty
    assert_equal Timesheet::STATUS_UNVERIFIED, entry.review_status
  end

  test "build removes shifts scheduled for later years" do
    this_year = create_slot(begins: Time.zone.local(YEAR, 8, 25, 9, 0, 0))
    next_year = create_slot(begins: Time.zone.local(YEAR + 1, 8, 25, 9, 0, 0))
    PersonSlot.create!(person_id: @person.id, slot_id: next_year.id)

    GroundHogDay.build(@moment)

    assert Slot.exists?(this_year.id)
    assert_not Slot.exists?(next_year.id)
    assert_empty PersonSlot.where(slot_id: next_year.id)
  end

  test "build marks the people who were there as on site" do
    create_timesheet(on_duty: @moment - 2.days, off_duty: @moment - 2.days + 4.hours)

    GroundHogDay.build(@moment)

    assert @person.reload.on_site
    assert @person.behavioral_agreement
    assert PersonEvent.find_by(person_id: @person.id, year: YEAR).asset_authorized
  end

  # put_people_on_site marks people on site with update_all, which skips
  # Person's hook, so build closes the gap itself: rows after the moment go, and
  # each history it keeps ends on the flag the copy now holds.
  test "build keeps the on-site log up to the moment and ends each history on the flag it leaves" do
    create_timesheet(on_duty: @moment - 2.days, off_duty: @moment - 2.days + 4.hours) # @person was there
    left = person(:retired_ranger)    # not there, yet the log still ends on site
    settled = person(:echelon_ranger) # not there, and the log already ends off site
    kept = log_on_site(@person, PersonOnSite::OFF_SITE, @moment - 1.day)
    later = log_on_site(@person, PersonOnSite::ON_SITE, @moment + 1.hour)
    log_on_site(left, PersonOnSite::ON_SITE, @moment - 3.days)
    log_on_site(settled, PersonOnSite::OFF_SITE, @moment - 3.days)

    assert_no_difference -> { PersonOnSite.where(person: settled).count } do
      GroundHogDay.build(@moment)
    end

    assert PersonOnSite.exists?(kept.id)
    assert_not PersonOnSite.exists?(later.id)
    newest = PersonOnSite.history_for(@person).first
    assert_equal [PersonOnSite::ON_SITE, @moment, nil], [newest.action, newest.created_at, newest.creator_person_id]
    assert_equal PersonOnSite::OFF_SITE, PersonOnSite.history_for(left).first.action

    # Every history ends on its person's flag, and no one on site is without one.
    latest = PersonOnSite.order(:created_at, :id).pluck(:person_id, :action).to_h
    Person.where(id: latest.keys).find_each do |person|
      assert_equal person.on_site, latest[person.id] == PersonOnSite::ON_SITE, person.callsign
    end
    assert_empty Person.where(on_site: true).where.not(id: latest.keys).pluck(:callsign)
  end

  test "build gives someone it puts on site with no history an on-site row at the moment" do
    create_timesheet(on_duty: @moment - 2.days, off_duty: @moment - 2.days + 4.hours)

    GroundHogDay.build(@moment)

    assert_equal [[PersonOnSite::ON_SITE, @moment]], PersonOnSite.where(person: @person).pluck(:action, :created_at)
  end

  test "build leaves an announcement saying which day it is" do
    GroundHogDay.build(@moment)

    announcement = Motd.order(:id).last

    assert_match "Welcome to Saturday, September 5, 2026", announcement.subject
    assert announcement.for_rangers
  end

  test "build puts the Clubhouse into event mode with nothing able to reach anybody" do
    GroundHogDay.build(@moment)

    assert_equal "event", Setting.get_value(Setting::DASHBOARD_PERIOD)
    assert Setting.get_value(Setting::BROADCAST_MAIL_SANDBOX)
    assert Setting.get_value(Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED)
  end

  # Everybody active is passed, so training can be practised from any account.
  test "train_actives signs up and passes every active Ranger" do
    Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, active: true)
    expected = Person.where(status: Person::ACTIVE).count

    slot = GroundHogDay.train_actives(YEAR)

    assert_equal expected, slot.signed_up
    assert_equal expected, PersonSlot.where(slot_id: slot.id).count
    trainee_status = TraineeStatus.find_by(slot_id: slot.id, person_id: @person.id)
    assert_equal TraineeStatus::STATUS_PASSED, trainee_status.status
    assert PersonRole.exists?(person_id: @person.id, role_id: Role::EVENT_MANAGEMENT_ON_PLAYA)
  end

  private

  def position
    @position ||= positions(:ood_position)
  end

  def create_timesheet(on_duty:, off_duty:)
    Timesheet.create!(person_id: @person.id, position_id: position.id,
                      on_duty: on_duty, off_duty: off_duty, additional_notes: "test entry")
  end

  def log_on_site(person, action, created_at)
    PersonOnSite.create!(person:, action:, created_at:)
  end

  def create_slot(begins:)
    Slot.create!(active: true, description: "Test shift", position_id: position.id,
                 begins: begins, ends: begins + 4.hours, max: 10, min: 1)
  end
end
