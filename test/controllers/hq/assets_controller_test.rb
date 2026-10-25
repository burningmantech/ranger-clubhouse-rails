# frozen_string_literal: true

require "test_helper"

# The in-shell HQ assets page. The checkout guard chain itself is
# AssetManagementConcern's and is exercised through the shift-manage and
# person-assets suites, so the assertions here concentrate on what is
# genuinely new:
#
#   * the widened audience — Shift Management alone reaches the page, where
#     the sidebar link-out it replaces demanded the person-page roles;
#   * the page split — open checkouts and the year's history render as
#     separate sections, current year only;
#   * the radio-agreement gate — no barcode form until the agreement is
#     signed;
#   * the concern actions mounted on this page's own paths, so every outcome
#     lands back on /hq/N/assets.
class Hq::AssetsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # The HQ shell loads PersonEventInfo, whose training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- Access gates ----------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_assets_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_assets_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "a shift management only operator reaches the page" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"

    get hq_assets_path(@subject)

    assert_response :success
    assert_select "#hq-assets-header", text: /#{Current.year} Assets/
  end

  # --- Page split ------------------------------------------------------------

  test "open checkouts and checked in history render in separate sections, current year only" do
    open_row = checkout!(barcode: "HQPAGE1")
    closed_row = checkout!(barcode: "HQPAGE2",
                           checked_in: Time.zone.local(2026, 8, 29, 12, 0, 0))
    past_row = checkout!(barcode: "HQPAGE3", year: 2025,
                         checked_out: Time.zone.local(2025, 8, 30, 10, 0, 0),
                         checked_in: Time.zone.local(2025, 8, 30, 16, 0, 0))

    get hq_assets_path(@subject)

    assert_response :success
    assert_select "a[href='#{hq_assets_check_in_path(@subject, open_row)}'][data-turbo-method='patch']"
    assert_select "a[href='#{hq_assets_change_attachment_path(@subject, open_row)}']"
    assert_includes @response.body, open_row.asset.barcode
    assert_includes @response.body, closed_row.asset.barcode
    assert_not_includes @response.body, past_row.asset.barcode,
                        "a prior-year checkout must not appear on the current-year page"
    # The closed row offers neither check-in nor attachment change.
    assert_select "a[href='#{hq_assets_check_in_path(@subject, closed_row)}']", false
    assert_select "a[href='#{hq_assets_change_attachment_path(@subject, closed_row)}']", false
  end

  # --- Radio agreement gate --------------------------------------------------

  test "no barcode form until the radio agreement is signed" do
    get hq_assets_path(@subject)

    assert_response :success
    assert_select "form[action='#{hq_assets_checkout_path(@subject)}']", false
    assert_match(/Radio Agreement Not Signed/, @response.body)
  end

  test "the barcode form renders once the agreement is signed" do
    authorize_assets!

    get hq_assets_path(@subject)

    assert_response :success
    assert_select "form[action='#{hq_assets_checkout_path(@subject)}']"
    assert_no_match(/Radio Agreement Not Signed/, @response.body)
  end

  # --- Concern actions on this page's paths -----------------------------------

  test "checkout creates the row and lands back on the assets page" do
    authorize_assets!
    asset = create_asset!(barcode: "HQASSETS1")

    post hq_assets_checkout_path(@subject),
         params: { person_asset: { barcode: "HQASSETS1" } }

    assert_redirected_to hq_assets_path(@subject)
    row = PersonAsset.order(:id).last
    assert_equal asset.id, row.asset_id
    assert_equal @subject.id, row.person_id
    assert_equal @viewer.id, row.check_out_person_id
  end

  test "check in stamps the row and lands back on the assets page" do
    row = checkout!(barcode: "HQASSETS2")

    patch hq_assets_check_in_path(@subject, row)

    assert_redirected_to hq_assets_path(@subject)
    assert_not_nil row.reload.checked_in
    assert_equal @viewer.id, row.check_in_person_id
  end

  private

  def authorize_assets!
    PersonEvent.create!(person_id: @subject.id, year: Current.year, asset_authorized: true)
  end

  def create_asset!(barcode:, year: 2026)
    Asset.create!(barcode:, type: Asset::TYPE_RADIO, year:)
  end

  def checkout!(barcode:, year: 2026,
                checked_out: Time.zone.local(2026, 8, 28, 10, 0, 0),
                checked_in: nil)
    PersonAsset.create!(person_id: @subject.id,
                        asset_id: create_asset!(barcode:, year:).id,
                        checked_out:, checked_in:)
  end
end
