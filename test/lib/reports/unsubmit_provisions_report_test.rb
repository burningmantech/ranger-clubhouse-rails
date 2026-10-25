# frozen_string_literal: true

require "test_helper"

# Who the un-submit recommendation turns up: people holding earned claimed or
# submitted provisions with no timesheet that year, plus the context flags the
# operator judges them by.
#
# The report reads whole tables and the shared fixtures belong to other suites,
# so every test starts from empty tables and builds exactly the rows it needs.
class UnsubmitProvisionsReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)
    @other = person(:ranger_with_custom_gender)

    AccessDocument.delete_all
    Provision.delete_all
    Timesheet.delete_all
    PersonSlot.delete_all
    Bmid.delete_all
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "lists people with earned claimed or submitted provisions who did not ranger" do
    claimed = provision_for(@person, status: Provision::CLAIMED)
    submitted = provision_for(@person, type: Provision::EVENT_RADIO, status: Provision::SUBMITTED)
    provision_for(@other, status: Provision::CLAIMED)
    shift_for(@other)

    rows = UnsubmitProvisionsReport.execute(YEAR)

    assert_equal [@person.callsign], rows.map { |row| row.person.callsign }
    assert_equal [submitted, claimed].map(&:id).sort, rows.first.provisions.map(&:id).sort
  end

  test "available and allocated provisions do not put anyone on the list" do
    provision_for(@person, status: Provision::AVAILABLE)
    provision_for(@other, status: Provision::CLAIMED, is_allocated: true)

    assert_empty UnsubmitProvisionsReport.execute(YEAR)
  end

  test "the context flags report the ticket, sap, and bmid on file" do
    provision_for(@person, status: Provision::CLAIMED)
    ticket = ticket_for(@person, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    ticket_for(@person, type: AccessDocument::SAP, status: AccessDocument::SUBMITTED,
               delivery_method: AccessDocument::DELIVERY_EMAIL)
    Bmid.create!(person: @person, year: YEAR, status: Bmid::SUBMITTED)

    row = UnsubmitProvisionsReport.execute(YEAR).first

    assert_equal ticket.id, row.ticket.id
    assert row.has_sap
    assert row.bmid
  end

  test "a claimed staff credential counts as both the ticket and a sap" do
    provision_for(@person, status: Provision::CLAIMED)
    ticket_for(@person, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED,
               delivery_method: AccessDocument::DELIVERY_WILL_CALL)

    row = UnsubmitProvisionsReport.execute(YEAR).first

    assert_equal AccessDocument::STAFF_CREDENTIAL, row.ticket.type
    assert row.has_sap
    assert_not row.bmid
  end

  # Upstream's sign-up join was broken and its flag meaningless; the port joins
  # the slot properly and keeps upstream's intent of ignoring trainings.
  test "signed up means a non-training sign-up for the year" do
    provision_for(@person, status: Provision::CLAIMED)
    provision_for(@other, status: Provision::CLAIMED)
    sign_up(@person, Position.create!(title: "Dirt", type: Position::TYPE_FRONTLINE))
    sign_up(@other, training_position)

    rows = UnsubmitProvisionsReport.execute(YEAR).index_by { |row| row.person.id }

    assert rows[@person.id].signed_up
    assert_not rows[@other.id].signed_up
  end

  # position.type is nullable, and SQL calls a NULL type unknown rather than
  # "not Training" -- so a join on type != 'Training' dropped the row and lost
  # the person a sign-up they have. Every position fixture is untyped, which is
  # what made the old behaviour easy to mistake for correct.
  test "a sign-up for a position with no type still counts" do
    provision_for(@person, status: Provision::CLAIMED)
    assert_nil positions(:ood_position).type, "fixture guard: this position has no type"
    sign_up(@person, positions(:ood_position))

    rows = UnsubmitProvisionsReport.execute(YEAR).index_by { |row| row.person.id }

    assert rows[@person.id].signed_up
  end

  private

  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, is_allocated: false)
    Provision.create!(person: holder, type:, status:, is_allocated:,
                      source_year: YEAR, expires_on: "#{YEAR}-09-15",
                      event_week_meals: type == Provision::MEALS)
  end

  def ticket_for(holder, type:, status:, delivery_method: AccessDocument::DELIVERY_NONE)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method:, expiry_date: "#{YEAR + 1}-09-15")
  end

  def shift_for(holder)
    on_duty = Time.local(YEAR, 8, 30, 10, 0, 0)
    Timesheet.create!(person: holder, position: positions(:ood_position),
                      on_duty:, off_duty: on_duty + 6.hours, additional_notes: "test shift")
  end

  def sign_up(holder, position)
    slot = Slot.create!(position:, begins: Time.local(YEAR, 8, 28, 9, 0, 0),
                        ends: Time.local(YEAR, 8, 28, 13, 0, 0), max: 10, active: true)
    PersonSlot.create!(person: holder, slot:)
  end

  def training_position
    Position.find_by(type: Position::TYPE_TRAINING) ||
      Position.create!(title: "Training", type: Position::TYPE_TRAINING)
  end
end
