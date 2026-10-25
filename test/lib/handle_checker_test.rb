# frozen_string_literal: true

require "test_helper"

class HandleCheckerTest < ActiveSupport::TestCase
  RANGER = "active ranger"

  def handle(name, entity_type = RANGER, vintage: false, person_id: 1, reason: nil)
    HandleChecker::Handle.new(name:, entity_type:, person_id:, vintage:, reason:)
  end

  def checker(*handles)
    HandleChecker.new(handles.flatten)
  end

  # Conflict descriptions for a name, so tests read like the UI.
  def descriptions(checker, name, **options)
    checker.check(name, **options).map(&:description)
  end

  def phonetic_alphabet
    %w[Alpha Bravo Charlie Tango].map do |word|
      handle(word, HandleReservation::TYPE_PHONETIC_ALPHABET, person_id: nil)
    end
  end

  # Rules that report a conflict for nearly every name drown out the rule under
  # test, so each test opts in to the rules it cares about.
  def only(*rule_ids) = { rule_ids: rule_ids.flatten }

  test "a blank handle has no conflicts" do
    check = checker(handle("Hubcap"))

    assert_empty check.check("")
    assert_empty check.check("   ")
    assert_empty check.check(nil)
  end

  # -- Substring rule ------------------------------------------------------

  test "an exact match is a high priority conflict" do
    check = checker(handle("Hubcap"))

    conflict = check.check("Hubcap", **only("substring")).sole

    assert_equal "Hubcap is already in use", conflict.description
    assert_equal HandleChecker::PRIORITY_HIGH, conflict.priority
    assert_equal "Hubcap", conflict.conflicting_handle.name
  end

  test "an exact match ignores case and punctuation" do
    check = checker(handle("Hub Cap"))

    assert_equal ["Hub Cap is already in use"], descriptions(check, "hub-cap", **only("substring"))
  end

  test "a proposed handle contained by an existing handle conflicts" do
    check = checker(handle("Boilermaker"))

    conflict = check.check("Boiler", **only("substring")).sole

    assert_equal "Boilermaker contains Boiler", conflict.description
    assert_equal HandleChecker::PRIORITY_MEDIUM, conflict.priority
  end

  test "a proposed handle containing an existing handle conflicts" do
    check = checker(handle("Boiler"))

    assert_equal ["Boilermaker contains Boiler"],
                 descriptions(check, "Boilermaker", **only("substring"))
  end

  test "a slur reports as a slur at high priority" do
    check = checker(handle("Badword", HandleReservation::TYPE_SLUR, person_id: nil))

    conflict = check.check("Badword", **only("substring")).sole

    assert_equal "Badword is a slur", conflict.description
    assert_equal HandleChecker::PRIORITY_HIGH, conflict.priority
  end

  test "an obscenity contained in a proposed handle is high priority" do
    check = checker(handle("Badword", HandleReservation::TYPE_OBSCENE, person_id: nil))

    conflict = check.check("Badwordly", **only("substring")).sole

    assert_equal "Badwordly contains the obscenity Badword", conflict.description
    assert_equal HandleChecker::PRIORITY_HIGH, conflict.priority
  end

  test "an abbreviation matches its spelled out form" do
    check = checker(handle("D P W"))

    assert_equal ["D P W is already in use"], descriptions(check, "DPW", **only("substring"))
  end

  test "an abbreviation inside a longer handle is found" do
    check = checker(handle("D P W"))

    assert_equal ["DPW Bob contains D P W"], descriptions(check, "DPW Bob", **only("substring"))
  end

  test "a lowercase word is not treated as an abbreviation" do
    check = checker(handle("LE"))

    assert_empty check.check("Sparkle", **only("substring"))
  end

  test "phonetic alphabet words are left to the phonetic alphabet rule" do
    check = checker(phonetic_alphabet)

    assert_empty check.check("Alphabet", **only("substring"))
  end

  test "a handle of only punctuation never matches" do
    check = checker(handle("!!!", HandleReservation::TYPE_UNCATEGORIZED, person_id: nil))

    assert_empty check.check("Hubcap", **only("substring"))
  end

  # -- Minimum length rule -------------------------------------------------

  test "a handle without letters should have letters" do
    conflict = checker.check("123", **only("min-length")).sole

    assert_equal "should have letters", conflict.description
    assert_equal HandleChecker::PRIORITY_MEDIUM, conflict.priority
  end

  test "a one letter handle is too short" do
    conflict = checker.check("X", **only("min-length")).sole

    assert_equal "might be too short", conflict.description
    assert_equal HandleChecker::PRIORITY_HIGH, conflict.priority
  end

  test "two capital letters are allowed as initials" do
    assert_empty checker.check("JC", **only("min-length"))
  end

  test "two lowercase letters are too short" do
    assert_equal ["might be too short"], descriptions(checker, "jc", **only("min-length"))
  end

  test "a three letter handle is long enough" do
    assert_empty checker.check("Cat", **only("min-length"))
  end

  # -- Phonetic alphabet rule ----------------------------------------------

  test "a handle of only phonetic alphabet words conflicts" do
    check = checker(phonetic_alphabet)

    conflict = check.check("Tango Charlie", **only("phonetic-alphabet")).sole

    assert_equal "consists entirely of NATO phonetic alphabet words", conflict.description
    assert_equal HandleChecker::PRIORITY_HIGH, conflict.priority
  end

  test "a handle mixing phonetic words with others does not conflict" do
    check = checker(phonetic_alphabet)

    assert_empty check.check("Tango Hubcap", **only("phonetic-alphabet"))
  end

  test "a numeric handle does not match an empty phonetic alphabet list" do
    assert_empty checker.check("123", **only("phonetic-alphabet"))
  end

  # -- Edit distance rule --------------------------------------------------

  test "a handle one edit away is spelled like the existing handle" do
    check = checker(handle("Sparkle"))

    conflict = check.check("Sparkl", **only("edit-distance")).sole

    assert_equal "is spelled like Sparkle", conflict.description
    assert_equal HandleChecker::PRIORITY_MEDIUM, conflict.priority
  end

  test "a handle two edits away is not reported" do
    check = checker(handle("Sparkle"))

    assert_empty check.check("Spark", **only("edit-distance"))
  end

  test "an identical handle is left to the substring rule" do
    check = checker(handle("Sparkle"))

    assert_empty check.check("sparkle", **only("edit-distance"))
  end

  # -- Phonetic rules ------------------------------------------------------

  test "soundex finds a handle that sounds alike" do
    check = checker(handle("Smith"))

    conflict = check.check("Smyth", **only("american-soundex")).sole

    assert_equal "may sound like Smith", conflict.description
    assert_equal HandleChecker::PRIORITY_MEDIUM, conflict.priority
  end

  test "soundex does not report the handle itself" do
    check = checker(handle("Smith"))

    assert_empty check.check("smith", **only("american-soundex"))
  end

  test "soundex ignores h and w between matching consonants" do
    check = checker(handle("Ashcraft"))

    assert_equal ["may sound like Ashcraft"], descriptions(check, "Ashcroft", **only("american-soundex"))
  end

  test "double metaphone finds a handle matching on the alternate encoding" do
    check = checker(handle("Smith"))

    assert_equal ["may sound like Smith"], descriptions(check, "Schmidt", **only("double-metaphone"))
  end

  test "double metaphone reports a handle once when both encodings match" do
    check = checker(handle("Schmidt"))

    # Schmidt and Schmitt share both the primary and the alternate encoding.
    assert_equal ["may sound like Schmidt"], descriptions(check, "Schmitt", **only("double-metaphone"))
  end

  test "double metaphone ignores handles it cannot encode" do
    check = checker(handle("123"))

    assert_empty check.check("456", **only("double-metaphone"))
  end

  # -- Eye rhyme rules -----------------------------------------------------

  test "eye rhyme reports a single rhyming syllable" do
    check = checker(handle("Hubcap"))

    conflict = check.check("Madcap", **only("eye-rhyme")).sole

    assert_equal "has a syllable rhyming with Hubcap", conflict.description
    assert_equal HandleChecker::PRIORITY_MEDIUM, conflict.priority
  end

  test "eye rhyme counts multiple rhyming syllables" do
    check = checker(handle("Hubcap"))

    assert_equal ["shares 2 rhyming syllables with Hubcap"],
                 descriptions(check, "Cap Hub", **only("eye-rhyme"))
  end

  test "eye rhyme counts a repeated rhyme once per pairing" do
    check = checker(handle("Big Wig"))

    # Big Wig rhymes with itself, so each of its two syllables is counted
    # against each of the proposed handle's two. Carried over from the Ember
    # rule, which notes the double counting as a known flaw.
    assert_equal ["shares 4 rhyming syllables with Big Wig"],
                 descriptions(check, "Twig Sprig", **only("eye-rhyme"))
  end

  test "experimental eye rhyme ignores names below the rhyme ratio" do
    check = checker(handle("Hubcap"))

    # One rhyming syllable out of three is under the one half threshold.
    assert_empty check.check("Madcap Bonanza", **only("experimental-eye-rhyme"))
    assert_not_empty check.check("Madcap Bonanza", **only("eye-rhyme"))
  end

  test "eye rhyme treats a silent e as part of the rime" do
    check = checker(handle("Bake"))

    assert_not_empty check.check("Cake", **only("eye-rhyme"))
    assert_empty check.check("Back", **only("eye-rhyme"))
  end

  test "eye rhyme collapses doubled consonants" do
    check = checker(handle("Barbel"))

    assert_not_empty check.check("Bar Bell", **only("eye-rhyme"))
  end

  test "eye rhyme splits camel case into words" do
    check = checker(handle("Hub Cap"))

    assert_not_empty check.check("MadCap", **only("eye-rhyme"))
  end

  test "eye rhyme ignores a handle with no letters" do
    check = checker(handle("Hubcap"))

    assert_empty check.check("123", **only("eye-rhyme"))
  end

  test "eye rhyme handles a name that is one long consonant cluster" do
    check = checker(handle("Hubcap"))

    assert_nothing_raised { check.check("Tsktsk", **only("eye-rhyme")) }
  end

  # -- Sorting and filtering -----------------------------------------------

  test "conflicts sort by priority then substring first then rule" do
    check = checker(handle("Hubcap"), handle("Hubcaps"))

    conflicts = check.check("Hubcap")

    assert_equal HandleChecker::PRIORITY_HIGH, conflicts.first.priority
    assert_equal "substring", conflicts.first.rule_id
    assert_equal conflicts.map(&:sort_key).sort, conflicts.map(&:sort_key)
  end

  test "a disabled rule reports nothing" do
    check = checker(handle("Hubcap"))

    assert_empty check.check("Hubcap", **only("min-length"))
    assert_not_empty check.check("Hubcap", **only("substring"))
  end

  test "an entity type filter hides conflicts from other types" do
    check = checker(handle("Hubcap", "retired ranger"))

    assert_empty check.check("Hubcap", entity_types: [RANGER], include_vintage: false)
    assert_not_empty check.check("Hubcap", entity_types: ["retired ranger"], include_vintage: false)
  end

  test "a vintage handle is reported even when its entity type is hidden" do
    check = checker(handle("Hubcap", "retired ranger", vintage: true))

    assert_not_empty check.check("Hubcap", entity_types: [RANGER], include_vintage: true)
    assert_empty check.check("Hubcap", entity_types: [RANGER], include_vintage: false)
  end

  test "conflicts without a conflicting handle survive entity type filters" do
    assert_equal ["might be too short"],
                 descriptions(checker, "X", entity_types: [], include_vintage: false)
  end

  # -- Entity types and labels ---------------------------------------------

  test "entity types list callsign statuses before reserved handle types" do
    check = checker(handle("Hubcap", "retired ranger"), handle("Boiler", RANGER),
                    handle("Badword", HandleReservation::TYPE_SLUR, person_id: nil))

    assert_equal [RANGER, "retired ranger", HandleReservation::TYPE_SLUR], check.entity_types
  end

  test "eye rhymes are the only rule off by default" do
    assert_equal HandleChecker.rule_ids - ["eye-rhyme"], HandleChecker.default_rule_ids
  end

  test "past prospective is the only status off by default" do
    assert_equal Person::ALL_STATUSES - [Person::PAST_PROSPECTIVE], HandleChecker::DEFAULT_CHECKED_STATUSES
  end

  test "default entity types drop past prospective callsigns but keep reserved handles" do
    check = checker(handle("Boiler", RANGER),
                    handle("Hubcap", "past prospective ranger"),
                    handle("Badword", HandleReservation::TYPE_SLUR, person_id: nil))

    assert_equal [RANGER, HandleReservation::TYPE_SLUR], check.default_entity_types
    assert_includes check.entity_types, "past prospective ranger"
  end

  # -- Handle pool ---------------------------------------------------------

  test "the handle pool includes callsigns and active reservations" do
    handles = HandleChecker.build_handles
    ranger = person(:active_ranger)

    callsign = handles.find { |handle| handle.person_id == ranger.id }

    assert_equal ranger.callsign, callsign.name
    assert_equal "#{ranger.status} ranger", callsign.entity_type
    assert_includes handles.map(&:name), handle_reservation(:slur).handle
  end

  test "the handle pool excludes expired reservations" do
    expired = HandleReservation.create!(handle: "Expiredword",
                                        reservation_type: HandleReservation::TYPE_UNCATEGORIZED,
                                        expires_on: Current.today - 1.day)

    assert_not_includes HandleChecker.build_handles.map(&:name), expired.handle
  end
end
