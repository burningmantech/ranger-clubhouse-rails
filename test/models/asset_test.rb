# frozen_string_literal: true

require "test_helper"

class AssetTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 14, 12, 0, 0)
    Current.reset
    Current.person = person(:auditor_ranger)

    ActionLog.delete_all
    PersonAsset.delete_all
    Asset.delete_all
    AssetAttachment.delete_all
  end

  teardown do
    Current.reset
    travel_back
  end

  test "barcode uniqueness is scoped to year" do
    create_asset(barcode: "A-100", year: 2026)

    duplicate = build_asset(barcode: "A-100", year: 2026)
    other_year = build_asset(barcode: "A-100", year: 2025)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:barcode], "Barcode has already been taken."
    assert other_year.valid?
  end

  test "optional blank fields normalize to nil" do
    asset = create_asset(
      group_name: "",
      description: "",
      entity_assignment: "",
      order_number: "",
      expires_on: ""
    )

    assert_nil asset.group_name
    assert_nil asset.description
    assert_nil asset.entity_assignment
    assert_nil asset.order_number
    assert_nil asset.expires_on
  end

  test "has_expired treats today as expired" do
    expiring_today = create_asset(expires_on: Current.today)
    future_asset = create_asset(expires_on: Current.today + 1.day)
    no_expiry_asset = create_asset(expires_on: nil)

    assert expiring_today.has_expired?
    assert_not future_asset.has_expired?
    assert_not no_expiry_asset.has_expired?
  end

  test "find_by_barcode_year finds the matching row and compatibility alias" do
    asset = create_asset(barcode: "BAR-42", year: 2026)
    create_asset(barcode: "BAR-42", year: 2025)

    assert_equal asset.id, Asset.find_by_barcode_year("BAR-42", 2026)&.id
    assert_equal asset.id, Asset.findByBarcodeYear("BAR-42", 2026)&.id
    assert_nil Asset.find_by_barcode_year("missing", 2026)
  end

  test "find_for_query filters checked out assets and eager loads current checkout" do
    attachment = create_attachment(description: "Speaker mic")
    matching_asset = create_asset(barcode: "RAD-OPEN", type: Asset::TYPE_RADIO, order_number: "PO-1")
    create_checkout(
      asset: matching_asset,
      person: person(:active_ranger),
      check_out_person: person(:auditor_ranger),
      attachment: attachment
    )

    create_asset(barcode: "RAD-CLOSED", type: Asset::TYPE_RADIO, order_number: "PO-1")
    create_asset(barcode: "GEAR-OPEN", type: Asset::TYPE_GEAR, order_number: "PO-1")

    rows = Asset.findForQuery(type: Asset::TYPE_RADIO, checked_out: true, order_number: "PO-1").to_a

    assert_equal [matching_asset.id], rows.map(&:id)

    row = rows.first
    assert row.association(:checked_out).loaded?
    assert_equal person(:active_ranger).id, row.checked_out.person_id
    assert row.checked_out.association(:person).loaded?
    assert row.checked_out.association(:check_out_person).loaded?
    assert row.checked_out.association(:attachment).loaded?
  end

  test "find_for_query loads history when requested" do
    attachment = create_attachment(description: "Battery")
    asset = create_asset(barcode: "RAD-HIST")
    first_checkout = create_checkout(
      asset: asset,
      person: person(:active_ranger),
      check_out_person: person(:auditor_ranger),
      checked_out: 3.days.ago,
      checked_in: 2.days.ago,
      check_in_person: person(:echelon_ranger),
      attachment: attachment
    )
    second_checkout = create_checkout(
      asset: asset,
      person: person(:ranger_with_custom_gender),
      check_out_person: person(:auditor_ranger),
      checked_out: 1.day.ago
    )

    rows = Asset.find_for_query(barcode: asset.barcode, include_history: true).to_a

    assert_equal [asset.id], rows.map(&:id)

    row = rows.first
    assert row.association(:asset_history).loaded?
    assert_equal [first_checkout.id, second_checkout.id], row.asset_history.map(&:id)
    assert row.asset_history.first.association(:person).loaded?
    assert row.asset_history.first.association(:check_out_person).loaded?
    assert row.asset_history.first.association(:check_in_person).loaded?
    assert row.asset_history.first.association(:attachment).loaded?
  end

  test "find_for_query applies blank sentinel and expiration filters" do
    blank_asset = create_asset(
      barcode: "BLANK-100",
      description: nil,
      group_name: nil,
      entity_assignment: nil,
      order_number: nil,
      expires_on: nil
    )
    expired_asset = create_asset(
      barcode: "EXP-100",
      description: "Portable",
      group_name: "Ops",
      entity_assignment: "Alpha",
      order_number: "PO-1",
      expires_on: Current.today
    )
    future_asset = create_asset(
      barcode: "FUTURE-100",
      description: "Portable",
      group_name: "Ops",
      entity_assignment: "Bravo",
      order_number: "PO-2",
      expires_on: Current.today + 1.day
    )

    assert_equal [blank_asset.id],
                 Asset.find_for_query(description: "Blank",
                                      group_name: "Blank",
                                      entity_assignment: "Blank",
                                      order_number: "Blank").map(&:id)
    assert_equal [expired_asset.id], Asset.find_for_query(expire: "expired").map(&:id)
    assert_equal [blank_asset.id, future_asset.id].sort, Asset.find_for_query(expire: "not-expired").map(&:id).sort
    assert_equal [future_asset.id], Asset.find_for_query(expire: (Current.today + 1.day).iso8601).map(&:id)
  end

  test "find_for_query sorts barcodes naturally" do
    create_asset(barcode: "SAND100")
    create_asset(barcode: "SAND2")
    create_asset(barcode: "SAND12")

    assert_equal %w[SAND2 SAND12 SAND100], Asset.find_for_query.map(&:barcode)
  end

  test "destroy removes checkout history via delete_all" do
    asset = create_asset
    create_checkout(asset: asset, person: person(:active_ranger))
    create_checkout(asset: asset, person: person(:ranger_with_custom_gender), checked_out: 1.day.ago, checked_in: 12.hours.ago)

    assert_difference("PersonAsset.count", -2) do
      asset.destroy!
    end
  end

  private

  def build_asset(**attributes)
    Asset.new(
      {
        barcode: next_barcode,
        type: Asset::TYPE_RADIO,
        year: Current.year
      }.merge(attributes)
    )
  end

  def create_asset(**attributes)
    build_asset(**attributes).tap(&:save!)
  end

  def create_attachment(**attributes)
    sequence = next_sequence

    AssetAttachment.create!(
      {
        id: sequence,
        parent_type: AssetAttachment::RADIO,
        description: "Attachment #{sequence}"
      }.merge(attributes)
    )
  end

  def create_checkout(asset:, person:, **attributes)
    PersonAsset.create!(
      {
        asset: asset,
        person: person,
        checked_out: attributes.delete(:checked_out) || Current.time
      }.merge(attributes)
    )
  end

  def next_barcode
    "ASSET-#{next_sequence}"
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
