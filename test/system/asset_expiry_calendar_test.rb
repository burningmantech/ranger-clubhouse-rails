# frozen_string_literal: true

require "application_system_test_case"

# The Expires On field's calendar lives in <body>, outside the form, and a refused
# save re-renders the form by morphing the page. The calendar has to survive the
# morph, and the field has to keep what was typed, with its error.
class AssetExpiryCalendarTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  CALENDAR = "[data-vc='calendar']:not([data-vc-calendar-hidden])"
  FIELD = "input#asset_expires_at"

  setup do
    editor = person(:active_ranger)
    ensure_role(Role::EDIT_ASSETS, "Edit Assets")
    grant_role(editor, Role::EDIT_ASSETS)
    Asset.create!(barcode: "RAD-200", type: Asset::TYPE_RADIO, year: Current.year)
    @asset = Asset.create!(barcode: "RAD-100", type: Asset::TYPE_RADIO, year: Current.year,
                           expires_at: Time.zone.local(Current.year, 9, 15, 14, 30))
    sign_in(editor)
  end

  test "the calendar still opens after a save refused for another field" do
    visit edit_asset_management_record_path(@asset)
    find(FIELD).click
    assert_selector CALENDAR
    find("[data-vc-close]").click
    assert_no_selector CALENDAR

    fill_in "Barcode", with: "RAD-200"
    click_on "Save Asset"
    assert_text "Barcode has already been taken."

    find(FIELD).click
    assert_selector CALENDAR
  end

  test "a refused expiry keeps what was typed, shows its error, and still opens the calendar" do
    visit edit_asset_management_record_path(@asset)
    find(FIELD).set("soon")
    find("[data-vc-close]").click
    click_on "Save Asset"
    assert_text "The expiration is not a date and time we could read."

    assert_selector "#{FIELD}.input-error"
    assert_equal "soon", find(FIELD).value
    find(FIELD).click
    assert_selector CALENDAR
  end

  test "on a phone the field stays a native date and time picker after a refused save" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit edit_asset_management_record_path(@asset)
    assert_selector "#{FIELD}[type='datetime-local']"

    fill_in "Barcode", with: "RAD-200"
    click_on "Save Asset"
    assert_text "Barcode has already been taken."

    assert_selector "#{FIELD}[type='datetime-local']"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
