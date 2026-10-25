# frozen_string_literal: true

require "test_helper"

class Vc::HandleCheckerHelperTest < ActionView::TestCase
  include Vc::HandleCheckerHelper
  include UiComponents::BadgeHelper
  include IconHelper

  def conflict(priority, parts: ["conflicts"], rule_id: "substring", handle: nil)
    HandleChecker::Conflict.new(candidate_name: "Hubcap", parts:, priority:, rule_id:,
                                conflicting_handle: handle)
  end

  def handle(name = "Hubcap", entity_type = "active ranger", person_id: 42, vintage: false, reason: nil)
    HandleChecker::Handle.new(name:, entity_type:, person_id:, vintage:, reason:)
  end

  test "handle type labels use the reservation label" do
    assert_equal "Slur", handle_checker_type_label(HandleReservation::TYPE_SLUR)
  end

  test "handle type labels show a callsign status as-is" do
    assert_equal "active ranger", handle_checker_type_label("active ranger")
  end

  test "rule names come from the rule classes" do
    assert_equal "Substring", handle_checker_rule_name("substring")
    assert_equal "Experimental eye rhymes", handle_checker_rule_name("experimental-eye-rhyme")
  end

  test "a clear handle reads as no conflicts" do
    assert_equal "No conflicts found.", handle_checker_result_summary([])
    assert_equal :success, handle_checker_result_variant([])
    assert_equal "circle-check", handle_checker_result_icon([])
  end

  test "a serious conflict is counted out and styled as an error" do
    conflicts = [conflict(HandleChecker::PRIORITY_HIGH), conflict(HandleChecker::PRIORITY_MEDIUM)]

    assert_equal "2 conflicts found, 1 of them serious.", handle_checker_result_summary(conflicts)
    assert_equal :error, handle_checker_result_variant(conflicts)
    assert_equal "triangle-exclamation", handle_checker_result_icon(conflicts)
  end

  test "conflicts without a serious one are styled as a warning" do
    conflicts = [conflict(HandleChecker::PRIORITY_MEDIUM)]

    assert_equal "1 conflict found.", handle_checker_result_summary(conflicts)
    assert_equal :warning, handle_checker_result_variant(conflicts)
  end

  test "conflict counts are delimited" do
    conflicts = Array.new(1626) { conflict(HandleChecker::PRIORITY_MEDIUM) }

    assert_equal "1,626 conflicts found.", handle_checker_result_summary(conflicts)
  end

  test "conflicts are capped and the overflow is spelled out" do
    conflicts = Array.new(1626) { conflict(HandleChecker::PRIORITY_MEDIUM) }

    assert_equal Vc::HandleCheckerForm::MAX_CONFLICTS, handle_checker_shown_conflicts(conflicts).size
    assert_match(/Showing the 50 most serious of 1,626 conflicts/, handle_checker_overflow_note(conflicts))
  end

  test "no overflow note when everything is shown" do
    assert_nil handle_checker_overflow_note([conflict(HandleChecker::PRIORITY_MEDIUM)])
    assert_nil handle_checker_overflow_note([])
  end

  # -- Inline conflict lines ------------------------------------------------

  def sounds_like(handle_record, priority: HandleChecker::PRIORITY_MEDIUM)
    conflict(priority,
             parts: ["may sound like ", HandleChecker::HANDLE_NAME],
             rule_id: "double-metaphone",
             handle: handle_record)
  end

  test "a conflict line reads as description, type, priority and rule" do
    line = handle_checker_conflict_line(sounds_like(handle))

    assert_equal "may sound like Hubcap active ranger medium priority • Double Metaphone",
                 Nokogiri::HTML5.fragment(line).text.squish
  end

  test "a person's callsign is linked inside the description" do
    line = handle_checker_conflict_line(sounds_like(handle))
    link = Nokogiri::HTML5.fragment(line).at_css("a")

    assert_equal "Hubcap", link.text
    assert_equal person_path(42), link["href"]
  end

  test "a reserved handle's name is not linked" do
    reserved = handle("Testslur", HandleReservation::TYPE_SLUR, person_id: nil)

    line = handle_checker_conflict_line(sounds_like(reserved))

    assert_nil Nokogiri::HTML5.fragment(line).at_css("a")
    assert_match "Testslur", Nokogiri::HTML5.fragment(line).text
  end

  # "Boilermaker contains Boiler" holds the conflicting name twice; only the
  # segment the rule marked may be linked.
  test "only the conflicting handle's own name is linked" do
    boiler = handle("Boiler")
    ambiguous = conflict(HandleChecker::PRIORITY_MEDIUM,
                         parts: ["Boilermaker contains ", HandleChecker::HANDLE_NAME],
                         handle: boiler)

    fragment = Nokogiri::HTML5.fragment(handle_checker_conflict_line(ambiguous))

    assert_equal "Boilermaker contains Boiler", fragment.text.split(/\s+(?=active ranger)/).first
    assert_equal 1, fragment.css("a").count
    assert_equal "Boiler", fragment.at_css("a").text
    # The link must sit after "contains", not inside "Boilermaker".
    assert_match(/contains <a/, handle_checker_conflict_line(ambiguous))
  end

  test "a high priority conflict says so in words" do
    line = handle_checker_conflict_line(sounds_like(handle, priority: HandleChecker::PRIORITY_HIGH))

    assert_match "high priority", Nokogiri::HTML5.fragment(line).text
  end

  test "a vintage callsign is called out on the line" do
    line = handle_checker_conflict_line(sounds_like(handle("Hubcap", vintage: true)))

    assert_match "Vintage", Nokogiri::HTML5.fragment(line).text
  end

  test "a conflict without a handle still lists priority and rule" do
    line = handle_checker_conflict_line(conflict(HandleChecker::PRIORITY_HIGH,
                                                 parts: ["might be too short"],
                                                 rule_id: "min-length"))

    assert_equal "might be too short high priority • Minimum length",
                 Nokogiri::HTML5.fragment(line).text.squish
  end

  test "description segments are escaped" do
    nasty = handle("<script>alert(1)</script>", person_id: nil)

    line = handle_checker_conflict_line(sounds_like(nasty))

    assert_no_match(/<script>/, line)
  end
end
