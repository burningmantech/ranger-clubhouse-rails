# frozen_string_literal: true

require "test_helper"

# Synthetic statements only: the log is personal data and never enters test/.
class LegacyLog::ParserTest < ActiveSupport::TestCase
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

  test "a plus at the start of a value is left alone" do
    event = '=person.address="+19715551234"@id=5'

    assert_equal [event, false], LegacyLog::Parser.normalize(event)
  end

  test "a statement with no marker is returned as it is" do
    assert_equal ["=person.status=alpha@id=1", false], LegacyLog::Parser.normalize("=person.status=alpha@id=1")
  end

  test "names a statement's family by operation and Classic table" do
    assert_equal "update person", LegacyLog::Parser.family("=person.status=alpha@id=1")
    assert_equal "insert person_slot", LegacyLog::Parser.family("+personslot(personid,slotid)(1,2)")
    assert_equal "delete person_position", LegacyLog::Parser.family("-personposition@personid=1&positionid=2")
    assert_equal "insert trainee_status", LegacyLog::Parser.family("+`traineestatus`(personid)(1)")
    assert_equal "update access_document_delivery",
                 LegacyLog::Parser.family("=accessdocumentdeliverySETmethod=mail@id=1")
  end

  test "a table the first Clubhouse never had is named in parentheses, and a non-statement has no family" do
    assert_equal "insert (widget)", LegacyLog::Parser.family("+widget(a)(1)")
    assert_nil LegacyLog::Parser.family("#login rangers")
    assert_nil LegacyLog::Parser.family("")
  end
end
