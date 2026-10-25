# frozen_string_literal: true

require "test_helper"

# Exercises TicketingManagement.retrieve_current_by_person, the query behind the
# Ticketing > Access Documents summary: which documents are still live, who is
# holding them, what order the holders appear in, and the arrival-date problems
# handed to the Weird Stuff column.
#
# The shared access_document fixtures belong to other suites and this module
# reads the whole table, so every test starts from an empty one and builds
# exactly the documents it needs.
class TicketingManagementTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
    AccessDocument.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- helpers -------------------------------------------------------------

  def summary
    TicketingManagement.retrieve_current_by_person
  end

  def summary_for(person)
    summary[:people].find { |row| row[:person].id == person.id }
  end

  def callsigns
    summary[:people].map { |row| row[:person].callsign }
  end

  # --- which documents count -----------------------------------------------

  # Submitted counts as current here, unlike upstream: the document is still a
  # live allocation and its holder still needs to be visible to the crew.
  test "returns only qualified, claimed, banked, and submitted documents" do
    ranger = person(:active_ranger)
    [AccessDocument::QUALIFIED, AccessDocument::CLAIMED, AccessDocument::BANKED,
     AccessDocument::SUBMITTED, AccessDocument::USED, AccessDocument::CANCELLED,
     AccessDocument::EXPIRED, AccessDocument::TURNED_DOWN].each do |status|
      document(ranger, type: AccessDocument::SPT, status:)
    end

    held = summary_for(ranger)[:documents]

    assert_equal AccessDocument::CURRENT_STATUSES.sort, held.map(&:status).sort
  end

  test "a holder of nothing but submitted documents still appears" do
    holder = person(:inactive_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::SUBMITTED)

    assert_equal [holder.callsign], callsigns
  end

  test "a holder with nothing but spent documents does not appear at all" do
    document(person(:inactive_ranger), type: AccessDocument::SPT, status: AccessDocument::USED)
    document(person(:inactive_ranger), type: AccessDocument::SPT, status: AccessDocument::CANCELLED)

    assert_empty summary[:people]
  end

  test "documents are grouped under the person holding them" do
    ranger = person(:active_ranger)
    other = person(:inactive_ranger)
    ranger_spt = document(ranger, type: AccessDocument::SPT)
    ranger_gift = document(ranger, type: AccessDocument::GIFT, name: "Gift Recipient")
    other_spt = document(other, type: AccessDocument::SPT)

    assert_equal [ranger_spt.id, ranger_gift.id].sort, summary_for(ranger)[:documents].map(&:id).sort
    assert_equal [other_spt.id], summary_for(other)[:documents].map(&:id)
  end

  # --- who appears ----------------------------------------------------------

  test "deceased and dismissed holders are left out entirely" do
    document(person(:deceased_ranger), type: AccessDocument::SPT)

    dismissed = person(:retired_ranger)
    dismissed.update_column(:status, Person::DISMISSED)
    document(dismissed, type: AccessDocument::SPT)

    document(person(:active_ranger), type: AccessDocument::SPT)

    assert_equal ["TestRanger"], callsigns
  end

  test "people come back ordered by callsign" do
    document(person(:active_ranger), type: AccessDocument::SPT)           # TestRanger
    document(person(:inactive_ranger), type: AccessDocument::SPT)         # InactiveRanger
    document(person(:alpha_ranger), type: AccessDocument::SPT)            # AlphaNewbie
    document(person(:plate_collision_ranger), type: AccessDocument::SPT)  # RANGER1

    assert_equal %w[AlphaNewbie InactiveRanger RANGER1 TestRanger], callsigns
  end

  test "callsign ordering ignores letter case" do
    person(:alpha_ranger).update_column(:callsign, "aardvark")
    document(person(:active_ranger), type: AccessDocument::SPT)  # TestRanger
    document(person(:alpha_ranger), type: AccessDocument::SPT)   # aardvark

    assert_equal %w[aardvark TestRanger], callsigns
  end

  # --- arrival-date problems ------------------------------------------------

  test "flags a Staff Credential with no access date" do
    ranger = person(:active_ranger)
    doc = document(ranger, type: AccessDocument::STAFF_CREDENTIAL)

    assert_equal ["RAD-#{doc.id} - missing access date"], summary_for(ranger)[:errors]
  end

  test "flags an access date left behind in a prior year" do
    ranger = person(:active_ranger)
    doc = document(ranger, type: AccessDocument::SAP, access_date: Time.zone.local(YEAR - 1, 8, 10, 12, 0, 0))

    assert_equal ["RAD-#{doc.id} - access date [#{YEAR - 1}-08-10 12:00:00] is less than current year [#{YEAR}]"],
                 summary_for(ranger)[:errors]
  end

  test "flags an access date whose day falls outside the allowable range" do
    ranger = person(:active_ranger)
    early = document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(3))
    late = document(ranger, type: AccessDocument::SAPSO, access_date: august(30), name: "Significant Other")

    assert_equal [
      "RAD-#{early.id} - access date [#{YEAR}-08-03 12:00:00] outside day [3] range low [5], high [26]",
      "RAD-#{late.id} - access date [#{YEAR}-08-30 12:00:00] outside day [30] range low [5], high [26]"
    ], summary_for(ranger)[:errors]
  end

  test "the allowable day range is inclusive of its endpoints" do
    ranger = person(:active_ranger)
    document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(5))
    document(ranger, type: AccessDocument::SAP, access_date: august(26))

    assert_empty summary_for(ranger)[:errors]
  end

  test "an in-range date, anytime access, and documents without arrival dates raise nothing" do
    ranger = person(:active_ranger)
    document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(10))
    document(ranger, type: AccessDocument::SAP, access_any_time: true)
    document(ranger, type: AccessDocument::SPT)
    document(ranger, type: AccessDocument::VEHICLE_PASS_SP)

    assert_empty summary_for(ranger)[:errors]
  end

  test "only the offending document is named in the error list" do
    ranger = person(:active_ranger)
    document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(10))
    offender = document(ranger, type: AccessDocument::SAP, access_date: august(28))

    assert_equal ["RAD-#{offender.id} - access date [#{YEAR}-08-28 12:00:00] outside day [28] range low [5], high [26]"],
                 summary_for(ranger)[:errors]
  end

  test "errors belong to the holder of the offending document" do
    ranger = person(:active_ranger)
    other = person(:inactive_ranger)
    doc = document(other, type: AccessDocument::STAFF_CREDENTIAL)
    document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(10))

    assert_empty summary_for(ranger)[:errors]
    assert_equal ["RAD-#{doc.id} - missing access date"], summary_for(other)[:errors]
  end

  # --- the allowable day range ---------------------------------------------

  test "the day range comes from the TAS_SAPDateRange setting" do
    sap_date_range("8 - 20")

    result = summary

    assert_equal 8, result[:day_low]
    assert_equal 20, result[:day_high]
  end

  test "the configured day range drives the access date check" do
    sap_date_range("8-20")
    ranger = person(:active_ranger)
    doc = document(ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(6))

    assert_equal ["RAD-#{doc.id} - access date [#{YEAR}-08-06 12:00:00] outside day [6] range low [8], high [20]"],
                 summary_for(ranger)[:errors]
  end

  test "the day range falls back to 5 and 26 when the setting is missing" do
    result = summary

    assert_equal 5, result[:day_low]
    assert_equal 26, result[:day_high]
  end

  test "the day range falls back to 5 and 26 when the setting cannot be read" do
    ["", "   ", "5", "5-26-27", "five-twentysix", "-", "5-", "5 to 26"].each do |value|
      sap_date_range(value)

      result = summary

      assert_equal 5, result[:day_low], "#{value.inspect} should fall back to the default low day"
      assert_equal 26, result[:day_high], "#{value.inspect} should fall back to the default high day"
    end
  end
end
