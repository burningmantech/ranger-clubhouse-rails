# frozen_string_literal: true

require "test_helper"

# Business rules for every /ticketing/maintenance task: what each one selects,
# what it changes records to, and what its ledger reports. The controller test
# covers the routing/auth plumbing; this file exercises the tasks directly.
#
# The tasks sweep whole tables, and the shared fixtures belong to other suites,
# so every test starts from empty tables and builds exactly the rows it needs.
class TicketingMaintenanceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    # September: the event is over, so maintenance_year == YEAR.
    travel_to Time.zone.local(YEAR, 9, 10, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @person = person(:active_ranger)
    @other = person(:ranger_with_custom_gender)
    @alpha = person(:alpha_ranger)

    AccessDocument.delete_all
    Provision.delete_all
    Timesheet.delete_all
    PersonSlot.delete_all
    Bmid.delete_all
    PersonAsset.delete_all
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  test "maintenance_year is last year's event until august" do
    travel_to Time.zone.local(YEAR, 7, 31) do
      assert_equal YEAR - 1, TicketingMaintenance.maintenance_year
    end
    travel_to Time.zone.local(YEAR, 8, 1) do
      assert_equal YEAR, TicketingMaintenance.maintenance_year
    end
  end

  test "find looks a task up by slug and misses unknown slugs" do
    assert_equal TicketingMaintenance::UnbankTickets, TicketingMaintenance.find("unbank-tickets")
    assert_nil TicketingMaintenance.find("mystery")
  end

  # --- unbank -----------------------------------------------------------------

  test "unbank tickets returns banked documents to qualified and previews save nothing" do
    banked = ticket_for(@person, status: AccessDocument::BANKED)
    ticket_for(@other, status: AccessDocument::CLAIMED)

    preview = TicketingMaintenance::UnbankTickets.execute(commit: false)

    assert_equal 1, preview.size
    assert_equal "banked → qualified", preview.first.change
    assert_equal AccessDocument::BANKED, banked.reload.status

    rows = TicketingMaintenance::UnbankTickets.execute(commit: true)

    assert_equal 1, rows.size
    assert_nil rows.first.error
    assert_equal AccessDocument::QUALIFIED, banked.reload.status
    assert_match "marked as qualified via maintenance function", banked.comments
  end

  test "unbank provisions returns banked provisions to available" do
    banked = provision_for(@person, status: Provision::BANKED)
    provision_for(@other, status: Provision::CLAIMED)

    rows = TicketingMaintenance::UnbankProvisions.execute(commit: true)

    assert_equal 1, rows.size
    assert_equal "banked → available", rows.first.change
    assert_equal Provision::AVAILABLE, banked.reload.status
  end

  # --- grants -----------------------------------------------------------------

  test "grant saps creates a qualified emailed sap for each candidate and logs the bulk grant" do
    default_sap_date
    sign_up(@person)

    rows = TicketingMaintenance::GrantSaps.execute(commit: true)

    assert_equal 1, rows.size
    assert_equal "new → qualified", rows.first.change
    sap = AccessDocument.find_by!(person_id: @person.id, type: AccessDocument::SAP)
    assert_equal AccessDocument::QUALIFIED, sap.status
    assert_equal AccessDocument::DELIVERY_EMAIL, sap.delivery_method
    assert_equal YEAR, sap.source_year
    assert_equal Date.new(YEAR, 8, 10), sap.access_date.to_date
    assert_match "created via maintenance function", sap.comments
    assert_equal 1, ActionLog.where(event: "access-document-bulk-grant").count
  end

  test "grant saps is blocked while the default access date setting is blank" do
    assert_match "TAS_DefaultWAPDate", TicketingMaintenance::GrantSaps.blocked_reason
    default_sap_date
    assert_nil TicketingMaintenance::GrantSaps.blocked_reason
  end

  test "grant alpha saps covers alphas and training prospectives but not the already covered" do
    Setting.create!(name: Setting::TAS_DEFAULT_ALPHA_SAP_DATE, value: "#{YEAR}-08-20")
    prospective = person(:prospective_ranger)
    training_sign_up(prospective)
    covered = person(:echelon_ranger)
    covered.update_columns(status: Person::ALPHA)
    ticket_for(covered, type: AccessDocument::SAP, status: AccessDocument::QUALIFIED,
               delivery_method: AccessDocument::DELIVERY_EMAIL)

    rows = TicketingMaintenance::GrantAlphaSaps.execute(commit: true)

    assert_equal [@alpha.callsign, prospective.callsign].sort_by(&:downcase),
                 rows.map { |row| row.person.callsign }
    sap = AccessDocument.find_by!(person_id: @alpha.id, type: AccessDocument::SAP)
    assert_equal AccessDocument::CLAIMED, sap.status
    assert_equal Date.new(YEAR, 8, 20), sap.access_date.to_date
    assert_equal 1, AccessDocument.where(person_id: covered.id, type: AccessDocument::SAP).count
  end

  test "grant vps matches ticket types to pass types and skips holders and the dismissed" do
    sc_holder = @person
    spt_holder = @other
    both_holder = person(:retired_ranger)
    dismissed = person(:echelon_ranger)
    dismissed.update_columns(status: Person::DISMISSED)

    ticket_for(sc_holder, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::QUALIFIED)
    ticket_for(spt_holder, type: AccessDocument::SPT, status: AccessDocument::BANKED)
    ticket_for(both_holder, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED)
    ticket_for(both_holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    ticket_for(dismissed, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    # An existing pass in a live status blocks a duplicate.
    ticket_for(sc_holder, type: AccessDocument::VEHICLE_PASS_GIFT, status: AccessDocument::CLAIMED)

    rows = TicketingMaintenance::GrantVps.execute(commit: true)

    assert_equal 3, rows.size
    granted = ->(holder, type) { AccessDocument.where(person_id: holder.id, type:, status: AccessDocument::QUALIFIED).count }
    assert_equal 1, granted.call(spt_holder, AccessDocument::VEHICLE_PASS_SP)
    assert_equal 1, granted.call(both_holder, AccessDocument::VEHICLE_PASS_GIFT)
    assert_equal 1, granted.call(both_holder, AccessDocument::VEHICLE_PASS_SP)
    assert_equal 0, granted.call(dismissed, AccessDocument::VEHICLE_PASS_SP)
    # The claimed pass blocked a duplicate; nothing qualified was added.
    assert_equal 0, granted.call(sc_holder, AccessDocument::VEHICLE_PASS_GIFT)
  end

  # --- staff credential access dates ------------------------------------------

  test "set sc access dates fills missing and stale dates and reports the dismissed as skipped" do
    default_sap_date
    missing = ticket_for(@person, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::QUALIFIED)
    stale = ticket_for(@other, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED,
                       access_date: Time.zone.local(YEAR - 1, 8, 1))
    current = ticket_for(person(:retired_ranger), type: AccessDocument::STAFF_CREDENTIAL,
                         status: AccessDocument::CLAIMED, access_date: Time.zone.local(YEAR, 8, 1))
    dismissed = person(:echelon_ranger)
    dismissed.update_columns(status: Person::DISMISSED)
    skipped = ticket_for(dismissed, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::QUALIFIED)

    rows = TicketingMaintenance::SetScAccessDates.execute(commit: true)

    assert_equal 3, rows.size
    assert_equal Time.zone.local(YEAR, 8, 10), missing.reload.access_date
    assert_equal Time.zone.local(YEAR, 8, 10), stale.reload.access_date
    assert_equal Time.zone.local(YEAR, 8, 1), current.reload.access_date
    assert_nil skipped.reload.access_date
    skip_row = rows.find { |row| row.person.id == dismissed.id }
    assert_equal "unchanged", skip_row.change
    assert_equal "person is dismissed", skip_row.detail
  end

  # --- post-event ticket sweeps ----------------------------------------------

  test "clean tickets consumes submitted documents and expires single-event types" do
    submitted = ticket_for(@person, type: AccessDocument::SPT, status: AccessDocument::SUBMITTED)
    single_event = ticket_for(@person, type: AccessDocument::SAP, status: AccessDocument::QUALIFIED,
                              delivery_method: AccessDocument::DELIVERY_EMAIL)
    keeper = ticket_for(@other, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)

    rows = TicketingMaintenance::CleanTickets.execute(commit: true)

    assert_equal 2, rows.size
    assert_equal AccessDocument::USED, submitted.reload.status
    assert_equal AccessDocument::EXPIRED, single_event.reload.status
    assert_equal AccessDocument::QUALIFIED, keeper.reload.status
  end

  test "bank tickets banks qualified tickets, scrubbing staff credential access dates in both passes" do
    plain = ticket_for(@person, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED)
    dated_sc = ticket_for(@other, type: AccessDocument::STAFF_CREDENTIAL,
                          status: AccessDocument::QUALIFIED, access_date: Time.zone.local(YEAR, 8, 1))
    parked_sc = ticket_for(person(:retired_ranger), type: AccessDocument::STAFF_CREDENTIAL,
                           status: AccessDocument::BANKED, access_date: Time.zone.local(YEAR, 8, 1))

    preview = TicketingMaintenance::BankTickets.execute(commit: false)
    assert_equal 3, preview.size
    assert_equal AccessDocument::QUALIFIED, plain.reload.status

    rows = TicketingMaintenance::BankTickets.execute(commit: true)

    assert_equal 3, rows.size
    assert_equal AccessDocument::BANKED, plain.reload.status
    assert_equal AccessDocument::BANKED, dated_sc.reload.status
    assert_nil dated_sc.access_date
    assert_nil parked_sc.reload.access_date
    assert_equal "access date → unspecified",
                 rows.find { |row| row.person.id == parked_sc.person_id }.change
  end

  test "expire tickets expires live documents dated today or earlier and reports emails" do
    due = ticket_for(@person, status: AccessDocument::BANKED, expiry_date: Date.current)
    overdue = ticket_for(@other, status: AccessDocument::QUALIFIED, expiry_date: Date.current - 1)
    not_yet = ticket_for(person(:retired_ranger), status: AccessDocument::CLAIMED,
                         expiry_date: Date.current + 1)

    rows = TicketingMaintenance::ExpireTickets.execute(commit: true)

    assert_equal 2, rows.size
    assert_equal AccessDocument::EXPIRED, due.reload.status
    assert_equal AccessDocument::EXPIRED, overdue.reload.status
    assert_equal AccessDocument::CLAIMED, not_yet.reload.status
    assert_equal @person.email, rows.find { |row| row.person.id == @person.id }.email
  end

  # --- post-event provision sweeps --------------------------------------------

  test "clean provisions consumes claimed provisions with the year" do
    claimed = provision_for(@person, status: Provision::CLAIMED)

    rows = TicketingMaintenance::CleanProvisions.execute(commit: true)

    assert_equal 1, rows.size
    assert_equal Provision::USED, claimed.reload.status
    assert_equal YEAR, claimed.consumed_year
  end

  test "clean provisions expires an available radio only when the person shows no activity" do
    no_show = provision_for(@person, type: Provision::EVENT_RADIO, status: Provision::AVAILABLE)
    worked = provision_for(@other, type: Provision::EVENT_RADIO, status: Provision::AVAILABLE)
    borrowed = provision_for(person(:retired_ranger), type: Provision::EVENT_RADIO,
                             status: Provision::AVAILABLE)
    rolls_over = provision_for(person(:echelon_ranger), type: Provision::WET_SPOT,
                               status: Provision::AVAILABLE)
    shift_for(@other)
    radio_checkout_for(person(:retired_ranger))

    rows = TicketingMaintenance::CleanProvisions.execute(commit: true)

    assert_equal 3, rows.size
    assert_equal Provision::EXPIRED, no_show.reload.status
    assert_equal "did not ranger and did not check out a radio",
                 rows.find { |row| row.person.id == @person.id }.detail
    assert_equal Provision::USED, worked.reload.status
    assert_equal "rangered that year", rows.find { |row| row.person.id == @other.id }.detail
    assert_equal Provision::USED, borrowed.reload.status
    assert_equal Provision::AVAILABLE, rolls_over.reload.status
  end

  test "clean provisions consumes or expires allocated provisions by bmid and status" do
    consumed_status = provision_for(@person, status: Provision::SUBMITTED, is_allocated: true)
    consumed_bmid = provision_for(@other, status: Provision::AVAILABLE, is_allocated: true)
    Bmid.create!(person: @other, year: YEAR, status: Bmid::SUBMITTED)
    # A legacy row from before the allocated-cannot-be-banked validation; the
    # sweep still has to settle it, so build it the way legacy data got in.
    wasted = Provision.new(person: person(:retired_ranger), type: Provision::WET_SPOT,
                           status: Provision::BANKED, is_allocated: true,
                           source_year: YEAR, expires_on: "#{YEAR}-09-15")
    wasted.save!(validate: false)

    rows = TicketingMaintenance::CleanProvisions.execute(commit: true)

    assert_equal 3, rows.size
    assert_equal Provision::USED, consumed_status.reload.status
    assert_equal Provision::USED, consumed_bmid.reload.status
    assert_equal Provision::EXPIRED, wasted.reload.status
    assert_equal YEAR, consumed_bmid.consumed_year
  end

  test "bank provisions banks earned available provisions and expires unclaimed radios" do
    shower = provision_for(@person, status: Provision::AVAILABLE)
    radio = provision_for(@other, type: Provision::EVENT_RADIO, status: Provision::AVAILABLE)
    allocated = provision_for(person(:retired_ranger), status: Provision::AVAILABLE, is_allocated: true)

    rows = TicketingMaintenance::BankProvisions.execute(commit: true)

    assert_equal 2, rows.size
    assert_equal Provision::BANKED, shower.reload.status
    assert_equal Provision::EXPIRED, radio.reload.status
    assert_equal Provision::AVAILABLE, allocated.reload.status
  end

  test "expire provisions expires earned live provisions dated today or earlier" do
    due = provision_for(@person, status: Provision::BANKED, expires_on: Date.current)
    not_yet = provision_for(@other, status: Provision::AVAILABLE, expires_on: Date.current + 1)
    allocated = provision_for(person(:retired_ranger), status: Provision::CLAIMED,
                              is_allocated: true, expires_on: Date.current)
    submitted = provision_for(person(:echelon_ranger), status: Provision::SUBMITTED,
                              expires_on: Date.current)

    rows = TicketingMaintenance::ExpireProvisions.execute(commit: true)

    assert_equal 1, rows.size
    assert_equal Provision::EXPIRED, due.reload.status
    assert_equal Provision::AVAILABLE, not_yet.reload.status
    assert_equal Provision::CLAIMED, allocated.reload.status
    assert_equal Provision::SUBMITTED, submitted.reload.status
  end

  # --- bump expiration ---------------------------------------------------------

  test "bump expiration adds a year to banked and qualified regular tickets only" do
    spt = ticket_for(@person, type: AccessDocument::SPT, status: AccessDocument::BANKED,
                     expiry_date: "#{YEAR + 1}-09-15")
    sap = ticket_for(@other, type: AccessDocument::SAP, status: AccessDocument::QUALIFIED,
                     delivery_method: AccessDocument::DELIVERY_EMAIL)
    claimed = ticket_for(person(:retired_ranger), type: AccessDocument::SPT,
                         status: AccessDocument::CLAIMED, expiry_date: "#{YEAR + 1}-09-15")

    rows = TicketingMaintenance::BumpExpiration.execute(commit: true, reason: "vendor delay")

    assert_equal 1, rows.size
    assert_equal Date.new(YEAR + 2, 9, 15), spt.reload.expiry_date
    assert_match "vendor delay", spt.comments
    assert_equal Date.new(YEAR, 9, 15), sap.reload.expiry_date
    assert_equal Date.new(YEAR + 1, 9, 15), claimed.reload.expiry_date
  end

  # --- un-submit ---------------------------------------------------------------

  test "unsubmit provisions returns only the chosen people's earned claimed provisions" do
    claimed = provision_for(@person, status: Provision::CLAIMED)
    submitted = provision_for(@person, type: Provision::EVENT_RADIO, status: Provision::SUBMITTED)
    allocated = provision_for(@person, type: Provision::MEALS, status: Provision::CLAIMED,
                              is_allocated: true)
    unpicked = provision_for(@other, status: Provision::CLAIMED)

    rows = TicketingMaintenance::UnsubmitProvisions.unsubmit([@person.id])

    assert_equal 2, rows.size
    assert_equal Provision::AVAILABLE, claimed.reload.status
    assert_equal Provision::AVAILABLE, submitted.reload.status
    assert_equal Provision::CLAIMED, allocated.reload.status
    assert_equal Provision::CLAIMED, unpicked.reload.status
    assert_match "un-submit maintenance function", claimed.comments
  end

  private

  # delivery_method is spelled out because the column is NOT NULL and the model
  # only fills it in on a status change.
  def ticket_for(holder, type: AccessDocument::SPT, status: AccessDocument::QUALIFIED,
                 delivery_method: AccessDocument::DELIVERY_NONE, expiry_date: "#{YEAR + 3}-09-15",
                 access_date: nil)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method:, expiry_date:, access_date:)
  end

  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE,
                    is_allocated: false, expires_on: "#{YEAR}-09-15")
    Provision.create!(person: holder, type:, status:, is_allocated:,
                      source_year: YEAR, expires_on:,
                      event_week_meals: type == Provision::MEALS)
  end

  def sign_up(holder, position: positions(:training_lead))
    slot = Slot.create!(position:, begins: Time.local(YEAR, 8, 28, 9, 0, 0),
                        ends: Time.local(YEAR, 8, 28, 13, 0, 0), max: 10, active: true)
    PersonSlot.create!(person: holder, slot:)
  end

  # The task matches slots on the well-known Training position id, which has no
  # fixture row.
  def training_sign_up(holder)
    position = Position.find_by(id: Position::TRAINING) ||
               Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING)
    slot = Slot.create!(position:, begins: Time.local(YEAR, 6, 20, 9, 0, 0),
                        ends: Time.local(YEAR, 6, 20, 17, 0, 0), max: 10, active: true)
    PersonSlot.create!(person: holder, slot:)
  end

  def shift_for(holder)
    on_duty = Time.local(YEAR, 8, 30, 10, 0, 0)
    Timesheet.create!(person: holder, position: positions(:ood_position),
                      on_duty:, off_duty: on_duty + 6.hours, additional_notes: "test shift")
  end

  def radio_checkout_for(holder)
    asset = Asset.create!(barcode: "RADIO-1", type: Asset::TYPE_RADIO, year: YEAR)
    PersonAsset.create!(person: holder, asset:, checked_out: Time.local(YEAR, 8, 29, 10, 0, 0))
  end

  def default_sap_date
    Setting.create!(name: Setting::TAS_DEFAULT_SAP_DATE, value: "#{YEAR}-08-10")
  end
end
