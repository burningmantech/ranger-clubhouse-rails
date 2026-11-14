# frozen_string_literal: true

require "test_helper"

# The roster's "No mentors available" rows (owner, 2026-11-13): one per mentee
# and shift, or per timesheet entry for a sign-in that matched no shift.
class PersonMentoringShiftTest < ActiveSupport::TestCase
  test "a row needs a shift or a timesheet entry, and an entry holds one row" do
    mentee = person(:alpha_ranger)

    assert_not PersonMentoringShift.new(person: mentee, incomplete: true).valid?

    PersonMentoringShift.create!(person: mentee, slot_id: 1, timesheet_id: 1, incomplete: true)
    assert_raises(ActiveRecord::RecordNotUnique) do
      PersonMentoringShift.create!(person: mentee, slot_id: 2, timesheet_id: 1, incomplete: true)
    end
    # An entry moved off a shift keeps its row, and the mentee's next entry on that shift gets its own.
    assert PersonMentoringShift.create!(person: mentee, slot_id: 1, timesheet_id: 2, incomplete: true)
  end

  test "for_entries finds the rows ticked on those entries, and deleting the person deletes theirs" do
    mentee = person(:alpha_ranger)
    row = PersonMentoringShift.create!(person: mentee, slot_id: 7, timesheet_id: 9, incomplete: true)
    PersonMentoringShift.create!(person: mentee, slot_id: 7, timesheet_id: 10, incomplete: true)

    assert_equal [row], PersonMentoringShift.for_entries([9]).to_a
    assert_equal :delete_all, Person.reflect_on_association(:person_mentoring_shift).options[:dependent]
  end
end
