# frozen_string_literal: true

require "test_helper"

# Every account, grouped by the status it holds right now: the counts, one
# status's people, and the slug each status resolves through.
class PeopleByStatusReportTest < ActiveSupport::TestCase
  test "counts lists every status, in ALL_STATUSES order" do
    assert_equal Person::ALL_STATUSES, PeopleByStatusReport.counts.keys
  end

  test "counts sums to the number of people on file" do
    assert_equal Person.count, PeopleByStatusReport.counts.values.sum
  end

  test "a status no one holds counts zero rather than dropping out" do
    assert_equal 0, PeopleByStatusReport.counts[Person::SUSPENDED]
  end

  test "a status people do hold matches a plain tally of it" do
    assert_equal Person.where(status: Person::ACTIVE).count,
                 PeopleByStatusReport.counts[Person::ACTIVE]
  end

  test "people returns only that status" do
    expected = Person.where(status: Person::ACTIVE).pluck(:id).sort

    assert_equal expected, PeopleByStatusReport.people(Person::ACTIVE).map(&:id).sort
  end

  test "people are ordered by callsign, ignoring case" do
    callsigns = PeopleByStatusReport.people(Person::ACTIVE).map(&:callsign)

    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  test "every status round-trips through its slug" do
    Person::ALL_STATUSES.each do |status|
      assert_equal status, PeopleByStatusReport.find_status(PeopleByStatusReport.slug(status))
    end
  end

  test "a multi-word status hyphenates its slug" do
    assert_equal "past-prospective", PeopleByStatusReport.slug(Person::PAST_PROSPECTIVE)
    assert_equal "inactive-extension", PeopleByStatusReport.slug(Person::INACTIVE_EXTENSION)
  end

  test "an unknown slug finds nothing" do
    assert_nil PeopleByStatusReport.find_status("shiny-pennies")
  end

  test "a blank slug finds nothing" do
    assert_nil PeopleByStatusReport.find_status("")
  end

  test "the raw stored value is not itself a valid slug" do
    assert_nil PeopleByStatusReport.find_status(Person::PAST_PROSPECTIVE)
  end
end
