# frozen_string_literal: true

require "test_helper"

class Person::AssetsControllerTest < ActionDispatch::IntegrationTest
  # rubocop:disable Metrics/ClassLength
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    ActionLog.delete_all
    PersonAsset.delete_all
    Asset.delete_all
    AssetAttachment.delete_all

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @event_manager = person(:echelon_ranger)
    @trainer = person(:ranger_with_custom_gender)
    @past_year = Current.year - 1

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@trainer, Role::TRAINER)

    Current.person = @admin
    PersonEvent.where(person_id: @target.id).delete_all
    PersonEvent.create!(person_id: @target.id, year: Current.year, asset_authorized: true)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  test "unauthorized person role is redirected from the asset page" do
    sign_in_as(@trainer)

    get person_assets_path(@target)

    assert_redirected_to person_path(@target)
    assert_equal "You are not authorized to manage assets.", flash[:error]
  end

  test "admin current-year page shows asset authorization form" do
    sign_in_as(@admin)
    disclaimer = "Recording a signature on someone else's behalf may expose the organization to legal liability"

    get person_assets_path(@target, year: Current.year)

    assert_response :success
    assert_select "body", text: /Asset authorization/i
    assert_select "body", text: /#{Regexp.escape(disclaimer)}/
    assert_select "input[name='person_event[asset_authorized]'][type='checkbox']", count: 1
    assert_select "input[type='submit'][value='Save']", count: 1
  end

  test "event management current-year page does not show asset authorization form" do
    sign_in_as(@event_manager)

    get person_assets_path(@target, year: Current.year)

    assert_response :success
    assert_select "body", text: /Asset authorization/i, count: 0
    assert_select "input[name='person_event[asset_authorized]'][type='checkbox']", count: 0
    assert_select "input[type='submit'][value='Save asset authorization']", count: 0
  end

  test "admin past-year page does not show asset authorization form" do
    sign_in_as(@admin)

    get person_assets_path(@target, year: @past_year)

    assert_response :success
    assert_select "body", text: /Asset authorization/i, count: 0
    assert_select "input[name='person_event[asset_authorized]'][type='checkbox']", count: 0
    assert_select "input[type='submit'][value='Save asset authorization']", count: 0
  end

  test "event management can check out and check in an asset" do
    asset = create_asset(barcode: "RAD-100")
    attachment = create_attachment(description: "Speaker mic")

    sign_in_as(@event_manager)

    assert_difference("PersonAsset.count", 1) do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode,
          attachment_id: attachment.id
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)

    checkout = PersonAsset.order(:id).last
    assert_equal @target.id, checkout.person_id
    assert_equal asset.id, checkout.asset_id
    assert_equal attachment.id, checkout.attachment_id
    assert_equal @event_manager.id, checkout.check_out_person_id

    patch check_in_person_asset_path(@target, checkout, year: Current.year)

    assert_redirected_to person_assets_path(@target, year: Current.year)

    checkout.reload
    assert_not_nil checkout.checked_in
    assert_equal @event_manager.id, checkout.check_in_person_id
  end

  test "non admin cannot delete an asset checkout row" do
    checkout = create_checkout(asset: create_asset(barcode: "DEL-100"), person: @target)

    sign_in_as(@event_manager)

    assert_no_difference("PersonAsset.count") do
      delete person_asset_path(@target, checkout, year: Current.year)
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Admin permission required to delete asset records.", flash[:error]
    assert PersonAsset.exists?(checkout.id)
  end

  test "admin can set asset authorization for the current year" do
    PersonEvent.find_for_person_year(@target.id, Current.year).update!(asset_authorized: false)
    sign_in_as(@admin)

    patch authorization_person_assets_path(@target, year: Current.year), params: {
      person_event: {
        asset_authorized: "1"
      }
    }

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert PersonEvent.find_for_person_year(@target.id, Current.year).asset_authorized
  end

  test "admin can clear asset authorization for the current year" do
    sign_in_as(@admin)

    patch authorization_person_assets_path(@target, year: Current.year), params: {
      person_event: {
        asset_authorized: "0"
      }
    }

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_not PersonEvent.find_for_person_year(@target.id, Current.year).asset_authorized
  end

  test "admin current-year authorization patch creates a person event when missing" do
    PersonEvent.where(person_id: @target.id, year: Current.year).delete_all
    sign_in_as(@admin)

    assert_difference(
      -> { PersonEvent.where(person_id: @target.id, year: Current.year).count },
      1
    ) do
      patch authorization_person_assets_path(@target, year: Current.year), params: {
        person_event: {
          asset_authorized: "1"
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert PersonEvent.find_for_person_year(@target.id, Current.year).asset_authorized
  end

  test "non admin cannot update asset authorization" do
    sign_in_as(@event_manager)

    patch authorization_person_assets_path(@target, year: Current.year), params: {
      person_event: {
        asset_authorized: "0"
      }
    }

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Admin permission required to update asset authorization.", flash[:error]
    assert PersonEvent.find_for_person_year(@target.id, Current.year).asset_authorized
  end

  test "past-year authorization update is rejected" do
    past_event = PersonEvent.create!(
      person_id: @target.id,
      year: @past_year,
      asset_authorized: false
    )
    sign_in_as(@admin)

    patch authorization_person_assets_path(@target, year: @past_year), params: {
      person_event: {
        asset_authorized: "1"
      }
    }

    assert_redirected_to person_assets_path(@target, year: @past_year)
    assert_equal "Asset authorization may only be changed for the current year.", flash[:error]
    assert_not past_event.reload.asset_authorized
  end

  test "expired asset renders the force interstitial and can then be forced" do
    asset = create_asset(barcode: "EXP-100", expires_on: Current.today)

    sign_in_as(@event_manager)

    assert_no_difference("PersonAsset.count") do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode
        }
      }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/target="modal"/, response.body)
    assert_match "Force Checkout Required", response.body
    assert_match "EXP-100", response.body
    assert_match "person_asset[force]", response.body

    assert_difference("PersonAsset.count", 1) do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode,
          force: "1"
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert PersonAsset.order(:id).last.check_out_forced?
  end

  test "entity-assigned asset cannot be checked out" do
    asset = create_asset(barcode: "ENT-100", entity_assignment: "Gerlach Patrol")

    sign_in_as(@event_manager)

    assert_no_difference("PersonAsset.count") do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Asset ENT-100 is assigned to Gerlach Patrol and cannot be checked out.",
                 flash[:error]
  end

  test "force does not override an entity assignment" do
    asset = create_asset(barcode: "ENT-200", entity_assignment: "Gerlach Patrol",
                         expires_on: Current.today)

    sign_in_as(@event_manager)

    assert_no_difference("PersonAsset.count") do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode,
          force: "1"
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Asset ENT-200 is assigned to Gerlach Patrol and cannot be checked out.",
                 flash[:error]
  end

  test "duplicate checkout is rejected" do
    asset = create_asset(barcode: "DUP-100")
    create_checkout(asset: asset, person: person(:ranger_with_custom_gender))

    sign_in_as(@event_manager)

    assert_no_difference("PersonAsset.count") do
      post person_assets_path(@target, year: Current.year), params: {
        person_asset: {
          barcode: asset.barcode
        }
      }
    end

    assert_redirected_to person_assets_path(@target, year: Current.year)
    holder = person(:ranger_with_custom_gender).callsign
    assert_equal "Asset DUP-100 is still checked out by #{holder} " \
                 "(checked out Thu Apr 16 @ 12:00).",
                 flash[:error]

    follow_redirect!

    assert_response :success
    assert_select "body", text: /still checked out by/i
  end

  test "asset cannot be checked in twice" do
    checkout = create_checkout(asset: create_asset(barcode: "TWI-100"), person: @target,
                               checked_in: Current.time)

    sign_in_as(@event_manager)

    patch check_in_person_asset_path(@target, checkout, year: Current.year)

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Asset is already checked in.", flash[:error]
  end

  test "change attachment renders the shared modal and updates the attachment" do
    attachment = create_attachment(description: "Speaker mic")
    checkout = create_checkout(asset: create_asset(barcode: "ATT-100"), person: @target)

    sign_in_as(@event_manager)

    get change_attachment_person_asset_path(@target, checkout, year: Current.year)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/target="modal"/, response.body)
    assert_match "Change Attachment", response.body

    patch update_attachment_person_asset_path(@target, checkout, year: Current.year), params: {
      person_asset: {
        attachment_id: attachment.id
      }
    }

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal attachment.id, checkout.reload.attachment_id
  end

  test "a non-hash person_asset param is refused rather than clearing the attachment" do
    attachment = create_attachment(description: "Speaker mic")
    checkout = create_checkout(asset: create_asset(barcode: "ATT-300"), person: @target,
                               attachment_id: attachment.id)

    sign_in_as(@event_manager)

    patch update_attachment_person_asset_path(@target, checkout, year: Current.year),
          params: { person_asset: "x" }

    assert_response :bad_request
    assert_equal attachment.id, checkout.reload.attachment_id
  end

  test "attachment cannot be changed after check in" do
    attachment = create_attachment(description: "Speaker mic")
    checkout = create_checkout(asset: create_asset(barcode: "ATT-200"), person: @target,
                               checked_in: Current.time)

    sign_in_as(@event_manager)

    patch update_attachment_person_asset_path(@target, checkout, year: Current.year), params: {
      person_asset: {
        attachment_id: attachment.id
      }
    }

    assert_redirected_to person_assets_path(@target, year: Current.year)
    assert_equal "Cannot change attachment after check in.", flash[:error]
    assert_nil checkout.reload.attachment_id
  end

  test "table shows the event-vs-shift assignment badge" do
    create_checkout(asset: create_asset(barcode: "RAD-SHIFT"), person: @target)
    create_checkout(asset: create_asset(barcode: "RAD-EVENT", perm_assign: true), person: @target)
    create_checkout(asset: create_asset(barcode: "GEAR-TEMP", type: Asset::TYPE_GEAR), person: @target)
    create_checkout(asset: create_asset(barcode: "GEAR-PERM", type: Asset::TYPE_GEAR, perm_assign: true),
                    person: @target)

    sign_in_as(@event_manager)

    get person_assets_path(@target, year: Current.year)

    assert_response :success
    assert_select "td[data-label=Assign]", text: /Shift/, count: 1
    assert_select "td[data-label=Assign]", text: /Event/, count: 1
    assert_select "td[data-label=Assign]", text: /Temporary/, count: 1
    assert_select "td[data-label=Assign]", text: /Permanent/, count: 1
  end

  test "current-year page renders the shared checkout form with the barcode id" do
    sign_in_as(@event_manager)

    get person_assets_path(@target, year: Current.year)

    assert_response :success
    assert_select "input#checkout-barcode[name='person_asset[barcode]'][maxlength='25']", count: 1
    assert_select "label[for=checkout-barcode]", count: 1
  end

  test "year filter shows only that year and exposes historical years in the selector" do
    create_checkout(asset: create_asset(barcode: "CUR-100"), person: @target,
                    checked_out: Current.time)
    create_checkout(
      asset: create_asset(barcode: "HIST-100", year: @past_year),
      person: @target,
      checked_out: Current.time.change(year: @past_year),
      checked_in: Current.time.change(year: @past_year) + 2.hours
    )

    sign_in_as(@admin)

    get person_assets_path(@target, year: @past_year)

    assert_response :success
    assert_select "body", text: /HIST-100/
    assert_select "body", text: /CUR-100/, count: 0
    assert_select "div.table-container.w-fit > table.responsive-table"
    assert_select "tr.table-row-striped"
    assert_select "td[data-label=Barcode]", text: /HIST-100/
    assert_select "input[name='person_asset[barcode]']", count: 0
    assert_select "select[name='year'] option[value='#{Current.year}']", minimum: 1
    assert_select "select[name='year'] option[value='#{@past_year}']", minimum: 1
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end

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

  def create_checkout(asset:, person:, **attributes)
    PersonAsset.create!(
      {
        asset: asset,
        person: person,
        checked_out: attributes.delete(:checked_out) || Current.time
      }.merge(attributes)
    )
  end

  def next_sequence
    @next_sequence = (@next_sequence || 0) + 1
  end
  # rubocop:enable Metrics/ClassLength
end
