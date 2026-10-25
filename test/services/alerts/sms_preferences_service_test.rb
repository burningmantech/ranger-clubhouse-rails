# frozen_string_literal: true

require "test_helper"

class Alerts::SmsPreferencesServiceTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    @person.update_columns(sms_number: nil, sms_code: nil, sms_verified: false, sms_stopped: false)
  end

  # =========================================================================
  # save_number
  # =========================================================================

  test "save_number clears number when blank" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    result = Alerts::SmsPreferencesService.save_number(person: @person, raw_number: "")

    assert result.success?
    assert_equal "cleared", result.status

    @person.reload
    assert_nil @person.sms_number
    assert_not @person.sms_verified?
  end

  test "save_number returns unchanged when number is the same" do
    @person.update_columns(sms_number: "+12025551234", sms_verified: true)

    result = Alerts::SmsPreferencesService.save_number(person: @person, raw_number: "+12025551234")

    assert result.success?
    assert_equal "unchanged", result.status
  end

  test "save_number rejects invalid number" do
    result = Alerts::SmsPreferencesService.save_number(person: @person, raw_number: "abc")

    assert_not result.success?
    assert_equal "invalid-number", result.status
    assert result.errors[:sms_number].present?
  end

  test "save_number rejects duplicate number" do
    other = person(:inactive_ranger)
    other.update_columns(sms_number: "+12025551234")

    result = Alerts::SmsPreferencesService.save_number(person: @person, raw_number: "+12025551234")

    assert_not result.success?
    assert_equal "duplicate-number", result.status
  end

  test "save_number rejects UK numbers" do
    result = Alerts::SmsPreferencesService.save_number(person: @person, raw_number: "+447911123456")

    assert_not result.success?
    assert_equal "country-not-supported", result.status
  end

  # =========================================================================
  # send_code
  # =========================================================================

  test "send_code refuses when no number" do
    result = Alerts::SmsPreferencesService.send_code(person: @person)

    assert_not result.success?
    assert_equal "no-number", result.status
  end

  test "send_code refuses when already verified" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    result = Alerts::SmsPreferencesService.send_code(person: @person)

    assert_not result.success?
    assert_equal "already-verified", result.status
  end

  # =========================================================================
  # confirm_code
  # =========================================================================

  test "confirm_code verifies with correct code" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "4321", sms_verified: false)

    result = Alerts::SmsPreferencesService.confirm_code(person: @person, code: "4321")

    assert result.success?
    assert_equal "confirmed", result.status

    @person.reload
    assert @person.sms_verified?
  end

  test "confirm_code rejects code of differing length without raising" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "4321", sms_verified: false)

    result = Alerts::SmsPreferencesService.confirm_code(person: @person, code: "12345")

    assert_not result.success?
    assert_equal "no-match", result.status
  end

  test "confirm_code rejects wrong code" do
    @person.update_columns(sms_number: "+15551234567", sms_code: "4321", sms_verified: false)

    result = Alerts::SmsPreferencesService.confirm_code(person: @person, code: "0000")

    assert_not result.success?
    assert_equal "no-match", result.status

    @person.reload
    assert_not @person.sms_verified?
  end

  test "confirm_code returns already-verified when already verified" do
    @person.update_columns(sms_number: "+15551234567", sms_verified: true)

    result = Alerts::SmsPreferencesService.confirm_code(person: @person, code: "1234")

    assert_not result.success?
    assert_equal "already-verified", result.status
  end

  test "confirm_code returns no-number when no number on file" do
    result = Alerts::SmsPreferencesService.confirm_code(person: @person, code: "1234")

    assert_not result.success?
    assert_equal "no-number", result.status
  end
end
