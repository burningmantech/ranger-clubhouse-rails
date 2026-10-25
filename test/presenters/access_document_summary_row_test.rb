# frozen_string_literal: true

require "test_helper"

# Exercises AccessDocumentSummaryRow, the per-person row of the Ticketing >
# Access Documents summary: which document fills each cell, how the cell is
# tinted, and everything that lands in the Weird Stuff column.
#
# The row is a value object over a list of documents, so the documents are built
# unsaved -- that keeps each case in exactly the state under test instead of
# whatever AccessDocument's before_save callbacks would rewrite it to.
class AccessDocumentSummaryRowTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- helpers -------------------------------------------------------------

  def doc(type, status: AccessDocument::QUALIFIED, **attributes)
    AccessDocument.new(type:, status:, source_year: YEAR, **attributes)
  end

  def august(day)
    Time.zone.local(YEAR, 8, day, 12, 0, 0)
  end

  def row(*documents, errors: [])
    AccessDocumentSummaryRow.new(person: person(:active_ranger), documents:, errors:)
  end

  # --- arrival fallback chain ----------------------------------------------

  test "arrival prefers a claimed Staff Credential over everything else" do
    summary_row = row(
      doc(AccessDocument::STAFF_CREDENTIAL, access_date: august(20)),
      doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_date: august(10)),
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED, access_date: august(25))
    )

    assert_equal "Tue Aug 25", summary_row.arrival.value
    assert_equal AccessDocument::CLAIMED, summary_row.arrival.status
  end

  test "arrival falls back to a Setup Access Pass when no Staff Credential is claimed" do
    summary_row = row(
      doc(AccessDocument::STAFF_CREDENTIAL, access_date: august(20)),
      doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_date: august(10))
    )

    assert_equal "Mon Aug 10", summary_row.arrival.value
    assert_equal AccessDocument::CLAIMED, summary_row.arrival.status
  end

  test "arrival falls back to any Staff Credential when there is no SAP" do
    summary_row = row(doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED, access_date: august(12)))

    assert_equal "Wed Aug 12", summary_row.arrival.value
    assert_equal AccessDocument::BANKED, summary_row.arrival.status
  end

  # A ticket on its own carries no arrival date, so the cell is empty rather
  # than missing -- three quarters of the people on this page are in this state
  # and none of them has a problem.
  test "arrival is empty when the person holds neither a Staff Credential nor a SAP" do
    summary_row = row(doc(AccessDocument::SPT, status: AccessDocument::CLAIMED))

    assert_predicate summary_row.arrival, :empty?
    assert_nil summary_row.arrival.value
    assert_not summary_row.arrival_missing?
    assert_nil summary_row.arrival.status
  end

  test "arrival is missing when the arrival document carries no access date" do
    summary_row = row(doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED))

    assert_equal AccessDocumentSummaryRow::ARRIVAL_MISSING, summary_row.arrival.value
    assert summary_row.arrival_missing?
  end

  test "arrival reads Anytime for an any-time access document" do
    summary_row = row(doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_any_time: true))

    assert_equal AccessDocumentSummaryRow::ARRIVAL_ANY_TIME, summary_row.arrival.value
    assert_not summary_row.arrival_missing?
  end

  test "a qualified arrival document leaves the cell untinted" do
    summary_row = row(doc(AccessDocument::SAP, access_date: august(10)))

    assert_equal "Mon Aug 10", summary_row.arrival.value
    assert_nil summary_row.arrival.status
  end

  # --- SC + SAP -------------------------------------------------------------

  test "notes SC+SAP when the person arrives on a Staff Credential and also holds a SAP" do
    summary_row = row(
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED, access_date: august(25)),
      doc(AccessDocument::SAP, access_date: august(10))
    )

    assert_includes summary_row.notes, "SC+SAP"
  end

  # Upstream (access-documents-for-person.js) only raises the combination when
  # the arrival document itself is the Staff Credential. With no claimed SC the
  # SAP wins the lookup and the pairing goes unremarked.
  test "SC+SAP is not noted when the SAP is the arrival document" do
    summary_row = row(
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED, access_date: august(25)),
      doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_date: august(10))
    )

    assert_not_includes summary_row.notes, "SC+SAP"
  end

  test "notes more than one SAP" do
    summary_row = row(
      doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_date: august(10)),
      doc(AccessDocument::SAP, access_date: august(12))
    )

    assert_includes summary_row.notes, "2 SAPs"
  end

  test "a single SAP is not noted" do
    summary_row = row(doc(AccessDocument::SAP, status: AccessDocument::CLAIMED, access_date: august(10)))

    assert_empty summary_row.notes
  end

  # --- tickets --------------------------------------------------------------

  test "the ticket cell shows the short label of the first regular ticket" do
    summary_row = row(doc(AccessDocument::SPT, status: AccessDocument::CLAIMED))

    assert_equal "SPT", summary_row.tickets.value
    assert_equal AccessDocument::CLAIMED, summary_row.tickets.status
    assert_empty summary_row.notes
  end

  test "the ticket cell is empty when the person holds no regular ticket" do
    summary_row = row(doc(AccessDocument::GIFT, name: "Gift Recipient"))

    assert summary_row.tickets.empty?
    assert_nil summary_row.tickets.value
  end

  test "notes more than one ticket" do
    summary_row = row(
      doc(AccessDocument::SPT, status: AccessDocument::CLAIMED),
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED, access_date: august(12))
    )

    assert_includes summary_row.notes, "2 tickets"
    assert_equal "SPT", summary_row.tickets.value
    assert_equal AccessDocument::CLAIMED, summary_row.tickets.status
  end

  # --- expired tickets ------------------------------------------------------

  test "notes a banked ticket past its expiry date" do
    summary_row = row(doc(AccessDocument::SPT, status: AccessDocument::BANKED,
                          expiry_date: Date.new(YEAR - 1, 9, 15)))

    assert_includes summary_row.notes, "SPT #{AccessDocumentSummaryRow::EXPIRED_NOTE}"
  end

  test "notes a qualified ticket past its expiry date alongside the ticket count" do
    summary_row = row(
      doc(AccessDocument::SPT, expiry_date: Date.new(YEAR - 1, 9, 15)),
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED,
          access_date: august(25), expiry_date: Date.new(YEAR + 2, 9, 15))
    )

    assert_includes summary_row.notes, "2 tickets; SPT #{AccessDocumentSummaryRow::EXPIRED_NOTE}"
  end

  test "names each expired ticket rather than repeating a bare EXPIRED" do
    summary_row = row(
      doc(AccessDocument::SPT, status: AccessDocument::BANKED,
          expiry_date: Date.new(YEAR - 1, 9, 15)),
      doc(AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED,
          access_date: august(25), expiry_date: Date.new(YEAR - 1, 9, 15))
    )

    note = summary_row.notes.find { |n| n.include?(AccessDocumentSummaryRow::EXPIRED_NOTE) }

    assert_equal "2 tickets; SPT EXPIRED SC EXPIRED", note
    refute_includes note, "EXPIRED EXPIRED"
  end

  test "a claimed ticket past its expiry date is not flagged" do
    summary_row = row(doc(AccessDocument::SPT, status: AccessDocument::CLAIMED,
                          expiry_date: Date.new(YEAR - 1, 9, 15)))

    assert_empty summary_row.notes
  end

  test "a banked ticket still inside its expiry date is not flagged" do
    summary_row = row(doc(AccessDocument::SPT, status: AccessDocument::BANKED,
                          expiry_date: Date.new(YEAR + 2, 9, 15)))

    assert_empty summary_row.notes
  end

  # --- vehicle passes -------------------------------------------------------

  test "the VP cell shows the short label of the first vehicle pass" do
    summary_row = row(doc(AccessDocument::VEHICLE_PASS_GIFT, status: AccessDocument::CLAIMED))

    assert_equal "VPGIFT", summary_row.vp.value
    assert_equal AccessDocument::CLAIMED, summary_row.vp.status
    assert_empty summary_row.notes
  end

  test "notes more than one vehicle pass" do
    summary_row = row(
      doc(AccessDocument::VEHICLE_PASS_SP, status: AccessDocument::CLAIMED),
      doc(AccessDocument::VEHICLE_PASS_GIFT)
    )

    assert_includes summary_row.notes, "2 VPs"
    assert_equal "VPSP", summary_row.vp.value
    assert_equal AccessDocument::CLAIMED, summary_row.vp.status
  end

  test "an LSD vehicle pass is counted as special, not as a vehicle pass" do
    summary_row = row(
      doc(AccessDocument::VEHICLE_PASS_SP, status: AccessDocument::CLAIMED),
      doc(AccessDocument::VEHICLE_PASS_LSD, status: AccessDocument::CLAIMED)
    )

    assert_equal "VPSP", summary_row.vp.value
    assert_equal 1, summary_row.special.lsd_vp
    assert_not_includes summary_row.notes, "2 VPs"
  end

  # --- significant-other SAPs ----------------------------------------------

  test "counts SO SAPs and leaves three of them unremarked" do
    summary_row = row(*Array.new(3) do
      doc(AccessDocument::SAPSO, status: AccessDocument::CLAIMED, access_date: august(10), name: "SO")
    end)

    assert_equal 3, summary_row.so_count
    assert_equal AccessDocument::CLAIMED, summary_row.so_status
    assert_empty summary_row.notes
  end

  test "notes more than three SO SAPs" do
    summary_row = row(*Array.new(4) do
      doc(AccessDocument::SAPSO, status: AccessDocument::CLAIMED, access_date: august(10), name: "SO")
    end)

    assert_equal 4, summary_row.so_count
    assert_includes summary_row.notes, "4 WAPSOs"
  end

  test "the SO SAP count is zero when the person holds none" do
    summary_row = row(doc(AccessDocument::SPT))

    assert_equal 0, summary_row.so_count
    assert_nil summary_row.so_status
  end

  # --- special documents ----------------------------------------------------

  test "counts gift, LSD, and LSD vehicle pass documents" do
    summary_row = row(
      doc(AccessDocument::GIFT, name: "First"),
      doc(AccessDocument::GIFT, name: "Second"),
      doc(AccessDocument::LSD, status: AccessDocument::CLAIMED, name: "Third"),
      doc(AccessDocument::VEHICLE_PASS_LSD, status: AccessDocument::CLAIMED)
    )

    assert_equal 2, summary_row.special.gift
    assert_equal 1, summary_row.special.lsd
    assert_equal 1, summary_row.special.lsd_vp
    assert_not summary_row.special.empty?
  end

  test "special is empty when the person holds no gift or LSD documents" do
    summary_row = row(doc(AccessDocument::SPT))

    assert summary_row.special.empty?
    assert_equal 0, summary_row.special.gift
    assert_equal 0, summary_row.special.lsd
    assert_equal 0, summary_row.special.lsd_vp
  end

  # --- pass-through ---------------------------------------------------------

  test "carries the person, documents, and pre-formatted errors through untouched" do
    document = doc(AccessDocument::SPT)
    errors = ["RAD-42 - missing access date"]

    summary_row = row(document, errors:)

    assert_equal person(:active_ranger), summary_row.person
    assert_equal [document], summary_row.documents
    assert_equal errors, summary_row.errors
  end
end
