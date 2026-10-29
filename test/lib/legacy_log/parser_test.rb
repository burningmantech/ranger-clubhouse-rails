# frozen_string_literal: true

require "test_helper"

# Synthetic statements only: the log is personal data and never enters test/.
class LegacyLog::ParserTest < ActiveSupport::TestCase
  def parse(text, truncated: false)
    LegacyLog::Parser.parse(text, truncated:)
  end

  # --- normalisation -------------------------------------------------------

  test "an echoed WHERE clause folds back into one statement, nothing lost" do
    text, truncated = LegacyLog::Parser.normalize("=person.status=alpha@id=4806LIMIT1+@id=4806LIMIT1")

    assert_equal "=person.status=alpha@id=4806LIMIT1", text
    assert_not truncated
  end

  test "a WHERE clause cut partway and repeated whole in the tail is completed, nothing lost" do
    text, truncated = LegacyLog::Parser.normalize("=person.status=alpha@id=48+@id=4806LIMIT1")

    assert_equal "=person.status=alpha@id=4806LIMIT1", text
    assert_not truncated
  end

  test "the 2008 marker is dropped and the statement marked as cut" do
    text, truncated = LegacyLog::Parser.normalize("=person.first=Jo,last=Bloggs,+@id=212")

    assert_equal "=person.first=Jo,last=Bloggs@id=212", text
    assert truncated
  end

  test "a marker whose head never reaches the WHERE clause marks a real cut" do
    text, truncated = LegacyLog::Parser.normalize("=person.notes=abc+@id=212")

    assert_equal "=person.notes=abc@id=212", text
    assert truncated
  end

  test "a bare trailing marker on a short statement is dropped, nothing lost" do
    text, truncated = LegacyLog::Parser.normalize("+personslot(personid,slotid)(422,213)+")

    assert_equal "+personslot(personid,slotid)(422,213)", text
    assert_not truncated
  end

  test "a bare trailing marker on a statement cut at either logger's length marks the cut" do
    later = "+person(notes)(#{"x" * 483})"
    early = "+slot.begins=2008-08-2800:00:00,ends=2008-08-2806:00:00,max=1,description=Grave,positionid=14,train"

    assert_equal [499, 99], [later.length, early.length]
    assert_equal [later, true], LegacyLog::Parser.normalize("#{later}+")
    assert_equal [early, true], LegacyLog::Parser.normalize("#{early}+")
  end

  test "a cut row stored byte by byte as characters is still read as cut" do
    head = "+personmessage(personid,body)(702,#{"â€™" * 10}"
    accented = "#{head}#{"x" * (498 - head.length)})"

    assert_equal 499, accented.length
    assert_operator accented.bytesize, :>, 499
    assert_equal [accented, true], LegacyLog::Parser.normalize("#{accented}+")
  end

  test "a row the logger ran past the column, with no marker left, is read as cut" do
    head = "+personmessage(personid,creatorpersonid,subject,body)(1378,1146,Idea,"
    overflow = "#{head}#{"x" * (500 - head.length)}"

    assert_equal 500, overflow.length
    assert_equal [overflow, true], LegacyLog::Parser.normalize(overflow)
    assert_equal({ "personid" => 1378, "creatorpersonid" => 1146 }, parse(overflow, truncated: true).ids)
    assert_equal [overflow[0, 499], false], LegacyLog::Parser.normalize(overflow[0, 499])
  end

  test "a plus at the start of a value is left alone" do
    event = '=person.address="+19715551234"@id=5'

    assert_equal [event, false], LegacyLog::Parser.normalize(event)
  end

  test "names a statement's family by operation and Classic table" do
    assert_equal "update person", LegacyLog::Parser.family("=person.status=alpha@id=1")
    assert_equal "insert person_slot", LegacyLog::Parser.family("+personslot(personid,slotid)(1,2)")
    assert_equal "insert (widget)", LegacyLog::Parser.family("+widget(a)(1)")
    assert_nil LegacyLog::Parser.family("#login rangers")
  end

  # --- inserts -------------------------------------------------------------

  test "reads a tuple insert, claiming the ids by position" do
    statement = parse("+personslot(personid,slotid)(422,213)")

    assert_equal %w[insert person_slot], [statement.operation, statement.table]
    assert_equal %w[personid slotid], statement.columns
    assert_equal "422,213", statement.values
    assert_equal({ "personid" => 422, "slotid" => 213 }, statement.ids)
    assert_not statement.upsert
  end

  test "reads an insert with no column list on the three tables written that way" do
    statement = parse("+personposition(1,26)")

    assert_equal %w[personid positionid], statement.columns
    assert_equal({ "personid" => 1, "positionid" => 26 }, statement.ids)
    assert_nil parse("+personposition(1,26,3)")
    assert_nil parse("+asset(1,26)")
  end

  test "a person id that is not a person is no statement to read" do
    assert_nil parse("+personrole(personid,roleid)(-1,31)")
  end

  test "reads a set-form insert, claiming the ids it assigns" do
    statement = parse("+personmentor.personid=1541,mentorid=444,mentoryear=2010,status=pass")

    assert_equal "personid=1541,mentorid=444,mentoryear=2010,status=pass", statement.set
    assert_equal({ "personid" => 1541, "mentorid" => 444 }, statement.ids)
  end

  test "an insert with ON DUPLICATE KEY UPDATE is an upsert" do
    statement = parse("+personlanguage(personid,language)(5,Spanish)ONDUPLICATEKEY=language=Spanish")

    assert statement.upsert
    assert_equal({ "personid" => 5 }, statement.ids)
  end

  test "reads an insert from a SELECT, claiming the ids before FROM" do
    statement = parse("+manualreview(personid,passdate)SELECT290,2018-04-0618:04:07FROMDUAL@NOTEXISTS(SELECT*FROMmanualreview@personid=290&year=2018)")

    assert_equal "290,2018-04-0618:04:07", statement.values
    assert_equal({ "personid" => 290 }, statement.ids)
  end

  test "a bulk insert copying a person column from a SELECT converts with no person" do
    statement = parse('+bmid(personid,status,year,title1)SELECTpersonid,"inprep",2018,""FROMpersonposition@positionid=5')

    assert_equal "bmid", statement.table
    assert_equal %w[personid status year title1], statement.columns
    assert_empty statement.ids
  end

  test "a tuple the logger cut before its close is read only when the row was cut" do
    cut = "+accessdocumentchanges(tablename,recordid,operation,changes,changerpersonid)(accessdocument,170152,modify,[["

    assert_equal({ "recordid" => 170152 }, parse(cut, truncated: true).ids)
    assert_nil parse(cut)
  end

  test "a multi-row insert keeps the first tuple's ids" do
    statement = parse("+assetperson(personid,assetid)(634,3),(635,4)")

    assert_equal({ "personid" => 634, "assetid" => 3 }, statement.ids)
  end

  test "ids past a value that is not simple are not claimed by position" do
    statement = parse("+personmessage(personid,creatorpersonid,subject,body)(306,753,Hey,there,mentorid=4)")

    assert_equal({ "personid" => 306, "creatorpersonid" => 753 }, statement.ids)
  end

  # --- updates and deletes -------------------------------------------------

  test "reads an update, its assignments and its conditions" do
    statement = parse("=person.status=alpha@id=1578&status=prospective")

    assert_equal %w[update person], [statement.operation, statement.table]
    assert_equal "status=alpha", statement.set
    assert_equal "id=1578&status=prospective", statement.where
    assert_equal({ "id" => 1578 }, statement.ids)
  end

  test "reads backticks, LIMIT 1 and an empty assignment" do
    statement = parse("=`traineestatus`.passed=1,notes=@id=9270LIMIT1")

    assert_equal "trainee_status", statement.table
    assert_equal "passed=1,notes=", statement.set
    assert_equal({ "id" => 9270 }, statement.ids)
  end

  test "an email in the SET clause does not mislead the WHERE clause" do
    statement = parse("=person.email=joe@example.com@id=5")

    assert_equal "email=joe@example.com", statement.set
    assert_equal({ "id" => 5 }, statement.ids)
  end

  test "an email in the WHERE clause is a value, and names no one" do
    statement = parse("=person.password=[hidden]@email=joe@example.comLIMIT1")

    assert_equal "email=joe@example.com", statement.where
    assert_empty statement.ids
  end

  test "a column with its table in front reads as the column" do
    assert_equal({ "id" => 7 }, parse("=person.onsite=1@person.id=7").ids)
  end

  test "a bulk update with no id converts with no person" do
    statement = parse("=person.onsite=0@onsite!=0")

    assert_equal "onsite!=0", statement.where
    assert_empty statement.ids
  end

  test "the password redaction is a value" do
    assert_equal({ "id" => 108 }, parse("=person.password=[hidden]@id=108&password=[hidden]").ids)
  end

  test "SET glued to the table name is the set form" do
    statement = parse("=accessdocumentdeliverySETmethod=mail@id=1")

    assert_equal "access_document_delivery", statement.table
    assert_equal "method=mail", statement.set
  end

  test "reads null tests, id lists and comparisons" do
    assert_equal({ "id" => 9 }, parse("=timesheet.offduty=NOW()@id=9&offdutyISNULL").ids)
    assert_empty parse("=timesheet.offduty=NOW()@offdutyISNULL&idin(13149,13144)").ids
    assert_equal({ "id" => 15946 }, parse("=slot.signedup=signedup+1@id=15946&signedup<max").ids)
    assert_nil parse("=slot.signedup=signedup+1@id=15946&signedup<<max")
  end

  test "reads a WHERE clause of flags joined by OR, and a function of a column" do
    flags = parse("=person.assetauthorized=0,vehiclepaperwork=0@assetauthorizedORvehiclepaperwork")
    function = parse("=slot.active=TRUE@positionid=99&YEAR(begins)=2018")

    assert_equal "assetauthorizedORvehiclepaperwork", flags.where
    assert_empty flags.ids
    assert_equal({ "positionid" => 99 }, function.ids)
    assert_equal "year(timestamp)<2018", parse("-personmessage@year(timestamp)<2018").where
  end

  test "an empty value is a value, except where an id was expected" do
    assert_equal({ "id" => 420 }, parse("=person.status=dismissed@id=420&status=").ids)
    assert_nil parse("=person.status=dismissed@id=")
  end

  test "a parenthesised group is one condition that names nothing" do
    statement = parse("=`person`.`password`='[hidden]':bbb,`tpassword`='[hidden]'tpasswordexpire`=1@id=4637&((password='[hidden]':327c)OR(tpassword='[hidden]':014d)OR(password='[hidden]'))LIMIT1")

    assert_equal "person", statement.table
    assert_equal({ "id" => 4637 }, statement.ids)
    assert_equal "id=4637&((password='[hidden]':327c)OR(tpassword='[hidden]':014d)OR(password='[hidden]'))", statement.where
    assert_nil parse("=person.status=alpha@id=5&((status=x)")
  end

  test "a WHERE left whole by the shorthand starts the clause, past the nested selects" do
    statement = parse("=broadcastSETretryat=NOW(),smsfailed=(SELECTcount(*)FROMbroadcastmessage@broadcastid=57&status=fail)WHEREid=57")

    assert_equal "retryat=NOW(),smsfailed=(SELECTcount(*)FROMbroadcastmessage@broadcastid=57&status=fail)", statement.set
    assert_equal({ "id" => 57 }, statement.ids)
  end

  test "reads the 2018 statements with their double-quoted values" do
    statement = parse('+timesheetlog.action="signon",personid=1265,createpersonid=1287,message="forced",timesheetid=35666')

    assert_equal({ "personid" => 1265, "createpersonid" => 1287, "timesheetid" => 35666 }, statement.ids)
    assert_equal({ "id" => 4 }, parse('=broadcastmessage.status="sent"@id=4').ids)
  end

  test "reads a delete and its conditions" do
    statement = parse("-personslot@personid=422&slotid=216")

    assert_equal %w[delete person_slot], [statement.operation, statement.table]
    assert_equal({ "personid" => 422, "slotid" => 216 }, statement.ids)
    assert_nil statement.set
  end

  test "stays unknown where the shape is not one the grammar knows" do
    assert_nil parse("=traineestatus.passed=0,notes=@id=LIMIT1")
    assert_nil parse("-personposition@personidIN(SELECTpersonidFROMperson@status=bonked)")
    assert_nil parse("=broadcastSETretryat=NOW(),sentat=(SELECT1)")
    assert_nil parse("-person")
    assert_nil parse("+widget(a)(1)")
    assert_nil parse("#login rangers")
  end
end
