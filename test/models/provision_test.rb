# frozen_string_literal: true

require "test_helper"

# The rules of the two event-only radio types, radio_shift and radio_group:
# never banked, never allocated, expiring with the present event, and a
# radio_group always naming a radio asset group.
class ProvisionTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Current.reset
    @person = person(:active_ranger)
    @radios = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Command Operations")
    @gear = AssetGroup.create!(type: Asset::TYPE_GEAR, title: "Command Operations")
  end

  teardown do
    Current.reset
    travel_back
  end

  test "a shift radio defaults to one radio and expires with the present event" do
    shift = build(type: Provision::RADIO_SHIFT, expires_on: "2029")

    assert shift.save
    assert_equal 1, shift.item_count
    assert_equal Date.new(2026, 9, 15), shift.expires_on
    assert_predicate shift, :event_only?
    assert_not shift.bankable?
  end

  test "a provision changed into a radio type, or given a later year, expires with the present event" do
    radio = create(type: Provision::EVENT_RADIO, expires_on: "2029")
    assert_equal 2029, radio.expires_on.year

    radio.update!(type: Provision::RADIO_SHIFT)
    assert_equal 2026, radio.expires_on.year

    radio.update!(expires_on: "2028")
    assert_equal 2026, radio.expires_on.year

    # A later save that touches neither leaves a past year's record as it was.
    travel_to Time.zone.local(2027, 4, 16) do
      radio.update!(additional_comments: "Looked up in 2027.")
      assert_equal 2026, radio.expires_on.year
    end
  end

  test "an event-only radio type cannot be banked or allocated" do
    [Provision::RADIO_SHIFT, Provision::RADIO_GROUP].each do |type|
      banked = build(type:, asset_group: @radios, status: Provision::BANKED)
      assert_not banked.valid?
      assert_match "cannot be banked", banked.errors[:status].first

      allocated = build(type:, asset_group: @radios, is_allocated: true)
      assert_not allocated.valid?
      assert_includes allocated.errors[:is_allocated], Provision::NOT_ALLOCATABLE
    end
  end

  test "a radio group provision needs a group, and a radio one" do
    assert_includes invalid(type: Provision::RADIO_GROUP).errors[:asset_group_id], Provision::GROUP_REQUIRED
    assert_includes invalid(type: Provision::RADIO_GROUP, asset_group: @gear).errors[:asset_group_id],
                    Provision::GROUP_REQUIRED

    granted = build(type: Provision::RADIO_GROUP, asset_group: @radios)
    assert granted.save
    assert_equal "Specialized Radio: Command Operations", granted.type_label
  end

  test "an inactive radio group can still be granted from" do
    @radios.update!(active: false)

    assert_predicate build(type: Provision::RADIO_GROUP, asset_group: @radios), :valid?
  end

  test "the group is dropped from every other type" do
    radio = build(type: Provision::EVENT_RADIO, asset_group: @radios)

    assert radio.save
    assert_nil radio.asset_group_id
  end

  test "bankable and event_only split every provision between them" do
    earned = create(type: Provision::WET_SPOT)
    allocated = create(type: Provision::WET_SPOT, is_allocated: true)
    shift = create(type: Provision::RADIO_SHIFT)
    group = create(type: Provision::RADIO_GROUP, asset_group: @radios)
    mine = Provision.where(id: [earned, allocated, shift, group])

    assert_equal [earned], mine.bankable.to_a
    assert_equal [allocated, shift, group].map(&:id).sort, mine.event_only.pluck(:id).sort
    assert_not_includes Provision.retrieve_earned(@person.id), shift
    assert_includes Provision.retrieve_earned(@person.id), earned

    # What the member's pages, the badge pages and the BMID export read.
    usable = Provision.retrieve_usable_for_person_ids([@person.id])
    assert_includes usable, allocated
    assert_empty usable & [shift, group]
  end

  private

  test "build_package takes the highest shift radio count and each radio group once" do
    create(type: Provision::RADIO_SHIFT, item_count: 2)
    create(type: Provision::RADIO_SHIFT)
    2.times { create(type: Provision::RADIO_GROUP, asset_group: @radios) }
    create(type: Provision::RADIO_SHIFT, item_count: 5, status: Provision::CANCELLED)
    # Left over from a past event, not yet ended by Clean Provisions.
    create(type: Provision::RADIO_SHIFT, item_count: 4).update_columns(expires_on: Date.new(2025, 9, 15))

    package = Provision.build_package(Provision.radio_grants.where(person_id: @person.id))

    assert_equal 2, package.shift_radios
    assert_equal [@radios], package.radio_groups
    assert_equal 0, package.event_radios
    assert_not package.have_allocated
  end

  def build(**attributes)
    Provision.new(person: @person, status: Provision::AVAILABLE, source_year: 2026, expires_on: "2026", **attributes)
  end

  def create(**attributes) = build(**attributes).tap(&:save!)

  def invalid(**attributes) = build(**attributes).tap(&:valid?)
end
