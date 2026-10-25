# frozen_string_literal: true

require "test_helper"

class Communication::RbsMessagesControllerTest < ActionDispatch::IntegrationTest
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

    @listener = rbs_person("Listener")
    @sent = BroadcastMessage.create!(person_id: @listener.id, address_type: "sms",
                                     address: @listener.sms_number, direction: "outbound",
                                     status: Broadcast::STATUS_SENT)
    @received = BroadcastMessage.create!(person_id: @listener.id, address_type: "sms",
                                         address: @listener.sms_number, direction: "inbound",
                                         status: Broadcast::STATUS_STOP, message: "STOP")
    @unknown = BroadcastMessage.create!(address_type: "sms", address: "+14155550000",
                                        direction: "inbound",
                                        status: Broadcast::STATUS_UNKNOWN_PHONE,
                                        message: "who is this")

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "a Megaphone role alone may not read the message log" do
    sign_in_as(@megaphone)

    get communication_rbs_messages_path

    assert_redirected_to me_root_path
  end

  test "a Tech Ninja may read the message log" do
    sign_in_as(@tech)

    get communication_rbs_messages_path

    assert_response :success
  end

  test "the log lists what was sent and what came back" do
    get communication_rbs_messages_path

    assert_response :success
    assert_match "STOP", response.body
    assert_match @listener.callsign, response.body
  end

  test "the log can be narrowed to what phones sent in" do
    get communication_rbs_messages_path(filter: { direction: "inbound" })

    assert_response :success
    assert_select "tbody tr", minimum: 1
    assert_match "Asked to stop", response.body
  end

  test "the log can be narrowed to one outcome" do
    get communication_rbs_messages_path(filter: { status: [Broadcast::STATUS_UNKNOWN_PHONE] })

    assert_response :success
    assert_match "who is this", response.body
    assert_no_match(/STOP</, response.body)
  end

  test "an email that did not go shows why, and the log can be narrowed to that reason" do
    BroadcastMessage.create!(person_id: @listener.id, address_type: "email", address: @listener.email,
                             direction: "outbound", status: "account-throttled")

    get communication_rbs_messages_path(filter: { status: ["account-throttled"] })

    assert_response :success
    assert_select "#rbs-email-failure-label", text: "Email Failure Reason"
    assert_select "input#rbs-status-account-throttled[checked]"
    assert_select ".badge", text: "SES rate limit"
    assert_no_match(/who is this/, response.body)
  end

  # Not a failure, so it sits with the other outcomes, not the SES reasons.
  test "an email never sent to an address that bounced or was reported as spam shows why, and can be found" do
    BroadcastMessage.create!(person_id: @listener.id, address_type: "email", address: @listener.email,
                             direction: "outbound", status: Rbs::EMAIL_STATUS_SUPPRESSED)

    get communication_rbs_messages_path(filter: { status: [Rbs::EMAIL_STATUS_SUPPRESSED] })

    assert_response :success
    assert_select "[aria-labelledby=rbs-status-label] input#rbs-status-suppressed[checked]"
    assert_select ".badge", text: "Bounce or spam report on file"
    assert_no_match(/who is this/, response.body)
  end

  # Never sent either: an opt-out, or no address on file, as here. The box
  # carries the code, so only the badge is checked for it.
  test "an email skipped for an opt-out or no address shows why, and can be found" do
    BroadcastMessage.create!(person_id: @listener.id, address_type: "email", address: "",
                             direction: "outbound", status: Rbs::EMAIL_STATUS_NO_CONTACT)

    get communication_rbs_messages_path(filter: { status: [Rbs::EMAIL_STATUS_NO_CONTACT] })

    assert_response :success
    assert_select "[aria-labelledby=rbs-status-label] input#rbs-status-no-contact[checked]"
    assert_select ".badge", text: "Opted out or no address on file"
    assert_select ".badge", text: "no-contact", count: 0
    assert_select "a span", text: "Outcome: Opted out or no address on file"
    assert_no_match(/who is this/, response.body)
    assert_no_match(/STOP</, response.body)
  end

  test "a callsign no one holds returns no messages rather than all of them" do
    get communication_rbs_messages_path(filter: { callsign: "NotARealCallsign" })

    assert_response :success
    assert_select "tbody tr", 0
  end

  test "the log can be narrowed to one person" do
    get communication_rbs_messages_path(filter: { callsign: @listener.callsign })

    assert_response :success
    assert_match @listener.callsign, response.body
  end

  test "a page past the end lands on the last page there is" do
    get communication_rbs_messages_path(filter: { page: 99_999_999 })

    assert_response :success
    assert_match "Page 1 of 1", response.body
  end

  test "a page number that is not a number does not fail" do
    get communication_rbs_messages_path(filter: { page: ["2"] })

    assert_response :success
  end

  test "a filter that is not a set of fields is ignored" do
    get communication_rbs_messages_path(filter: "nonsense")

    assert_response :success
  end

  # Direction says which way a row points, never whether it went: these two
  # never left, and still read outgoing. The Outcome says what became of them.
  test "the log names direction outgoing or incoming, never sent or received" do
    BroadcastMessage.create!(person_id: @listener.id, address_type: "email", address: @listener.email,
                             direction: "outbound", status: Rbs::EMAIL_STATUS_SUPPRESSED)
    BroadcastMessage.create!(person_id: @listener.id, address_type: "sms", address: @listener.sms_number,
                             direction: "outbound", status: Broadcast::STATUS_SERVICE_FAIL)

    get communication_rbs_messages_path

    assert_response :success
    assert_select "tbody td", text: /\A\s*sent\s*\z/, count: 0
    assert_select "tbody td", text: /\A\s*received\s*\z/, count: 0
    assert_select "tbody td", text: /\A\s*outgoing\s*\z/, count: 3
    assert_select "tbody td", text: /\A\s*incoming\s*\z/, count: 2
    assert_select "section[aria-labelledby=rbs-messages-header]",
                  text: /Every text, email, and Clubhouse message the broadcast system recorded in the year, outgoing and incoming\./
    assert_select "[class~=?]", "bg-base-100", text: /\A\s*2\s*Incoming from Phones\s*\z/
    assert_select "#rbs-message-filters option", text: /received|sent/i, count: 0

    get communication_rbs_messages_path(filter: { direction: "outbound" })

    assert_response :success
    assert_select "tbody td", text: /\A\s*outgoing\s*\z/, count: 3
    assert_select "tbody td", text: /\A\s*incoming\s*\z/, count: 0
    assert_match "Direction: Outgoing from the Clubhouse", response.body

    get communication_rbs_messages_path(year: 2019)

    assert_response :success
    assert_match "No messages were recorded in 2019.", response.body
  end
end
