# frozen_string_literal: true

require "test_helper"

class Vc::HandleCheckerHelperTest < ActionView::TestCase
  include Vc::HandleCheckerHelper
  include UiComponents::BadgeHelper
  include IconHelper
  include ApplicationHelper

  def conflict(priority, parts: ["conflicts"], rule_id: "substring", handle: nil)
    HandleChecker::Conflict.new(candidate_name: "Hubcap", parts:, priority:, rule_id:,
                                conflicting_handle: handle)
  end

  def handle(name = "Hubcap", entity_type = "active ranger", person_id: 42, vintage: false, reason: nil)
    HandleChecker::Handle.new(name:, entity_type:, person_id:, vintage:, reason:)
  end

  def sounds_like(handle_record, priority: HandleChecker::PRIORITY_MEDIUM, rule_id: "double-metaphone")
    conflict(priority,
             parts: ["may sound like ", HandleChecker::HANDLE_NAME],
             rule_id:,
             handle: handle_record)
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
  end

  test "a serious conflict is counted out" do
    conflicts = [conflict(HandleChecker::PRIORITY_HIGH), conflict(HandleChecker::PRIORITY_MEDIUM)]

    assert_equal "2 conflicts found, 1 of them serious.", handle_checker_result_summary(conflicts)
  end

  test "conflicts without a serious one are only counted" do
    assert_equal "1 conflict found.", handle_checker_result_summary([conflict(HandleChecker::PRIORITY_MEDIUM)])
  end

  test "conflict counts are delimited" do
    conflicts = Array.new(1626) { conflict(HandleChecker::PRIORITY_MEDIUM) }

    assert_equal "1,626 conflicts found.", handle_checker_result_summary(conflicts)
  end

  test "conflicts are capped and the overflow is spelled out" do
    conflicts = Array.new(1626) { conflict(HandleChecker::PRIORITY_MEDIUM) }

    assert_equal Vc::HandleCheckerForm::MAX_CONFLICTS, handle_checker_shown_conflicts(conflicts).size
    assert_equal "Showing the #{Vc::HandleCheckerForm::MAX_CONFLICTS} most serious. " \
                 "Switch off a rule above to narrow this down.",
                 handle_checker_overflow_note(conflicts)
  end

  test "no overflow note when everything is shown" do
    assert_nil handle_checker_overflow_note([conflict(HandleChecker::PRIORITY_MEDIUM)])
    assert_nil handle_checker_overflow_note([])
  end

  # -- Rule runs -------------------------------------------------------------

  test "a rule's run of rows is spanned from its first row" do
    conflicts = [
      sounds_like(handle, rule_id: "american-soundex"),
      sounds_like(handle("Other"), rule_id: "double-metaphone"),
      sounds_like(handle("Third"), rule_id: "double-metaphone")
    ]

    runs = handle_checker_rule_runs(conflicts)

    assert_equal conflicts, runs.map(&:first)
    assert_equal [1, 2, nil], runs.map(&:last)
  end

  test "rule runs stop at the conflict cap" do
    conflicts = Array.new(Vc::HandleCheckerForm::MAX_CONFLICTS + 5) { conflict(HandleChecker::PRIORITY_MEDIUM) }

    runs = handle_checker_rule_runs(conflicts)

    assert_equal Vc::HandleCheckerForm::MAX_CONFLICTS, runs.size
    assert_equal Vc::HandleCheckerForm::MAX_CONFLICTS, runs.first.last
  end

  # -- Descriptions ----------------------------------------------------------

  test "a person's callsign is linked inside the description" do
    link = Nokogiri::HTML5.fragment(handle_checker_description(sounds_like(handle))).at_css("a")

    assert_equal "Hubcap", link.text
    assert_equal person_path(42), link["href"]
  end

  test "a reserved handle's name is not linked" do
    reserved = handle("Testslur", HandleReservation::TYPE_SLUR, person_id: nil)

    fragment = Nokogiri::HTML5.fragment(handle_checker_description(sounds_like(reserved)))

    assert_nil fragment.at_css("a")
    assert_match "Testslur", fragment.text
  end

  # "Boilermaker contains Boiler" holds the conflicting name twice; only the
  # segment the rule marked may be linked.
  test "only the conflicting handle's own name is linked" do
    boiler = handle("Boiler")
    ambiguous = conflict(HandleChecker::PRIORITY_MEDIUM,
                         parts: ["Boilermaker contains ", HandleChecker::HANDLE_NAME],
                         handle: boiler)

    description = handle_checker_description(ambiguous)
    fragment = Nokogiri::HTML5.fragment(description)

    assert_equal "Boilermaker contains Boiler", fragment.text
    assert_equal 1, fragment.css("a").count
    assert_equal "Boiler", fragment.at_css("a").text
    # The link must sit after "contains", not inside "Boilermaker".
    assert_match(/contains <a/, description)
  end

  test "a conflict without a handle reads as its description and has no type" do
    short = conflict(HandleChecker::PRIORITY_HIGH, parts: ["might be too short"], rule_id: "min-length")

    assert_equal "might be too short", handle_checker_description(short)
    assert_equal "—", handle_checker_type_badges(short.conflicting_handle)
  end

  test "description segments are escaped" do
    nasty = handle("<script>alert(1)</script>", person_id: nil)

    assert_no_match(/<script>/, handle_checker_description(sounds_like(nasty)))
  end

  # -- Type and priority -----------------------------------------------------

  test "a handle's type is a badge" do
    assert_equal "active ranger", Nokogiri::HTML5.fragment(handle_checker_type_badges(handle)).text.squish
  end

  test "a vintage callsign is called out beside its type" do
    badges = handle_checker_type_badges(handle("Hubcap", vintage: true))

    assert_equal "active ranger Vintage", Nokogiri::HTML5.fragment(badges).text.squish
  end

  test "priority is said in words and styled by level" do
    high = handle_checker_priority_text(HandleChecker::PRIORITY_HIGH)

    assert_equal "high", Nokogiri::HTML5.fragment(high).text
    assert_match "text-error", high
    assert_match "text-warning", handle_checker_priority_text(HandleChecker::PRIORITY_MEDIUM)
  end
end
