# frozen_string_literal: true

require "test_helper"

class Communication::RbsPhoneNumbersControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include RbsTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ensure_rbs_roles

    @admin = person(:active_ranger)
    @tech = person(:echelon_ranger)
    @megaphone = person(:retired_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech, Role::TECH_NINJA)
    grant_role(@megaphone, Role::MEGAPHONE)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "a Megaphone role alone may not read the phone numbers" do
    sign_in_as(@megaphone)

    get communication_rbs_phone_numbers_path

    assert_redirected_to me_root_path
  end

  test "a Tech Ninja may read the phone numbers" do
    sign_in_as(@tech)

    get communication_rbs_phone_numbers_path

    assert_response :success
  end

  test "a number that was never confirmed is listed" do
    waiting = rbs_person("Waiting", verified: false)

    get communication_rbs_phone_numbers_path

    assert_response :success
    assert_match waiting.callsign, response.body
    assert_select "[role=heading]", text: /Not Confirmed \(\d+\)/
  end

  test "a number that asked to stop is listed" do
    stopped = rbs_person("Stopped")
    stopped.update!(sms_stopped: true)

    get communication_rbs_phone_numbers_path

    assert_match stopped.callsign, response.body
    assert_select "[role=heading]", text: /Asked to Stop \(\d+\)/
  end

  # Counted against records this test created, not against the same queries the
  # page uses -- re-deriving the answer from the implementation would pass
  # whatever the implementation said.
  test "the counts match the accounts they describe" do
    Person.where(status: Person::ACTIVE).update_all(sms_number: nil, sms_verified: false,
                                                    sms_stopped: false)
    rbs_person("Confirmed")
    rbs_person("Waiting", verified: false)
    rbs_person("Halted").update!(sms_stopped: true)

    get communication_rbs_phone_numbers_path

    assert_response :success
    row = RbsPhoneNumbers.counts.find { |status_row| status_row.status == Person::ACTIVE }

    assert_equal 3, row.numbers, "three active people were given a number"
    assert_equal 2, row.verified
    assert_equal 1, row.unverified
    assert_equal 1, row.stopped
    assert_select "[role=heading]", text: /Not Confirmed \(1\)/
    assert_select "[role=heading]", text: /Asked to Stop \(1\)/
  end
end
