# frozen_string_literal: true

require "test_helper"

# Which people each BMID management category covers, and what the listing hands
# back once they are resolved to badges.
#
# The categories sweep whole tables and the shared fixtures belong to other
# suites, so every test starts from empty tables and builds exactly the records
# it needs.
class BmidManagementTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Current.reset
    Bmid.delete_all
    AccessDocument.delete_all
    Provision.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    Setting.where(name: Setting::TAS_DEFAULT_SAP_DATE).delete_all
    Setting.create!(name: Setting::TAS_DEFAULT_SAP_DATE, value: "#{YEAR}-08-15")
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- the filter menu ------------------------------------------------------

  test "the filter list offers every category the page can ask for" do
    assert_equal %w[special alpha qualified nonprint no-shifts in_prep ready_to_print submitted],
                 BmidManagement::FILTERS
    assert_equal BmidManagement::FILTERS, BmidManagement::FILTER_OPTIONS.map(&:last)
    assert_equal BmidManagement::SPECIAL, BmidManagement::DEFAULT_FILTER
  end

  # --- special: badges carrying something printable -------------------------

  test "special covers badges carrying a title, meals, or showers" do
    lead = person(:active_ranger)
    badge(lead, title1: "Shift Lead")

    green_dot = person(:inactive_ranger)
    badge(green_dot, title2: "Green Dot")

    double_oh = person(:retired_ranger)
    badge(double_oh, title3: "007")

    fed = person(:echelon_ranger)
    badge(fed, meals: "all")

    washed = person(:alpha_ranger)
    badge(washed, showers: true)

    badge(person(:auditor_ranger))

    assert_equal [lead, green_dot, double_oh, fed, washed].map(&:id).sort,
                 ids(BmidManagement::SPECIAL)
  end

  test "special only looks at the requested year's badges" do
    holder = person(:active_ranger)
    badge(holder, year: YEAR - 1, title1: "Shift Lead")

    assert_empty ids(BmidManagement::SPECIAL)
    assert_equal [holder.id], ids(BmidManagement::SPECIAL, year: YEAR - 1)
  end

  # --- special: people arriving before everyone else -------------------------

  test "special covers any-time access and arrivals before the default SAP date" do
    any_time = person(:active_ranger)
    document(any_time, access_any_time: true)

    early = person(:inactive_ranger)
    document(early, access_date: Time.zone.local(YEAR, 8, 1, 12, 0, 0))

    document(person(:retired_ranger), access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    assert_equal [any_time, early].map(&:id).sort, ids(BmidManagement::SPECIAL)
  end

  test "special ignores an early access date belonging to another year" do
    document(person(:active_ranger), access_date: Time.zone.local(YEAR - 1, 8, 1, 12, 0, 0))

    assert_empty ids(BmidManagement::SPECIAL)
  end

  test "special ignores access documents of the wrong type or status" do
    document(person(:active_ranger), type: AccessDocument::SPT, access_any_time: true)
    document(person(:inactive_ranger), status: AccessDocument::CANCELLED, access_any_time: true)

    assert_empty ids(BmidManagement::SPECIAL)
  end

  test "with no default SAP date on file only any-time access counts as early" do
    Setting.where(name: Setting::TAS_DEFAULT_SAP_DATE).delete_all

    any_time = person(:active_ranger)
    document(any_time, access_any_time: true)
    document(person(:inactive_ranger), access_date: Time.zone.local(YEAR, 8, 1, 12, 0, 0))

    assert_equal [any_time.id], ids(BmidManagement::SPECIAL)
  end

  test "an unreadable default SAP date is treated as no date at all" do
    # Written past the validations: the Laravel side shares this table and the
    # page must not blow up on whatever it left behind.
    Setting.where(name: Setting::TAS_DEFAULT_SAP_DATE).update_all(value: "whenever")

    any_time = person(:active_ranger)
    document(any_time, access_any_time: true)
    document(person(:inactive_ranger), access_date: Time.zone.local(YEAR, 8, 1, 12, 0, 0))

    assert_equal [any_time.id], ids(BmidManagement::SPECIAL)
  end

  # --- special: wet spot & meal provisions ----------------------------------

  test "special covers wet spot and meal provisions from any year" do
    washed = person(:active_ranger)
    provision_for(washed, source_year: YEAR - 3)

    fed = person(:inactive_ranger)
    provision_for(fed, type: Provision::MEALS, event_week_meals: true)

    provision_for(person(:retired_ranger), type: Provision::EVENT_RADIO, item_count: 1)
    provision_for(person(:echelon_ranger), status: Provision::BANKED)

    assert_equal [washed, fed].map(&:id).sort, ids(BmidManagement::SPECIAL)
  end

  test "special counts someone matching two of its arms once" do
    both = person(:active_ranger)
    badge(both, title1: "Shift Lead")
    provision_for(both)

    assert_equal [both.id], BmidManagement.category_person_ids(BmidManagement::SPECIAL, YEAR)
  end

  # --- alpha ----------------------------------------------------------------

  test "alpha covers alphas and prospectives whatever else is true of them" do
    assert_equal [person(:alpha_ranger), person(:prospective_ranger)].map(&:id).sort,
                 ids(BmidManagement::ALPHA)
  end

  test "alpha does not care which year is being managed" do
    assert_equal ids(BmidManagement::ALPHA), ids(BmidManagement::ALPHA, year: YEAR - 5)
  end

  # --- qualified ------------------------------------------------------------

  test "qualified covers active people holding a claimed or submitted ticket" do
    claimed = person(:active_ranger)
    document(claimed, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)

    submitted = person(:inactive_ranger)
    document(submitted, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::SUBMITTED)

    # Qualified is not claimed: the ticket is offered, not taken.
    document(person(:retired_ranger), type: AccessDocument::SAP, status: AccessDocument::QUALIFIED)
    # An Alpha is not an active Ranger; the alpha category covers them instead.
    document(person(:alpha_ranger), type: AccessDocument::SPT, status: AccessDocument::CLAIMED)

    assert_equal [claimed, submitted].map(&:id).sort, ids(BmidManagement::QUALIFIED)
  end

  test "qualified takes a claimed ticket from any source year" do
    holder = person(:active_ranger)
    document(holder, type: AccessDocument::SPT, status: AccessDocument::CLAIMED, source_year: YEAR - 2)

    assert_equal [holder.id], ids(BmidManagement::QUALIFIED)
  end

  test "qualified covers active people signed up for in-person training" do
    trainee = person(:active_ranger)
    sign_up(trainee, slot_for(Position::TRAINING))

    uber = person(:inactive_ranger)
    sign_up(uber, slot_for(Position::TRAINER_UBER))

    assert_equal [trainee, uber].map(&:id).sort, ids(BmidManagement::QUALIFIED)
  end

  test "qualified ignores sign-ups on the wrong year, slot, or position" do
    sign_up(person(:active_ranger), slot_for(Position::TRAINING, year: YEAR - 1))
    sign_up(person(:inactive_ranger), slot_for(Position::TRAINING, active: false))
    sign_up(person(:retired_ranger), slot_for(Position::OOD))
    sign_up(person(:alpha_ranger), slot_for(Position::TRAINING))

    assert_empty ids(BmidManagement::QUALIFIED)
  end

  test "qualified counts someone with both a ticket and a training sign-up once" do
    both = person(:active_ranger)
    document(both, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
    sign_up(both, slot_for(Position::TRAINING))

    assert_equal [both.id], BmidManagement.category_person_ids(BmidManagement::QUALIFIED, YEAR)
  end

  # --- nonprint & the status categories -------------------------------------

  test "nonprint covers this year's badges marked issues or do not print" do
    issues = person(:active_ranger)
    badge(issues, status: Bmid::ISSUES)

    blocked = person(:inactive_ranger)
    badge(blocked, status: Bmid::DO_NOT_PRINT)

    badge(person(:retired_ranger), status: Bmid::IN_PREP)
    badge(person(:echelon_ranger), year: YEAR - 1, status: Bmid::ISSUES)

    assert_equal [issues, blocked].map(&:id).sort, ids(BmidManagement::NONPRINT)
  end

  test "the status categories select badges by their own status" do
    prepping = person(:active_ranger)
    badge(prepping, status: Bmid::IN_PREP)

    printing = person(:inactive_ranger)
    badge(printing, status: Bmid::READY_TO_PRINT)

    sent = person(:retired_ranger)
    badge(sent, status: Bmid::SUBMITTED)

    badge(person(:echelon_ranger), status: Bmid::READY_TO_REPRINT_LOST)

    assert_equal [prepping.id], ids(Bmid::IN_PREP)
    assert_equal [printing.id], ids(Bmid::READY_TO_PRINT)
    assert_equal [sent.id], ids(Bmid::SUBMITTED)
  end

  # --- no-shifts ------------------------------------------------------------

  test "no-shifts covers badge holders with nothing on this year's schedule" do
    idle = person(:active_ranger)
    badge(idle)

    stale = person(:retired_ranger)
    badge(stale)
    sign_up(stale, slot_for(Position::OOD, year: YEAR - 1))

    busy = person(:inactive_ranger)
    badge(busy)
    sign_up(busy, slot_for(Position::OOD))

    # A cancelled shift is still a shift: upstream never checks slot.active here.
    cancelled = person(:echelon_ranger)
    badge(cancelled)
    sign_up(cancelled, slot_for(Position::OOD, active: false))

    assert_equal [idle, stale].map(&:id).sort, ids(BmidManagement::NO_SHIFTS)
  end

  test "no-shifts only considers people who already have a badge" do
    person(:active_ranger) # no badge, no shifts, still not listed

    assert_empty ids(BmidManagement::NO_SHIFTS)
  end

  # --- unknown filters ------------------------------------------------------

  test "an unrecognized filter falls back to special" do
    lead = person(:active_ranger)
    badge(lead, title1: "Shift Lead")

    assert_equal [lead.id], ids("nonsense")
    assert_equal [lead.id], ids(nil)
    assert_equal ids(BmidManagement::SPECIAL), ids("")
  end

  # --- retrieve_category_to_manage -------------------------------------------

  test "the listing synthesizes a badge for everyone in the category, sorted by callsign" do
    saved = person(:alpha_ranger)
    badge(saved, title1: "Alpha")
    missing = person(:prospective_ranger)

    rows = BmidManagement.retrieve_category_to_manage(BmidManagement::ALPHA, YEAR)

    assert_equal [saved, missing].map(&:id).sort, rows.map(&:person_id).sort
    assert_equal rows.map { |row| row.person.callsign.downcase }.sort,
                 rows.map { |row| row.person.callsign.downcase }

    synthesized = rows.find { |row| row.person_id == missing.id }
    assert_nil synthesized.id
    assert_equal Bmid::IN_PREP, synthesized.status
  end

  test "the current year's listing leaves departed people out entirely" do
    departed = person(:deceased_ranger)
    badge(departed, title1: "Shift Lead")

    live = person(:active_ranger)
    badge(live, title1: "Shift Lead")

    rows = BmidManagement.retrieve_category_to_manage(BmidManagement::SPECIAL, YEAR)

    assert_equal [live.id], rows.map(&:person_id)
  end

  test "a past year's listing still shows departed people" do
    departed = person(:deceased_ranger)
    badge(departed, year: YEAR - 1, title1: "Shift Lead")

    rows = BmidManagement.retrieve_category_to_manage(BmidManagement::SPECIAL, YEAR - 1)

    assert_equal [departed.id], rows.map(&:person_id)
  end

  private

  def ids(filter, year: YEAR)
    BmidManagement.category_person_ids(filter, year).uniq.sort
  end

  def badge(holder, year: YEAR, status: Bmid::IN_PREP, **attributes)
    Bmid.create!(person: holder, year:, status:, **attributes)
  end
end
