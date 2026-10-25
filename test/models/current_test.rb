# frozen_string_literal: true

require "test_helper"

# Covers the viewer on-duty accessors added for the HQ Window port
# (Ember source: app/services/session.js updateOnDuty / onduty_position).
class CurrentTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Current.reset
    @person = person(:active_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "onduty_entry and onduty_position_subtype are nil without a person" do
    assert_nil Current.onduty_entry
    assert_nil Current.onduty_position_subtype
  end

  test "onduty_entry is nil when the person is not on duty" do
    Current.person = @person

    assert_nil Current.onduty_entry
    assert_nil Current.onduty_position_subtype
  end

  test "onduty_entry returns the open entry with position preloaded and is memoized" do
    position = create_position!("Mentor Shift", type: Position::TYPE_MENTORING)
    entry = create_open_entry!(@person, position)

    Current.person = @person

    found = Current.onduty_entry
    assert_equal entry.id, found.id
    assert found.association(:position).loaded?, "position should be preloaded"
    assert_equal "mentor", Current.onduty_position_subtype
    assert_same found, Current.onduty_entry, "repeated reads should return the memoized entry"
  end

  test "a closed entry does not count as on duty" do
    position = create_position!("Dusk Patrol")
    entry = create_open_entry!(@person, position)
    entry.update_column(:off_duty, Current.time)

    Current.person = @person

    assert_nil Current.onduty_entry
  end

  test "switching the person invalidates the memoized entry" do
    position = create_position!("Night Watch")
    create_open_entry!(@person, position)

    Current.person = @person
    assert_not_nil Current.onduty_entry

    Current.person = person(:auditor_ranger)
    assert_nil Current.onduty_entry
    assert_nil Current.onduty_position_subtype
  end

  test "reset clears the memoized entry" do
    position = create_position!("Dawn Patrol")
    entry = create_open_entry!(@person, position)

    Current.person = @person
    assert_not_nil Current.onduty_entry

    # Close the shift behind the memo's back, then reset: a fresh read must
    # hit the database again instead of serving the stale entry.
    entry.update_column(:off_duty, Current.time)
    Current.reset
    Current.person = @person

    assert_nil Current.onduty_entry
  end

  private

  def create_position!(title, **attrs)
    Position.create!({ title: title, active: true, no_training_required: true }.merge(attrs))
  end

  def create_open_entry!(person, position)
    entry = Timesheet.new(person_id: person.id, position_id: position.id, on_duty: Current.time - 2.hours)
    entry.save!(validate: false)
    entry
  end
end
