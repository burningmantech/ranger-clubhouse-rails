# frozen_string_literal: true

require "test_helper"

class Person::ProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @target = person(:active_ranger)
    @ticketing_admin = person(:echelon_ranger)

    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Docs")
    grant_role(@ticketing_admin, Role::EDIT_ACCESS_DOCS)

    Current.person = @ticketing_admin
    sign_in_as(@ticketing_admin)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "new preselects the type from the hub buttons" do
    get new_person_provision_path(@target, type: Provision::EVENT_RADIO)

    assert_response :success
    assert_select "body", text: /Add Provision/
  end

  test "create defaults an event radio to one radio" do
    assert_difference "Provision.count", 1 do
      post person_provisions_path(@target), params: {
        provision: {
          type: Provision::EVENT_RADIO,
          status: Provision::AVAILABLE,
          source_year: 2026,
          expires_on: "2029"
        }
      }
    end

    assert_redirected_to person_tickets_provisions_path(@target)

    provision = Provision.order(:id).last
    assert_equal @target.id, provision.person_id
    assert_equal 1, provision.item_count
    assert_equal Date.new(2029, 9, 15), provision.expires_on
  end

  test "the form offers the radio groups, active before inactive" do
    AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Command Operations")
    AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Old Pool", active: false)
    AssetGroup.create!(type: Asset::TYPE_GEAR, title: "Tool Crib")

    get new_person_provision_path(@target, type: Provision::RADIO_GROUP)

    assert_response :success
    # The year the model will hold it to, not the three years an earned one keeps.
    assert_select "select[name='provision[expires_on]'] option[selected]", text: "2026"
    assert_select "select[name='provision[type]'] option[selected][value=?]", Provision::RADIO_GROUP
    # A radio group provision is counted, so the form starts it at one radio.
    assert_select "input[name='provision[item_count]'][value='1']"
    assert_select "select[name='provision[asset_group_id]']" do
      assert_select "optgroup[label='Active'] option", text: "Command Operations"
      assert_select "optgroup[label='Inactive'] option", text: "Old Pool"
      assert_select "option", text: "Tool Crib", count: 0
    end
  end

  test "create saves a radio group provision with its group, expiring this event" do
    group = AssetGroup.create!(type: Asset::TYPE_RADIO, title: "Command Operations")

    assert_difference "Provision.count", 1 do
      post person_provisions_path(@target), params: {
        provision: {
          type: Provision::RADIO_GROUP,
          status: Provision::AVAILABLE,
          source_year: 2026,
          expires_on: "2029",
          asset_group_id: group.id
        }
      }
    end

    assert_redirected_to person_tickets_provisions_path(@target)
    granted = Provision.order(:id).last
    assert_equal group.id, granted.asset_group_id
    assert_equal 2026, granted.expires_on.year

    get person_tickets_provisions_path(@target)
    assert_select "td", text: /Specialized Radio: Command Operations/
  end

  test "create rejects a radio group provision without a group, and a banked shift radio" do
    assert_no_difference "Provision.count" do
      post person_provisions_path(@target), params: {
        provision: { type: Provision::RADIO_GROUP, status: Provision::AVAILABLE, source_year: 2026,
                     expires_on: "2026" }
      }
      assert_response :unprocessable_entity
      assert_match Provision::GROUP_REQUIRED, response.body

      post person_provisions_path(@target), params: {
        provision: { type: Provision::RADIO_SHIFT, status: Provision::BANKED, source_year: 2026,
                     expires_on: "2026" }
      }
      assert_response :unprocessable_entity
      assert_match "cannot be banked", response.body
    end
  end

  test "create rejects a meal provision without any meal period" do
    assert_no_difference "Provision.count" do
      post person_provisions_path(@target), params: {
        provision: {
          type: Provision::MEALS,
          status: Provision::AVAILABLE,
          source_year: 2026,
          expires_on: "2029"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "at least one meal period", response.body
  end

  test "update rejects banking an allocated provision" do
    provision = provision(:ar_meals)

    patch person_provision_path(@target, provision), params: {
      provision: { is_allocated: "1", status: Provision::BANKED }
    }

    assert_response :unprocessable_entity
    assert_match "cannot be banked", response.body
    refute provision.reload.is_allocated
  end

  test "update saves changes and appends a timestamped comment" do
    provision = provision(:ar_meals)

    patch person_provision_path(@target, provision), params: {
      provision: { status: Provision::CLAIMED, additional_comments: "Issued at HQ." }
    }

    assert_redirected_to person_tickets_provisions_path(@target)

    provision.reload
    assert_equal Provision::CLAIMED, provision.status
    assert_includes provision.comments, "Issued at HQ."
    assert_includes provision.comments, @ticketing_admin.callsign
  end

  test "destroy removes the provision" do
    assert_difference "Provision.count", -1 do
      delete person_provision_path(@target, provision(:ar_shower))
    end

    assert_redirected_to person_tickets_provisions_path(@target)
  end
end
