# frozen_string_literal: true

require "test_helper"

# Synthetic statements only: the log is personal data and never enters test/.
class LegacyLog::ConverterTest < ActiveSupport::TestCase
  OCCURRED = Time.zone.parse("2015-06-01 12:00:00")

  def convert(event, user: 7, session: 9, id: 42)
    LegacyLog::Converter.convert(id, user, session, OCCURRED, event).first
  end

  def event_of(statement)
    convert(statement)[:event]
  end

  test "names events by the house rule, with Clubhouse 2's names where it chose them" do
    assert_equal "person-slot-add", event_of("+personslot(personid,slotid)(687,386)")
    assert_equal "person-slot-remove", event_of("-personslot@personid=687&slotid=15")
    assert_equal "person-position-add", event_of("+personposition(1,26)")
    assert_equal "person-position-remove", event_of("-personposition@personid=198&positionid=3")
    assert_equal "person-role-add", event_of("+personrole(personid,roleid)(522,1)")
    assert_equal "person-role-remove", event_of("-personrole@personid=202&roleid=101")
    assert_equal "person-asset-create", event_of("+assetperson(personid,assetid,checkedout)(634,3,NOW())")
    assert_equal "person-alert-create", event_of("+alertperson(personid,alertid)(5,2)")
    assert_equal "person-update", event_of("=person.status=alpha@id=1578")
    assert_equal "person-create", event_of("+person.firstname=,mi=,lastname=,callsign=")
    assert_equal "timesheet-update", event_of("=timesheet.offduty=NOW()@id=9&offdutyISNULL")
    assert_equal "manual-review-create", event_of("+manualreview(personid,passdate)SELECT290,2018-04-06FROMDUAL")
    assert_equal "trainee-status-create", event_of("+`traineestatus`.slotid=16034,personid=2707,passed=0,notes=")
    assert_equal "access-document-changes-create",
                 event_of("+accessdocumentchanges(tablename,recordid,operation)(accessdocument,170152,modify)")
    assert_equal "person-language-update", event_of("+personlanguage(personid,language)(5,Spanish)ONDUPLICATEKEY=language=Spanish")
    assert_equal "unknown", event_of("=traineestatus.passed=0,notes=@id=LIMIT1")
  end

  test "the actor is the signed-in user and the target the person the statement names" do
    row = convert("+personslot(personid,slotid)(687,386)", user: 7, session: 9)

    assert_equal 7, row[:person_id]
    assert_equal 687, row[:target_person_id]
    assert_equal 9, row[:data]["legacy"]["session_person_id"]
    assert_equal OCCURRED, row[:created_at]
  end

  test "the session's person is kept only when it differs from the target" do
    session_of = ->(statement, session) { convert(statement, session:)[:data]["legacy"]["session_person_id"] }

    assert_nil session_of.call("=person.status=alpha@id=9", 9)
    assert_equal 9, session_of.call("=person.onsite=0@onsite!=0", 9)
    assert_nil session_of.call("=person.onsite=0@onsite!=0", 0)
  end

  test "a person named as zero or NULL is no one" do
    row = convert("+personslot(personid,slotid)(0,386)", user: 0, session: nil)

    assert_nil row[:target_person_id]
    assert_nil row[:person_id]
  end

  test "the recipient is the target of a contact log entry" do
    assert_equal 9, convert("+contactlog(senderpersonid,recipientpersonid,type)(5,9,mentor)")[:target_person_id]
  end

  test "an update's data is the new values and its ids, under today's column names" do
    row = convert("=timesheet.offduty=2015-08-30,positionid=9@id=212&personid=5", session: 5)

    assert_equal({ "off_duty" => "2015-08-30", "position_id" => 9, "id" => 212, "person_id" => 5,
                   "legacy" => { "event" => "=timesheet.offduty=2015-08-30,positionid=9@id=212&personid=5",
                                 "log_id" => 42 } }, row[:data])
  end

  test "an insert's data pairs its columns with its values" do
    row = convert("+timesheet(personid,positionid,onduty)(5,9,NOW())")

    assert_equal({ "person_id" => 5, "position_id" => 9, "on_duty" => "NOW()" }, row[:data].except("legacy"))
  end

  test "an insert whose value holds a comma pairs nothing, and keeps the ids it can trust" do
    row = convert("+personmessage(personid,subject)(5,Hey,there)")

    assert_equal({ "person_id" => 5 }, row[:data].except("legacy"))
  end

  test "a delete's data is the ids its conditions name" do
    row = convert("-timesheet@id=212")

    assert_equal({ "id" => 212 }, row[:data].except("legacy"))
  end

  test "a sign-up and a grant keep what action_logs keeps: the slot id, or a list of one" do
    assert_equal({ "slot_id" => 386 }, convert("+personslot(personid,slotid)(687,386)")[:data].except("legacy"))
    assert_equal({ "slot_id" => 15 }, convert("-personslot@personid=687&slotid=15")[:data].except("legacy"))
    assert_equal({ "position_ids" => [26] }, convert("+personposition(1,26)")[:data].except("legacy"))
    assert_equal({ "role_ids" => [101] }, convert("-personrole@personid=202&roleid=101")[:data].except("legacy"))
  end

  test "a column Clubhouse 3 no longer has keeps its Classic name" do
    data = convert("=person.oldbarcode=77,status=alpha@id=5")[:data]

    assert_equal({ "oldbarcode" => "77", "status" => "alpha", "id" => 5 }, data.except("legacy"))
  end

  test "a cut statement says so, pairs nothing, and keeps what it still names" do
    head = "+accessdocumentchanges(tablename,recordid,operation,changes)(accessdocument,170152,modify,[["
    data = convert("#{head}#{"x" * (499 - head.length)}+")[:data]

    assert data["legacy"]["truncated"]
    assert_equal 170152, data["record_id"]
    assert_nil data["operation"]
  end

  test "an unknown row keeps the raw event and the session's person" do
    row = convert("=traineestatus.passed=0,notes=@id=LIMIT1", user: 7, session: 9)

    assert_equal "unknown", row[:event]
    assert_equal 9, row[:target_person_id]
    assert_equal({ "legacy" => { "event" => "=traineestatus.passed=0,notes=@id=LIMIT1", "log_id" => 42,
                                 "target_source" => "session" } }, row[:data])
  end

  test "skips events, diagnostics, session purges and custom fields" do
    assert_equal :events, LegacyLog::Converter.skip_reason("#login rangers")
    assert_equal :diagnostics, LegacyLog::Converter.skip_reason("!DB SQL error")
    assert_equal :sessions, LegacyLog::Converter.skip_reason("-sessions@expires<NOW()")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("+personxfield(personid,xfieldid,val)(687,1,)")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("=personxfield.val=x@personid=1&xfieldid=2")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("-personxfield@personid=1")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("=xfield.label=Shoe size@id=3")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("+xgroup(name)(Sizes)")
    assert_equal :custom_fields, LegacyLog::Converter.skip_reason("-xoption@id=4")
    assert_nil LegacyLog::Converter.skip_reason("+personslot(personid,slotid)(687,386)")
  end
end
