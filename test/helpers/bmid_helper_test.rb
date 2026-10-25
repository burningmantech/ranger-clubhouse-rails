# frozen_string_literal: true

require "test_helper"

class BmidHelperTest < ActionView::TestCase
  include DateTimeHelper

  test "bmid_sap_badge_value returns 'None' when no SAP is on file" do
    bmid = Bmid.new
    assert_equal "None", bmid_sap_badge_value(bmid)
  end

  test "bmid_sap_badge_value returns 'Any' for access-any-time" do
    bmid = Bmid.new(sap: "requested")
    bmid.access_any_time = true
    assert_equal "Any", bmid_sap_badge_value(bmid)
  end

  test "bmid_sap_badge_value formats a specific access date without the year" do
    bmid = Bmid.new(sap: "requested")
    bmid.access_date = Date.new(2026, 8, 31) # a Monday
    assert_equal "Mon Aug 31", bmid_sap_badge_value(bmid)
  end

  test "bmid_sap_badge_value returns 'Unspecified' when SAP exists but no date is set" do
    bmid = Bmid.new(sap: "requested")
    assert_equal "Unspecified", bmid_sap_badge_value(bmid)
  end
end
