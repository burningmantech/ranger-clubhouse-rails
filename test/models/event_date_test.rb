# frozen_string_literal: true

require "test_helper"

class EventDateTest < ActiveSupport::TestCase
  YEAR = 2026

  test "a well formed record is valid" do
    assert build_event_date.valid?
  end

  test "each window must run forwards" do
    {
      event_end: [Time.zone.local(YEAR, 8, 29), "Event End must be after the Event Start"],
      pre_event_slot_end: [Time.zone.local(YEAR, 8, 19), "Pre-Event Slot End must be after the Pre-Event Slot Start"]
    }.each do |column, (backwards, message)|
      event_date = build_event_date(column => backwards)

      assert_not event_date.valid?, "#{column} running backwards should be invalid"
      assert_includes event_date.errors[column], message, "wrong message for #{column}"
    end
  end

  test "the credit period has to contain the event it credits" do
    early_close = build_event_date(post_event_end: Time.zone.local(YEAR, 1, 2))

    assert_not early_close.valid?
    assert_includes early_close.errors[:post_event_end], "Post-Event End must be on or after the Event End"

    late_open = build_event_date(pre_event_start: Time.zone.local(YEAR, 9, 1))

    assert_not late_open.valid?
    assert_includes late_open.errors[:event_start], "Pre-Event Start must be on or before the Event Start"
  end

  test "a window with only one half set is left to the presence validations" do
    event_date = build_event_date(pre_event_slot_end: nil)

    assert_not event_date.valid?
    assert_equal ["Pre-event slot end can't be blank."], event_date.errors[:pre_event_slot_end]
  end

  test "dates outside the event year are rejected" do
    {
      event_end: Time.zone.local(YEAR + 1, 9, 7, 23, 59),
      pre_event_start: Time.zone.local(YEAR - 1, 1, 1, 1, 0),
      pre_event_slot_start: Time.zone.local(YEAR - 1, 8, 20),
      pre_event_slot_end: Time.zone.local(YEAR - 1, 8, 28)
    }.each do |column, wrong_year|
      event_date = build_event_date(column => wrong_year)
      event_date.valid?

      assert_includes event_date.errors[column].join, "the same year as the Event Start",
                      "no wrong-year error for #{column}"
    end
  end

  test "each wrong-year message names its own field" do
    event_date = build_event_date(pre_event_slot_start: Time.zone.local(YEAR - 1, 8, 20),
                                  pre_event_slot_end: Time.zone.local(YEAR - 1, 8, 28))
    event_date.valid?

    # errors.format drops the attribute name, so two fields failing the same
    # rule must not produce two identical bullets.
    messages = event_date.errors.full_messages.select { |m| m.include?("same year") }
    assert_equal messages.uniq.size, messages.size, "wrong-year messages are indistinguishable"
  end

  test "the credit period may close in the following January" do
    event_date = build_event_date(post_event_end: Time.zone.local(YEAR + 1, 1, 15, 12, 0))

    assert event_date.valid?, event_date.errors.full_messages.inspect
  end

  test "the credit period may also close inside the event year" do
    event_date = build_event_date(post_event_end: Time.zone.local(YEAR, 12, 31, 23, 59))

    assert event_date.valid?, event_date.errors.full_messages.inspect
  end

  test "a credit period closing past January of the following year is rejected" do
    event_date = build_event_date(post_event_end: Time.zone.local(YEAR + 1, 9, 12))

    assert_not event_date.valid?
    assert_includes event_date.errors[:post_event_end],
                    "Post-Event End must be in #{YEAR} or January #{YEAR + 1}"
  end

  test "a credit period closing two years out is rejected" do
    event_date = build_event_date(post_event_end: Time.zone.local(YEAR + 2, 1, 1, 0, 59))

    assert_not event_date.valid?
    assert_includes event_date.errors[:post_event_end],
                    "Post-Event End must be in #{YEAR} or January #{YEAR + 1}"
  end

  test "a year may only be recorded once" do
    build_event_date.save!

    duplicate = build_event_date

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:event_start], "#{YEAR} already has an event date record"
  end

  test "a record does not clash with itself" do
    event_date = build_event_date
    event_date.save!

    event_date.event_end = Time.zone.local(YEAR, 9, 8, 23, 59)

    assert event_date.valid?, event_date.errors.full_messages.inspect
  end

  test "saving a record writes an action log entry" do
    ActionLog.delete_all

    build_event_date.save!

    assert_not_nil ActionLog.find_by(event: "event-dates-create")
  end

  private

  def build_event_date(overrides = {})
    EventDate.new({
      event_start: Time.zone.local(YEAR, 8, 30, 0, 0, 0),
      event_end: Time.zone.local(YEAR, 9, 7, 23, 59, 0),
      pre_event_start: Time.zone.local(YEAR, 1, 1, 1, 0, 0),
      post_event_end: Time.zone.local(YEAR + 1, 1, 1, 0, 59, 0),
      pre_event_slot_start: Time.zone.local(YEAR, 8, 20, 0, 0, 0),
      pre_event_slot_end: Time.zone.local(YEAR, 8, 28, 0, 0, 0)
    }.merge(overrides))
  end
end
