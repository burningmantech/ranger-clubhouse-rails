# frozen_string_literal: true

require "test_helper"

# The rules behind the Radio Checkout Report, asserted against the report class
# rather than the page it renders: which checkouts qualify in each view, and who
# counts as entitled to keep a radio.
#
# The controller test can only read these verdicts off section headings, which
# are copy and get reworded; the boundary cases below are the contract.
class RadioCheckoutReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  HOUR = 3600

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Current.reset

    PersonAsset.delete_all
    Asset.delete_all
    # The fixtures hand active_ranger an available event-radio provision, which
    # would silently make every holder here eligible.
    Provision.delete_all

    @holder = person(:inactive_ranger)
    @clerk = person(:auditor_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  test "no year reports nothing" do
    check_out(radio, @holder, hours_ago: 20)

    assert_empty RadioCheckoutReport.execute(year: nil)
  end

  test "the limit is exclusive at exactly fourteen hours" do
    check_out(radio(barcode: "AT-LIMIT"), @holder, hours_ago: RadioCheckoutReport::HOUR_LIMIT)
    check_out(radio(barcode: "OVER"), @holder, hours_ago: RadioCheckoutReport::HOUR_LIMIT + 0.01)

    assert_equal ["OVER"], barcodes(RadioCheckoutReport.execute(year: Current.year))
  end

  test "the chase list carries only radios still out" do
    check_out(radio(barcode: "STILL-OUT"), @holder, hours_ago: 20)
    check_out(radio(barcode: "BACK-LATE"), @holder, hours_ago: 30, returned_hours_ago: 2)

    assert_equal ["STILL-OUT"], barcodes(RadioCheckoutReport.execute(year: Current.year))
  end

  test "the event summary adds late returns and every radio still out, however briefly" do
    check_out(radio(barcode: "BACK-LATE"), @holder, hours_ago: 30, returned_hours_ago: 2)
    check_out(radio(barcode: "BRIEF"), @holder, hours_ago: 2)
    # Returned inside the limit: accounted for, so it is no one's problem.
    check_out(radio(barcode: "PROMPT"), @holder, hours_ago: 4, returned_hours_ago: 1)

    rows = RadioCheckoutReport.execute(year: Current.year, event_summary: true)

    assert_equal %w[BACK-LATE BRIEF], barcodes(rows).sort
  end

  test "a checkout whose timestamps run backwards is dropped, not reported as a long hold" do
    # abs() would turn this into a 72-hour overrun at the top of the list.
    reversed = check_out(radio(barcode: "REVERSED"), @holder, hours_ago: 2)
    reversed.update!(checked_in: reversed.checked_out - (72 * HOUR))

    assert_empty RadioCheckoutReport.execute(year: Current.year, event_summary: true)
  end

  test "only handheld radios are reported" do
    check_out(radio(barcode: "RADIO"), @holder, hours_ago: 20)
    check_out(radio(barcode: "GEAR", type: Asset::TYPE_GEAR), @holder, hours_ago: 20)
    check_out(radio(barcode: "DESK", type: Asset::TYPE_DESKTOP_RADIO), @holder, hours_ago: 20)

    assert_equal ["RADIO"], barcodes(RadioCheckoutReport.execute(year: Current.year))
  end

  test "the report is scoped to the year the radio went out" do
    check_out(radio(barcode: "NOW"), @holder, hours_ago: 20)
    check_out(radio(barcode: "THEN", year: Current.year - 1), @holder, hours_ago: 20,
              at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))

    assert_equal ["NOW"], barcodes(RadioCheckoutReport.execute(year: Current.year))
    assert_equal ["THEN"], barcodes(RadioCheckoutReport.execute(year: Current.year - 1))
  end

  test "rows come back longest-held first" do
    check_out(radio(barcode: "SHORTER"), @holder, hours_ago: 20)
    check_out(radio(barcode: "LONGER"), @holder, hours_ago: 50)

    assert_equal %w[LONGER SHORTER], barcodes(RadioCheckoutReport.execute(year: Current.year))
  end

  test "a holder with no event radio provision is not eligible" do
    check_out(radio, @holder, hours_ago: 20)

    assert_equal [false], RadioCheckoutReport.execute(year: Current.year).map(&:eligible)
  end

  test "each usable provision status makes the current year's holder eligible" do
    Provision::CAN_USE_STATUSES.each do |status|
      PersonAsset.delete_all
      Provision.delete_all
      check_out(radio, @holder, hours_ago: 20)
      grant_event_radio(status:)

      assert_equal [true], RadioCheckoutReport.execute(year: Current.year).map(&:eligible),
                   "expected #{status} to count for the current year"
    end
  end

  test "a banked provision does not count, matching upstream" do
    # Deliberate divergence from PersonEventInfo#radio_max -- see the report's
    # own note. Pinned so a change to it is a decision, not a drift.
    check_out(radio, @holder, hours_ago: 20)
    grant_event_radio(status: Provision::BANKED)

    assert_equal [false], RadioCheckoutReport.execute(year: Current.year).map(&:eligible)
  end

  test "an unconsumed provision says nothing about a past year" do
    check_out(radio(year: Current.year - 1), @holder, hours_ago: 20,
              at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))
    grant_event_radio(status: Provision::AVAILABLE, source_year: Current.year - 1)

    assert_equal [false], RadioCheckoutReport.execute(year: Current.year - 1).map(&:eligible)
  end

  test "a provision consumed in the reported year counts in that past year" do
    check_out(radio(year: Current.year - 1), @holder, hours_ago: 20,
              at: Time.zone.local(Current.year - 1, 8, 30, 12, 0, 0))
    grant_event_radio(status: Provision::USED, source_year: Current.year - 1,
                      consumed_year: Current.year - 1)

    assert_equal [true], RadioCheckoutReport.execute(year: Current.year - 1).map(&:eligible)
  end

  test "a provision consumed in a different year does not count" do
    check_out(radio, @holder, hours_ago: 20)
    grant_event_radio(status: Provision::USED, consumed_year: Current.year - 1)

    assert_equal [false], RadioCheckoutReport.execute(year: Current.year).map(&:eligible)
  end

  private

  def barcodes(rows)
    rows.map { |row| row.asset.barcode }
  end

  def radio(**attributes)
    Asset.create!(
      { barcode: "RADIO-#{next_sequence}", type: Asset::TYPE_RADIO, perm_assign: false,
        year: Current.year }.merge(attributes)
    )
  end

  def check_out(asset, holder, hours_ago:, returned_hours_ago: nil, at: Current.time)
    PersonAsset.create!(asset:,
                        person_id: holder.id,
                        checked_out: at - (hours_ago * HOUR),
                        checked_in: (at - (returned_hours_ago * HOUR) if returned_hours_ago),
                        check_out_person_id: @clerk.id)
  end

  def grant_event_radio(status:, source_year: Current.year, consumed_year: nil)
    Provision.create!(person_id: @holder.id,
                      type: Provision::EVENT_RADIO,
                      status:,
                      consumed_year:,
                      is_allocated: false,
                      item_count: 1,
                      source_year:,
                      expires_on: "#{source_year}-09-15")
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
