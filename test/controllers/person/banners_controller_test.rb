# frozen_string_literal: true

require "test_helper"

class Person::BannersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @trainer = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@trainer, Role::TRAINER)

    @permanent_banner = @target.person_banner.create!(
      is_permanent: true,
      message: "Permanent account note."
    )
    @event_banner = @target.person_banner.create!(
      is_permanent: false,
      message: "Event account note."
    )
  end

  teardown do
    Rails.cache.clear
  end

  test "admin can view the banner manager and legacy guidance" do
    sign_in_as(@admin)

    get person_banners_path(@target)

    assert_response :success
    assert_select "h1", text: /Manage account banners/i
    assert_select "a", text: /Add Banner/
    assert_select "th, td", text: /Permanent/
    assert_select "th, td", text: /Event only/
    assert_select "body", text: /The person will not see this message/i
    assert_select "body", text: /Event Management On Playa or Event Management permissions/i
  end

  test "new shows the expected fields and labels" do
    sign_in_as(@admin)

    get new_person_banner_path(@target)

    assert_response :success
    assert_select "legend, label", text: /Event only or permanent/i
    assert_select "label", text: /Banner message to show/i
  end

  test "trainer cannot manage banners" do
    sign_in_as(@trainer)

    get person_banners_path(@target)

    assert_redirected_to person_path(@target)
  end

  test "admin can create a banner" do
    sign_in_as(@admin)

    assert_difference("PersonBanner.count", 1) do
      post person_banners_path(@target), params: {
        person_banner: {
          is_permanent: "true",
          message: "Created from the form."
        }
      }
    end

    banner = PersonBanner.order(:id).last

    assert_redirected_to person_banners_path(@target)
    assert_equal @target.id, banner.person_id
    assert_equal @admin.id, banner.creator_person_id
    assert banner.is_permanent?
    assert_equal "Created from the form.", banner.message
  end

  test "vc can update a banner" do
    sign_in_as(@vc)

    patch person_banner_path(@target, @event_banner), params: {
      person_banner: {
        is_permanent: "true",
        message: "Updated by VC."
      }
    }

    assert_redirected_to person_banners_path(@target)

    @event_banner.reload
    assert @event_banner.is_permanent?
    assert_equal "Updated by VC.", @event_banner.message
    assert_equal @vc.id, @event_banner.updater_person_id
  end

  test "admin can delete a banner" do
    sign_in_as(@admin)

    assert_difference("PersonBanner.count", -1) do
      delete person_banner_path(@target, @permanent_banner)
    end

    assert_redirected_to person_banners_path(@target)
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
