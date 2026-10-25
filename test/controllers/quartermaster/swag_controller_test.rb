# frozen_string_literal: true

require "test_helper"

class Quartermaster::SwagControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @editor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_SWAG, "Edit Swag")
    grant_role(@admin, Role::ADMIN)
    grant_role(@editor, Role::EDIT_SWAG)

    @tshirt = swag(:tshirt_small)
    @pin = swag(:service_pin_5_year)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # The index only lists the types it has labels for, so a type added to the
  # model without a label here would be unreachable.
  test "every swag type the model allows has a page" do
    assert_equal Swag::VALID_TYPES.sort, Quartermaster::SwagController::TYPE_LABELS.keys.sort
  end

  test "denies access without the admin or edit swag role" do
    sign_in_as(@outsider)

    get quartermaster_swag_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Swag role required to manage the swag catalog.", flash[:error]
  end

  test "allows access with only the edit swag role" do
    sign_in_as(@editor)

    get quartermaster_swag_path

    assert_response :success
  end

  test "index lists every type with its item count" do
    get quartermaster_swag_path

    assert_response :success
    assert_select "a[href=?]", quartermaster_swag_type_path(Swag::TYPE_DEPT_SHIRT)
    assert_select "a[href=?]", quartermaster_swag_type_path(Swag::TYPE_OTHER)

    # Eight shirt fixtures, one of them deactivated.
    assert_match "8 items", response.body
    assert_match "1 inactive", response.body
  end

  test "index lists a type holding nothing" do
    Swag.where(type: Swag::TYPE_ORG_PIN).delete_all

    get quartermaster_swag_path

    assert_response :success
    assert_select "a[href=?]", quartermaster_swag_type_path(Swag::TYPE_ORG_PIN)
    assert_match "0 items", response.body
  end

  test "type page lists only that type and shows the shirt type column" do
    get quartermaster_swag_type_path(Swag::TYPE_DEPT_SHIRT)

    assert_response :success
    assert_select "th", text: "Shirt Type"
    assert_match @tshirt.title, response.body
    assert_no_match @pin.title, response.body
  end

  # Ember ran the description through nl2br; here a CSS rule does it, so the
  # newline has to survive into the markup rather than be collapsed.
  test "type page keeps the line breaks in a description" do
    get quartermaster_swag_type_path(Swag::TYPE_OTHER)

    assert_response :success
    assert_select "div.whitespace-pre-line"
    assert_match "First line\nSecond line", response.body
  end

  test "type page omits the shirt type column for other types" do
    get quartermaster_swag_type_path(Swag::TYPE_DEPT_PIN)

    assert_response :success
    assert_select "th", text: "Shirt Type", count: 0
    assert_match @pin.title, response.body
  end

  test "type page shows an empty state when the type holds nothing" do
    Swag.where(type: Swag::TYPE_ORG_PIN).delete_all

    get quartermaster_swag_type_path(Swag::TYPE_ORG_PIN)

    assert_response :success
    assert_match "No items have been added to Org Service Pins yet.", response.body
  end

  test "type page rejects an unknown type" do
    get quartermaster_swag_type_path("nonsense")

    assert_redirected_to quartermaster_swag_path
    assert_equal "That swag type could not be found.", flash[:error]
  end

  test "new preselects the requested type" do
    get quartermaster_new_swag_path(type: Swag::TYPE_ORG_PATCH)

    assert_response :success
    assert_select "select#swag_type option[selected][value=?]", Swag::TYPE_ORG_PATCH
  end

  test "creates a swag and lands on its type page" do
    assert_difference "Swag.count", 1 do
      post quartermaster_create_swag_path,
           params: { swag: { title: "Ranger T-Shirt 3XL", type: Swag::TYPE_DEPT_SHIRT,
                             shirt_type: Swag::SHIRT_T_SHIRT, active: "1",
                             description: "Extra roomy" } }
    end

    created = Swag.order(:id).last
    assert_redirected_to quartermaster_swag_type_path(Swag::TYPE_DEPT_SHIRT,
                                                      anchor: "swag-#{created.id}")
    assert_equal "Swag created.", flash[:success]
    assert_equal Swag::SHIRT_T_SHIRT, created.shirt_type
    assert created.active
  end

  test "rejects a swag without a title" do
    assert_no_difference "Swag.count" do
      post quartermaster_create_swag_path,
           params: { swag: { title: "", type: Swag::TYPE_DEPT_PIN, active: "1" } }
    end

    assert_response :unprocessable_entity
  end

  test "drops the shirt type when the item is not a shirt" do
    post quartermaster_create_swag_path,
         params: { swag: { title: "Coffee Mug", type: Swag::TYPE_OTHER,
                           shirt_type: Swag::SHIRT_LONG_SLEEVE, active: "1" } }

    assert_equal "", Swag.order(:id).last.shirt_type
  end

  test "updates a swag" do
    patch quartermaster_swag_item_path(@pin),
          params: { swag: { title: "Ranger 5 Year Pin", type: @pin.type, active: "0" } }

    assert_redirected_to quartermaster_swag_type_path(@pin.type, anchor: "swag-#{@pin.id}")
    assert_equal "Swag updated.", flash[:success]

    @pin.reload
    assert_equal "Ranger 5 Year Pin", @pin.title
    assert_not @pin.active
  end

  test "a type change redirects to the new type's page" do
    patch quartermaster_swag_item_path(@pin),
          params: { swag: { title: @pin.title, type: Swag::TYPE_ORG_PIN, active: "1" } }

    assert_redirected_to quartermaster_swag_type_path(Swag::TYPE_ORG_PIN, anchor: "swag-#{@pin.id}")
    assert_equal Swag::TYPE_ORG_PIN, @pin.reload.type
  end

  test "edit warns how many records a shirt was issued on" do
    PersonSwag.create!(person_id: @admin.id, swag_id: @tshirt.id, year_issued: 2025, notes: "")

    get quartermaster_edit_swag_path(@tshirt)

    assert_response :success
    assert_match "1 Ranger record", response.body
    assert_match "will have that choice cleared", response.body
  end

  test "deletes a swag along with the records it was issued on" do
    issued = PersonSwag.create!(person_id: @admin.id, swag_id: @pin.id, year_issued: 2025, notes: "")

    assert_difference ["Swag.count", "PersonSwag.count"], -1 do
      delete quartermaster_swag_item_path(@pin)
    end

    assert_redirected_to quartermaster_swag_type_path(Swag::TYPE_DEPT_PIN)
    assert_equal "Swag deleted.", flash[:success]
    assert_not PersonSwag.exists?(issued.id)
  end

  test "deleting a shirt clears it from the Rangers who chose it" do
    @admin.update_columns(tshirt_swag_id: @tshirt.id, long_sleeve_swag_id: @tshirt.id)

    delete quartermaster_swag_item_path(@tshirt)

    @admin.reload
    assert_nil @admin.tshirt_swag_id
    assert_nil @admin.long_sleeve_swag_id
  end
end
