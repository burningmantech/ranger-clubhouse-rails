# frozen_string_literal: true

require "test_helper"
require "ostruct"

# Unit tests for the pure Moodle client helpers plus decode_response / warnings
# handling. These never touch the network or DB: helpers run against lightweight
# doubles, and the only DB-writing collaborator (ErrorLog) is stubbed on the
# failure paths.
class MoodleTest < ActiveSupport::TestCase
  include ErrorLogTestHelper

  PersonDouble = Struct.new(:last_name, :desired_first_name, :callsign, :email, :id, keyword_init: true)
  ResponseDouble = Struct.new(:code, :body, keyword_init: true)

  # ---- normalize_email ----

  test "normalize_email strips a plus alias" do
    assert_equal "account@domain.com", Moodle.normalize_email("account+alias@domain.com")
  end

  test "normalize_email leaves a plain address unchanged" do
    assert_equal "plain@example.org", Moodle.normalize_email("plain@example.org")
  end

  test "normalize_email strips a multi-part alias up to the at sign" do
    assert_equal "ranger@example.org", Moodle.normalize_email("ranger+one+two@example.org")
  end

  test "normalize_email tolerates a nil address" do
    assert_equal "", Moodle.normalize_email(nil)
  end

  # ---- build_moodle_username ----

  test "build_moodle_username strips (NR), spaces, punctuation and downcases" do
    person = PersonDouble.new(callsign: "Danger Ranger (NR)")
    assert_equal "dangerranger", Moodle.build_moodle_username(person)
  end

  test "build_moodle_username removes (NR) case-insensitively" do
    person = PersonDouble.new(callsign: "Spot (nr)")
    assert_equal "spot", Moodle.build_moodle_username(person)
  end

  test "build_moodle_username transliterates diacritics" do
    person = PersonDouble.new(callsign: "Renée")
    assert_equal "renee", Moodle.build_moodle_username(person)
  end

  test "build_moodle_username keeps underscores but drops other symbols" do
    person = PersonDouble.new(callsign: "Night_Owl!")
    assert_equal "night_owl", Moodle.build_moodle_username(person)
  end

  # ---- generate_password ----

  test "generate_password has the LastName + initial + ! + 6 digits shape" do
    person = PersonDouble.new(last_name: "Smith", desired_first_name: "John")
    50.times do
      password = Moodle.generate_password(person)
      assert_match(/\ASmithJ!\d{6}[a-k]*\z/, password, "unexpected password: #{password}")
      assert_operator password.length, :>=, 10
      assert_match(/[a-z]/, password)
    end
  end

  test "generate_password pads short names out to at least ten characters" do
    person = PersonDouble.new(last_name: "O", desired_first_name: "A")
    50.times do
      password = Moodle.generate_password(person)
      assert_operator password.length, :>=, 10
      assert_match(/\AOA!\d{6}[a-k]+\z/, password, "unexpected password: #{password}")
      assert_match(/[a-z]/, password)
    end
  end

  test "generate_password title-cases the last name after the first letter" do
    person = PersonDouble.new(last_name: "MCKENNA", desired_first_name: "Bea")
    assert Moodle.generate_password(person).start_with?("MckennaB!")
  end

  test "generate_password transliterates diacritics in the name" do
    person = PersonDouble.new(last_name: "Åström", desired_first_name: "Éowyn")
    assert Moodle.generate_password(person).start_with?("AstromE!")
  end

  # ---- decode_response ----

  test "decode_response returns an OpenStruct for a JSON object" do
    response = ResponseDouble.new(code: "200", body: %q({"users":[{"id":7}],"warnings":[]}))
    result = Moodle.decode_response(response, "https://lms.example/ws")
    assert_instance_of OpenStruct, result
    assert_equal 7, result.users[0].id
  end

  test "decode_response returns an Array for a JSON list" do
    response = ResponseDouble.new(code: "200", body: %q([{"id":1,"format":"topics"}]))
    result = Moodle.decode_response(response, "https://lms.example/ws")
    assert_instance_of Array, result
    assert_equal 1, result[0].id
  end

  test "decode_response returns a nested object without an exception key" do
    response = ResponseDouble.new(code: "200", body: %q({"completionstatus":{"completed":true}}))
    result = Moodle.decode_response(response, "https://lms.example/ws")
    assert result.completionstatus.completed
  end

  test "decode_response handles a bare null body" do
    response = ResponseDouble.new(code: "200", body: "null")
    assert_nil Moodle.decode_response(response, "https://lms.example/ws")
  end

  test "decode_response raises DownForMaintenanceError on the maintenance page" do
    response = ResponseDouble.new(code: "503", body: "<h1>This site is undergoing maintenance</h1>")
    silence_error_log do |calls|
      assert_raises(Moodle::DownForMaintenanceError) do
        Moodle.decode_response(response, "https://lms.example/ws")
      end
      assert_equal "lms-down-for-maintenance", calls.first[:type]
    end
  end

  test "decode_response raises on an HTTP failure status" do
    response = ResponseDouble.new(code: "500", body: "kaboom")
    silence_error_log do |calls|
      error = assert_raises(RuntimeError) do
        Moodle.decode_response(response, "https://lms.example/ws")
      end
      assert_match(/status=500/, error.message)
      assert_equal "lms-request-failure", calls.first[:type]
    end
  end

  test "decode_response raises when the body carries a Moodle exception" do
    body = %q({"exception":"webservice_access_exception","errorcode":"accessexception","message":"nope"})
    response = ResponseDouble.new(code: "200", body: body)
    silence_error_log do
      error = assert_raises(RuntimeError) do
        Moodle.decode_response(response, "https://lms.example/ws")
      end
      assert_match(/webservice_access_exception/, error.message)
    end
  end

  test "decode_response raises a decode error on malformed JSON" do
    response = ResponseDouble.new(code: "200", body: "not json{")
    silence_error_log do |calls|
      error = assert_raises(RuntimeError) do
        Moodle.decode_response(response, "https://lms.example/ws")
      end
      assert_match(/decode/, error.message)
      assert(calls.any? { |c| c[:method] == :record_exception }, "expected ErrorLog.record_exception to be called")
    end
  end

  # ---- check_for_warnings ----

  test "check_for_warnings raises when warnings are present" do
    result = OpenStruct.new(warnings: [{ "warningcode" => "x", "message" => "skipped" }])
    silence_error_log do |calls|
      error = assert_raises(RuntimeError) do
        Moodle.check_for_warnings(result, Moodle::WS_UPDATE_USERS)
      end
      assert_match(/#{Moodle::WS_UPDATE_USERS}/, error.message)
      assert_equal "lms-request-warning", calls.first[:type]
    end
  end

  test "check_for_warnings is a no-op when warnings are empty" do
    assert_nil Moodle.check_for_warnings(OpenStruct.new(warnings: []), Moodle::WS_UPDATE_USERS)
  end

  test "check_for_warnings is a no-op when there is no warnings key" do
    assert_nil Moodle.check_for_warnings(OpenStruct.new(status: true), Moodle::WS_UPDATE_USERS)
  end

  test "check_for_warnings is a no-op for a non-object result" do
    assert_nil Moodle.check_for_warnings(nil, Moodle::WS_UPDATE_USERS)
  end

  # ---- redact_sensitive_data ----

  test "redact_sensitive_data redacts token and password without mutating the input" do
    data = { "wstoken" => "secret", "password" => "hunter2", "wsfunction" => "core_user_get_users" }
    redacted = Moodle.redact_sensitive_data(data)

    assert_equal "[REDACTED]", redacted["wstoken"]
    assert_equal "[REDACTED]", redacted["password"]
    assert_equal "core_user_get_users", redacted["wsfunction"]
    assert_equal "secret", data["wstoken"], "original hash must not be mutated"
  end

  # ---- build_query ----

  test "build_query encodes nested arrays with numeric indices like http_build_query" do
    query = Moodle.build_query({ "users" => [{ "username" => "spot", "idnumber" => 7 }] })
    assert_equal "users%5B0%5D%5Busername%5D=spot&users%5B0%5D%5Bidnumber%5D=7", query
  end

  test "build_query encodes a criteria array of hashes" do
    query = Moodle.build_query({ "criteria" => [{ "key" => "email", "value" => "a@b.co" }] })
    assert_equal "criteria%5B0%5D%5Bkey%5D=email&criteria%5B0%5D%5Bvalue%5D=a%40b.co", query
  end
end
