# frozen_string_literal: true

require "test_helper"

class PersonAssetTest < ActiveSupport::TestCase
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

  test "associations resolve and optional attachment and staff ids are allowed" do
    asset = create_asset
    attachment = create_attachment

    row = PersonAsset.create!(
      asset: asset,
      person: person(:active_ranger),
      attachment: attachment,
      check_out_person: person(:auditor_ranger),
      check_in_person: person(:echelon_ranger),
      checked_out: 2.hours.ago,
      checked_in: 1.hour.ago
    )

    optional_row = PersonAsset.create!(
      asset: asset,
      person: person(:ranger_with_custom_gender),
      attachment_id: "",
      checked_out: Current.time
    )

    assert_equal asset.id, row.asset.id
    assert_equal person(:active_ranger).id, row.person.id
    assert_equal attachment.id, row.attachment.id
    assert_equal person(:auditor_ranger).id, row.check_out_person.id
    assert_equal person(:echelon_ranger).id, row.check_in_person.id

    assert_nil optional_row.attachment_id
    assert_nil optional_row.attachment
    assert_nil optional_row.check_out_person
    assert_nil optional_row.check_in_person
  end

  test "duration uses current time for open checkouts and checked in time for closed rows" do
    asset = create_asset

    open_row = PersonAsset.create!(
      asset: asset,
      person: person(:active_ranger),
      checked_out: 2.hours.ago
    )
    closed_row = PersonAsset.create!(
      asset: asset,
      person: person(:ranger_with_custom_gender),
      checked_out: 4.hours.ago,
      checked_in: 90.minutes.ago
    )

    assert_equal 2.hours.to_i, open_row.duration
    assert_equal 150.minutes.to_i, closed_row.duration
  end

  test "find_for_query filters by person and year and eager loads relationships" do
    current_asset = create_asset(type: Asset::TYPE_RADIO)
    historical_asset = create_asset(type: Asset::TYPE_GEAR)
    attachment = create_attachment

    current_row = PersonAsset.create!(
      asset: current_asset,
      person: person(:active_ranger),
      attachment: attachment,
      check_out_person: person(:auditor_ranger),
      checked_out: Current.time
    )
    PersonAsset.create!(
      asset: historical_asset,
      person: person(:active_ranger),
      checked_out: Current.time.change(year: 2025)
    )

    rows = PersonAsset.findForQuery(person_id: person(:active_ranger).id, year: 2026).to_a

    assert_equal [current_row.id], rows.map(&:id)
    row = rows.first
    assert row.association(:asset).loaded?
    assert row.association(:attachment).loaded?
    assert row.association(:person).loaded?
    assert row.association(:check_out_person).loaded?
    assert row.association(:check_in_person).loaded?
  end

  test "retrieve_history returns ordered rows with loaded associations" do
    asset = create_asset
    attachment = create_attachment

    first_row = PersonAsset.create!(
      asset: asset,
      person: person(:active_ranger),
      attachment: attachment,
      check_out_person: person(:auditor_ranger),
      check_in_person: person(:echelon_ranger),
      checked_out: 3.days.ago,
      checked_in: 2.days.ago
    )
    second_row = PersonAsset.create!(
      asset: asset,
      person: person(:ranger_with_custom_gender),
      checked_out: 1.day.ago
    )

    rows = PersonAsset.retrieveHistory(asset.id).to_a

    assert_equal [first_row.id, second_row.id], rows.map(&:id)
    assert rows.first.association(:person).loaded?
    assert rows.first.association(:attachment).loaded?
    assert rows.first.association(:check_out_person).loaded?
    assert rows.first.association(:check_in_person).loaded?
  end

  test "find_checked_out_person returns the current checkout row and alias" do
    asset = create_asset
    checked_in_row = PersonAsset.create!(
      asset: asset,
      person: person(:ranger_with_custom_gender),
      checked_out: 2.days.ago,
      checked_in: 1.day.ago
    )
    open_row = PersonAsset.create!(
      asset: asset,
      person: person(:active_ranger),
      checked_out: Current.time
    )

    result = PersonAsset.find_checked_out_person(asset.id)
    alias_result = PersonAsset.findCheckedOutPerson(asset.id)

    assert_equal open_row.id, result.id
    assert_equal open_row.id, alias_result.id
    assert_not_equal checked_in_row.id, result.id
    assert result.association(:person).loaded?
  end

  test "retrieve_type_for_person_ids groups current open checkouts by person" do
    radio_asset = create_asset(type: Asset::TYPE_RADIO)
    other_radio_asset = create_asset(type: Asset::TYPE_RADIO)
    desktop_radio_asset = create_asset(type: Asset::TYPE_DESKTOP_RADIO)

    matching_row = PersonAsset.create!(
      asset: radio_asset,
      person: person(:active_ranger),
      checked_out: Current.time
    )
    PersonAsset.create!(
      asset: other_radio_asset,
      person: person(:ranger_with_custom_gender),
      checked_out: 1.day.ago,
      checked_in: Current.time
    )
    PersonAsset.create!(
      asset: desktop_radio_asset,
      person: person(:ranger_with_custom_gender),
      checked_out: Current.time
    )

    grouped = PersonAsset.retrieveTypeForPersonIds(Asset::TYPE_RADIO, [person(:active_ranger).id, person(:ranger_with_custom_gender).id])

    assert_equal [person(:active_ranger).id], grouped.keys
    assert_equal [matching_row.id], grouped.fetch(person(:active_ranger).id).map(&:id)
    assert grouped.fetch(person(:active_ranger).id).first.association(:asset).loaded?
  end

  test "load_relationships preloads the configured associations and alias" do
    asset = create_asset
    attachment = create_attachment
    row = PersonAsset.create!(
      asset: asset,
      person: person(:active_ranger),
      attachment: attachment,
      check_out_person: person(:auditor_ranger),
      check_in_person: person(:echelon_ranger),
      checked_out: 2.hours.ago,
      checked_in: 1.hour.ago
    )

    reloaded_row = PersonAsset.find(row.id)
    refute reloaded_row.association(:asset).loaded?
    refute reloaded_row.association(:attachment).loaded?
    refute reloaded_row.association(:person).loaded?

    reloaded_row.loadRelationships

    assert reloaded_row.association(:asset).loaded?
    assert reloaded_row.association(:attachment).loaded?
    assert reloaded_row.association(:person).loaded?
    assert reloaded_row.association(:check_out_person).loaded?
    assert reloaded_row.association(:check_in_person).loaded?
  end

test "audit rows are named after the person_asset table" do
  row = PersonAsset.create!(asset: create_asset, person: person(:active_ranger), checked_out: Current.time)
  row.update!(checked_in: Current.time)
  row.destroy!

  events = ActionLog.where(target_person_id: person(:active_ranger).id).order(:id).pluck(:event)
  assert_equal %w[person-asset-create person-asset-update person-asset-delete], events
end

  private

  def create_asset(**attributes)
    Asset.create!(
      {
        barcode: "ASSET-#{next_sequence}",
        type: Asset::TYPE_RADIO,
        year: Current.year
      }.merge(attributes)
    )
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

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
end
