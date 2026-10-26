# frozen_string_literal: true

require "test_helper"

class Alerts::SmsPreferencesServiceTest < ActiveSupport::TestCase
  include FakeTwilioTestHelper

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

  test "send_code texts the code through the Messaging Service, and its row keeps Twilio's SID" do
    @person.update_columns(sms_number: "+14155550101")
    configure_twilio
    fake = FakeTwilioClient.new

    result = with_fake_twilio(fake) { Alerts::SmsPreferencesService.send_code(person: @person) }

    row = BroadcastMessage.where(person_id: @person.id, address_type: "sms").sole

    assert_equal "sent", result.status
    assert_equal [["+14155550101", "Your Clubhouse verification code is: #{@person.reload.sms_code}"]],
                 fake.created_texts.map { |text| text.values_at(:to, :body) }
    assert_equal [Broadcast::STATUS_VERIFY, format("SM%032d", 1)], [row.status, row.message_id]
  end

  # Either way the person is told the code could not be sent: sending again
  # makes a new one.
  test "a code Twilio may have taken is recorded send-unconfirmed, and a refused one only in the error log" do
    @person.update_columns(sms_number: "+14155550101")
    configure_twilio

    taken = with_fake_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.read_timeout })) do
      Alerts::SmsPreferencesService.send_code(person: @person)
    end
    refused = with_fake_twilio(FakeTwilioClient.new(errors: { message_create: FakeTwilioClient.refusal(21211, "Invalid 'To' Phone Number") })) do
      Alerts::SmsPreferencesService.send_code(person: @person)
    end

    assert_equal %w[sent-fail sent-fail], [taken.status, refused.status]
    assert_equal [Broadcast::STATUS_SEND_UNCONFIRMED], BroadcastMessage.where(person_id: @person.id).pluck(:status)
    assert_equal 2, ErrorLog.where(error_type: "sms-exception").count
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
