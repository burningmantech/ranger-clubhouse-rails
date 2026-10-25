# frozen_string_literal: true

require "test_helper"

class PersonPogTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 14, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)

    PersonPog.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "issued_at defaults to now on create when blank" do
    pog = build_pog(issued_at: nil)

    pog.save!

    assert_equal Current.time, pog.issued_at
  end

  test "issued_at is preserved when explicitly set" do
    explicit_time = 3.days.ago

    pog = build_pog(issued_at: explicit_time)
    pog.save!

    assert_equal explicit_time.to_i, pog.issued_at.to_i
  end

  test "pog must be in the allowed list" do
    pog = build_pog(pog: "bogus")

    refute pog.valid?
    assert_includes pog.errors[:pog], "Pog is not included in the list."
  end

  test "status must be in the allowed list" do
    pog = build_pog(status: "bogus")

    refute pog.valid?
    assert_includes pog.errors[:status], "Status is not included in the list."
  end

  test "notes normalizes blank and nil to empty string" do
    pog = build_pog(notes: nil)
    assert_equal "", pog.notes

    pog.notes = "   "
    assert_equal "", pog.notes

    pog.notes = "Gave an extra pog"
    assert_equal "Gave an extra pog", pog.notes
  end

  test "timesheet guard rejects a timesheet belonging to a different person" do
    pog = build_pog(person: person(:active_ranger), timesheet_id: timesheet(:echelon_ranger_work_2024).id)

    refute pog.valid?
    assert_includes pog.errors[:timesheet_id], "Timesheet does not belong to person"
  end

  test "timesheet guard accepts a timesheet belonging to the same person" do
    pog = build_pog(person: person(:active_ranger), timesheet_id: timesheet(:active_ranger_ood_2023_1).id)

    assert pog.valid?
  end

  test "timesheet guard allows a nil timesheet_id" do
    pog = build_pog(timesheet_id: nil)

    assert pog.valid?
  end

  test "find_for_query filters by person and year, and orders created_at desc" do
    target_person = person(:active_ranger)

    first = build_pog(person: target_person)
    first.save!
    first.update_column(:created_at, Time.zone.local(2025, 6, 1, 8, 0, 0))

    second = build_pog(person: target_person)
    second.save!
    second.update_column(:created_at, Time.zone.local(2025, 6, 2, 8, 0, 0))

    outside_year = build_pog(person: target_person)
    outside_year.save!
    outside_year.update_column(:created_at, Time.zone.local(2024, 6, 1, 8, 0, 0))

    other_person = build_pog(person: person(:echelon_ranger))
    other_person.save!
    other_person.update_column(:created_at, Time.zone.local(2025, 6, 3, 8, 0, 0))

    results = PersonPog.find_for_query(person_id: target_person.id, year: 2025).to_a

    assert_equal [second.id, first.id], results.map(&:id)
    assert results.first.association(:issued_by).loaded?
  end

  private

  def build_pog(**attributes)
    PersonPog.new({
      person: person(:active_ranger),
      issued_by: person(:auditor_ranger),
      pog: PersonPog::POG_MEAL,
      status: PersonPog::STATUS_ISSUED,
      notes: ""
    }.merge(attributes))
  end
end
