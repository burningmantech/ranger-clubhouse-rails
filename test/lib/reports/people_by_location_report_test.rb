# frozen_string_literal: true

require "test_helper"

class PeopleByLocationReportTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper

  # A year the timesheet and slot fixtures leave alone, so the only sign-ups and
  # hours in it are the ones each test creates.
  YEAR = 2022

  setup do
    Rails.cache.clear

    @person = person(:active_ranger)
    @person.update!(country: "US", state: "NV", city: "Gerlach", zip: "89412")
    @position = positions(:ood_position)
    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha")
  end

  teardown { Rails.cache.clear }

  def row_for(subject, **args)
    PeopleByLocationReport.execute(year: YEAR, **args).find { |row| row.id == subject.id }
  end

  def shift(position: @position, year: YEAR)
    create_slot(position, begins: Time.zone.local(year, 8, 20, 9, 0))
  end

  def sign_up(subject, slot)
    PersonSlot.create!(person_id: subject.id, slot_id: slot.id)
  end

  def add_timesheet(subject, year: YEAR)
    Timesheet.create!(person: subject, position: @position,
                      on_duty: Time.zone.local(year, 8, 20, 9, 0),
                      off_duty: Time.zone.local(year, 8, 20, 11, 0),
                      additional_notes: "test entry")
  end

  # ------------------------------------------------------------------ address

  test "a row carries the person's current address" do
    row = row_for(@person)

    assert_equal "US", row.country
    assert_equal "NV", row.state
    assert_equal "Gerlach", row.city
    assert_equal "89412", row.zip
  end

  test "a preferred name is used in place of the first name" do
    @person.update!(first_name: "Alexander", preferred_name: "Alex")

    assert_equal "Alex", row_for(@person).first_name
  end

  test "the first name is used when no preferred name is set" do
    @person.update!(first_name: "Alexander", preferred_name: "")

    assert_equal "Alexander", row_for(@person).first_name
  end

  test "email is only read when the reader may see it" do
    assert_nil row_for(@person).email
    assert_equal @person.email, row_for(@person, include_email: true).email
  end

  test "a blank state is bucketed under its own key" do
    # Written straight to the column: a state is required of new records, and
    # this is about the records already on file that have none.
    @person.update_column(:state, "")

    assert_equal PeopleByLocationReport::NO_STATE, row_for(@person).state_key
  end

  # Some records really do hold a dash as their state, so the marker for "none
  # on file" has to be something no one has typed in -- otherwise the two land
  # in one bucket and the page claims an address it does not have.
  test "a state that is punctuation is its own bucket, not the empty one" do
    @person.update_column(:state, "-")

    assert_equal "-", row_for(@person).state_key
    assert_not_equal PeopleByLocationReport::NO_STATE, row_for(@person).state_key
  end

  # ------------------------------------------------------------------- flags

  test "signing up for a shift in the year sets signed up" do
    assert_not row_for(@person).signed_up

    sign_up(@person, shift)

    assert row_for(@person).signed_up
  end

  test "an Alpha shift does not count as signing up" do
    sign_up(@person, shift(position: @alpha_position))

    assert_not row_for(@person).signed_up
  end

  test "a sign-up in another year does not count" do
    sign_up(@person, shift(year: YEAR - 1))

    assert_not row_for(@person).signed_up
  end

  test "a timesheet in the year sets rangered" do
    assert_not row_for(@person).rangered

    add_timesheet(@person)

    assert row_for(@person).rangered
  end

  test "a timesheet in another year does not count" do
    add_timesheet(@person, year: YEAR - 1)

    assert_not row_for(@person).rangered
  end

  # ----------------------------------------------------------- participation

  test "each participation choice keeps only the people it names" do
    signed_up_only = person(:echelon_ranger)
    # Not the auditor fixture: that status is one the report hides.
    rangered_only = person(:inactive_ranger)
    sign_up(@person, shift)
    add_timesheet(@person)
    sign_up(signed_up_only, shift)
    add_timesheet(rangered_only)

    assert_not_nil row_for(@person, participation: PeopleByLocationReport::SIGNED_UP)
    assert_not_nil row_for(signed_up_only, participation: PeopleByLocationReport::SIGNED_UP)
    assert_nil row_for(rangered_only, participation: PeopleByLocationReport::SIGNED_UP)

    assert_not_nil row_for(rangered_only, participation: PeopleByLocationReport::RANGERED)
    assert_nil row_for(signed_up_only, participation: PeopleByLocationReport::RANGERED)

    # Both: only the person who did each of them.
    assert_not_nil row_for(@person, participation: PeopleByLocationReport::BOTH)
    assert_nil row_for(signed_up_only, participation: PeopleByLocationReport::BOTH)
    assert_nil row_for(rangered_only, participation: PeopleByLocationReport::BOTH)

    # Either: all three.
    [@person, signed_up_only, rangered_only].each do |subject|
      assert_not_nil row_for(subject, participation: PeopleByLocationReport::EITHER),
                     "#{subject.callsign} should appear under 'either'"
    end
  end

  test "someone who did neither is dropped by every participation choice" do
    PeopleByLocationReport::PARTICIPATION_VALUES.each do |participation|
      assert_nil row_for(@person, participation:),
                 "should not appear under #{participation}"
    end
  end

  # --------------------------------------------------------------- statuses

  test "people who have left the Rangers are hidden by default" do
    PeopleByLocationReport::OPTIONAL_STATUSES.each do |status|
      @person.update_column(:status, status)

      assert_nil row_for(@person), "#{status} should be hidden"
    end
  end

  test "a hidden status comes back on its own without bringing the others" do
    retired = @person
    retired.update_column(:status, Person::RETIRED)
    deceased = person(:echelon_ranger)
    deceased.update_column(:status, Person::DECEASED)

    assert_not_nil row_for(retired, statuses: [Person::RETIRED])
    assert_nil row_for(deceased, statuses: [Person::RETIRED])
  end

  test "hidden statuses can be asked for together" do
    retired = @person
    retired.update_column(:status, Person::RETIRED)
    deceased = person(:echelon_ranger)
    deceased.update_column(:status, Person::DECEASED)

    both = [Person::RETIRED, Person::DECEASED]

    assert_not_nil row_for(retired, statuses: both)
    assert_not_nil row_for(deceased, statuses: both)
  end

  # A route segment cannot be empty, so a blank country needs a stand-in or its
  # row on the index links nowhere.
  test "a person with no country on file lands in a bucket that has a URL" do
    @person.update_column(:country, "")

    row = row_for(@person)

    assert_equal PeopleByLocationReport::NO_COUNTRY, row.country_key
    assert_predicate row.country, :blank?
  end

  # Applicants are hidden for the same reason as people who have left: neither
  # is a Ranger right now.
  test "an applicant is hidden until asked for" do
    applicant = person(:past_prospective_ranger)

    assert_nil row_for(applicant)
    assert_not_nil row_for(applicant, statuses: [Person::PAST_PROSPECTIVE])
  end

  # --------------------------------------------------------------- ordering

  # Compared as written, not downcased, so the assertion can actually fail if
  # the report drops its case folding. No fixture callsign starts lower case,
  # so this one has to be planted.
  test "rows are ordered by callsign, ignoring case" do
    @person.update!(callsign: "abby")
    person(:echelon_ranger).update!(callsign: "Zebra")

    calls = PeopleByLocationReport.execute(year: YEAR).map(&:callsign)

    assert_operator calls.index("abby"), :<, calls.index("Zebra")
    assert_equal calls.sort_by(&:downcase), calls
  end
end
