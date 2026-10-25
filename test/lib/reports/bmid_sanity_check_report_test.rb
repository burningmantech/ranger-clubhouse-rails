# frozen_string_literal: true

require "test_helper"

# The four sanity checks behind BMID > Sanity Check: who each one flags, who
# clears it, and what the reason strings say.
#
# Same harness as the other bmid suites: the checks sweep whole tables and the
# shared fixtures belong to other suites, so every test starts from empty
# tables and builds exactly the records it needs.
class BmidSanityCheckReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  # An arbitrary non-training position for check-1 shifts.
  DIRT = 999

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset
    AccessDocument.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    Setting.where(name: Setting::TAS_BOX_OFFICE_OPEN_DATE).delete_all
    Setting.create!(name: Setting::TAS_BOX_OFFICE_OPEN_DATE, value: "#{YEAR}-08-26 12:00:00")
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- shifts before the access date (checks 1 and 2) ------------------------

  test "flags a shift starting before the access date on the best live document" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 6, 15, 0)))
    doc = document(holder, status: AccessDocument::CLAIMED,
                           access_date: Time.zone.local(YEAR, 8, 25, 12, 0, 0))

    result = execute
    row = result.shifts_before_access_date.sole

    assert_equal holder.id, row.person.id
    assert_empty result.shifts_before_submitted_wap
    assert_includes row.reason, "Position #{DIRT}"
    assert_includes row.reason, doc.display_ref
    assert_includes row.reason, "access date #{YEAR}-08-25"
    assert_includes row.reason, "status claimed"
  end

  test "a submitted document lands the person in the submitted bucket instead" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 6, 15, 0)))
    document(holder, status: AccessDocument::SUBMITTED,
                     access_date: Time.zone.local(YEAR, 8, 25, 12, 0, 0))

    result = execute

    assert_empty result.shifts_before_access_date
    assert_equal [holder.id], result.shifts_before_submitted_wap.map { |row| row.person.id }
  end

  test "any-time access clears the person, dateless strays and late documents included" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 6, 15, 0)))
    document(holder, status: AccessDocument::CLAIMED) # no date, no any-time: a "bad" doc
    document(holder, status: AccessDocument::CLAIMED,
                     access_date: Time.zone.local(YEAR, 8, 25, 12, 0, 0))
    document(holder, type: AccessDocument::STAFF_CREDENTIAL,
                     status: AccessDocument::CLAIMED, access_any_time: true)

    result = execute

    assert_empty result.shifts_before_access_date
    assert_empty result.shifts_before_submitted_wap
    assert_empty result.shifts_no_wap
  end

  test "the earliest-dated document is the one the reason names" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 6, 15, 0)))
    late = document(holder, status: AccessDocument::CLAIMED,
                            access_date: Time.zone.local(YEAR, 8, 25, 12, 0, 0))
    early = document(holder, status: AccessDocument::CLAIMED,
                             access_date: Time.zone.local(YEAR, 8, 22, 12, 0, 0))

    row = execute.shifts_before_access_date.sole

    assert_includes row.reason, early.display_ref
    assert_not_includes row.reason, late.display_ref
  end

  test "no usable document is a no-SAP finding listing the shift, banked credentials, and dateless strays" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 16, 9, 0, 0)))
    banked = document(holder, type: AccessDocument::STAFF_CREDENTIAL,
                              status: AccessDocument::BANKED)
    dateless = document(holder, status: AccessDocument::CLAIMED) # live but dateless

    result = execute
    row = result.shifts_no_wap.sole

    assert_empty result.shifts_before_access_date
    assert_includes row.reason, "No usable SAP or Staff Credential."
    assert_includes row.reason, "First shift Position #{DIRT}"
    assert_includes row.reason, "#{banked.display_ref} Staff Credential banked."
    assert_includes row.reason, "#{dateless.display_ref} SAP status claimed has no access date."
  end

  test "an access date before the first shift clears the person everywhere" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
    document(holder, status: AccessDocument::CLAIMED,
                     access_date: Time.zone.local(YEAR, 8, 16, 12, 0, 0))

    assert_equal 0, execute.total
  end

  # --- pool asymmetries between check 1 and check 3 --------------------------

  test "training shifts are invisible to check 1 but count for check 3" do
    holder = person(:active_ranger)
    sign_up(holder, slot_for(Position::TRAINING, begins: Time.zone.local(YEAR, 8, 20, 9, 0, 0)))

    result = execute

    assert_empty result.shifts_before_access_date
    assert_equal [holder.id], result.shifts_no_wap.map { |row| row.person.id }
  end

  test "each check pools by its own cutoff and only check 1 requires an active slot" do
    # Aug 14: before the event cutoff, after the early cutoff -- check 3 only.
    early_bird = person(:active_ranger)
    sign_up(early_bird, event_slot(begins: Time.zone.local(YEAR, 8, 14, 12, 0, 0)))

    # Aug 9: before both cutoffs -- flagged nowhere.
    too_early = person(:retired_ranger)
    sign_up(too_early, event_slot(begins: Time.zone.local(YEAR, 8, 9, 12, 0, 0)))

    # Inactive Aug 20 slot: outside check 1's pool, still inside check 3's.
    unpublished = person(:inactive_ranger)
    sign_up(unpublished, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0), active: false))

    result = execute

    assert_empty result.shifts_before_access_date
    assert_equal [early_bird.id, unpublished.id].sort,
                 result.shifts_no_wap.map { |row| row.person.id }.sort
  end

  test "a banked-only staff credential is a no-SAP finding, not a date conflict" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
    banked = document(holder, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED)

    result = execute
    row = result.shifts_no_wap.sole

    assert_equal holder.id, row.person.id
    assert_empty result.shifts_before_access_date
    assert_includes row.reason, "#{banked.display_ref} Staff Credential banked."
  end

  test "statuses that never flag stay out of checks 1 and 3" do
    [person(:past_prospective_ranger), person(:alpha_ranger)].each do |bystander|
      sign_up(bystander, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
    end

    assert_equal 0, execute.total
  end

  # --- SPT access before the box office opens (check 4) ----------------------

  test "flags a live SPT holder whose SAP opens before the box office" do
    holder = person(:active_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    sap = document(holder, status: AccessDocument::CLAIMED,
                           access_date: Time.zone.local(YEAR, 8, 24, 12, 0, 0))

    # A SAP after the box office opens is fine.
    patient = person(:retired_ranger)
    document(patient, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(patient, status: AccessDocument::CLAIMED,
                      access_date: Time.zone.local(YEAR, 8, 27, 12, 0, 0))

    # An early SAP without an SPT is someone else's problem.
    document(person(:echelon_ranger), status: AccessDocument::CLAIMED,
                                      access_date: Time.zone.local(YEAR, 8, 24, 12, 0, 0))

    row = execute.spt_before_box_office.sole

    assert_equal holder.id, row.person.id
    assert_includes row.reason, sap.display_ref
    assert_includes row.reason, "status claimed"
    assert_includes row.reason, "access date #{YEAR}-08-24"
  end

  test "check 4 keeps upstream's shorter exclusion list: past prospective is flagged" do
    flagged = person(:past_prospective_ranger)
    document(flagged, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(flagged, status: AccessDocument::CLAIMED,
                      access_date: Time.zone.local(YEAR, 8, 24, 12, 0, 0))

    skipped = person(:alpha_ranger)
    document(skipped, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(skipped, status: AccessDocument::CLAIMED,
                      access_date: Time.zone.local(YEAR, 8, 24, 12, 0, 0))

    assert_equal [flagged.id], execute.spt_before_box_office.map { |row| row.person.id }
  end

  test "a blank box office setting sits the check out instead of raising" do
    Setting.where(name: Setting::TAS_BOX_OFFICE_OPEN_DATE).delete_all

    holder = person(:active_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    document(holder, status: AccessDocument::CLAIMED,
                     access_date: Time.zone.local(YEAR, 8, 24, 12, 0, 0))

    result = execute

    assert_nil result.box_office_open
    assert_empty result.spt_before_box_office
  end

  # --- shape ------------------------------------------------------------------

  test "rows come back callsign-sorted, case-insensitively" do
    first, second = [person(:retired_ranger), person(:active_ranger)]
                    .sort_by { |ranger| ranger.callsign.downcase }
    [second, first].each do |holder|
      sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
    end

    assert_equal [first.callsign, second.callsign],
                 execute.shifts_no_wap.map { |row| row.person.callsign }
  end

  test "findings merges the checks callsign-first and can narrow to one check" do
    holder = person(:active_ranger)
    sign_up(holder, event_slot(begins: Time.zone.local(YEAR, 8, 20, 12, 0, 0)))
    # A dated SAP after the first shift and before the box office, plus a live
    # SPT: one person, one finding each in checks 1 and 4.
    document(holder, status: AccessDocument::CLAIMED,
                     access_date: Time.zone.local(YEAR, 8, 23, 12, 0, 0))
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)

    result = execute

    assert_equal({ shifts_before_access_date: 1, shifts_before_submitted_wap: 0,
                   shifts_no_wap: 0, spt_before_box_office: 1 }, result.counts)
    assert_equal 2, result.total
    assert_equal %i[shifts_before_access_date spt_before_box_office],
                 result.findings.map(&:check)
    assert_equal %i[spt_before_box_office],
                 result.findings(check: "spt_before_box_office").map(&:check)
  end

  test "an empty year yields four empty checks" do
    result = execute

    assert_equal 0, result.total
    BmidSanityCheckReport::CHECK_KEYS.each { |key| assert_empty result.public_send(key) }
  end

  private

  def execute
    BmidSanityCheckReport.execute(YEAR)
  end

  # An active, non-training slot inside the event window unless told otherwise.
  def event_slot(begins:, active: true)
    slot_for(DIRT, begins:, active:)
  end
end
