# frozen_string_literal: true

require "test_helper"

class LanguagesKnownReportTest < ActiveSupport::TestCase
  setup do
    Current.reset
    PersonLanguage.delete_all

    @on_site = person(:active_ranger)          # TestRanger, active
    @also_on_site = person(:ranger_with_custom_gender) # CustomGender, active
    @retired = person(:retired_ranger)         # RetiredRanger, retired
    @bonked = person(:bonked_ranger)           # BonkedTest, bonked
    @away = person(:plate_collision_ranger)    # RANGER1, active

    [@on_site, @also_on_site, @retired, @bonked].each { |p| p.update!(on_site: true) }
    @away.update!(on_site: false)
  end

  teardown do
    Current.reset
  end

  # --- who is counted -------------------------------------------------------

  test "a language is listed with everyone on site who speaks it" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_FLUENT)
    speaks(@also_on_site, "French", PersonLanguage::PROFICIENCY_BASIC)

    french = find("French")
    assert_equal 2, french.speaker_count
    assert_equal ["CustomGender", "TestRanger"], french.speakers.map(&:callsign)
  end

  test "someone who is not on site is left out of the on site list" do
    speaks(@away, "French")

    assert_nil find_on_site("French")
    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON).languages
  end

  test "someone whose status is not active is left out" do
    speaks(@bonked, "French")
    speaks(@retired, "French")

    assert_equal ["RetiredRanger"], find("French").speakers.map(&:callsign)
  end

  test "a record whose person is gone is left out" do
    speaks(@on_site, "French")
    PersonLanguage.where(person_id: @on_site.id).update_all(person_id: 0)

    assert_nil find("French")
  end

  # --- grouping -------------------------------------------------------------

  test "a language typed in by hand is listed as other" do
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "Klingon")

    result = LanguagesKnownReport.execute
    assert_empty result.common
    assert_equal ["Klingon"], result.other.map(&:name)
  end

  test "a language from the list is listed as common" do
    speaks(@on_site, "French")

    result = LanguagesKnownReport.execute
    assert_equal ["French"], result.common.map(&:name)
    assert_empty result.other
  end

  test "the same language spelled differently becomes one language" do
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "klingon")
    speaks(@also_on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: " Klingon ")

    result = LanguagesKnownReport.execute
    assert_equal 1, result.language_count
    assert_equal 2, result.other.first.speaker_count
  end

  test "a typed-in language matching the standard list joins the common one" do
    speaks(@on_site, "French")
    speaks(@also_on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "french")

    result = LanguagesKnownReport.execute
    assert_empty result.other
    assert_equal 1, result.language_count
    # The spelling the form offers wins the name.
    assert_equal "French", result.common.first.name
    assert_equal 2, result.common.first.speaker_count
  end

  test "one person listing a language twice is counted once" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_FLUENT)
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, PersonLanguage::PROFICIENCY_BASIC, custom: "French")

    assert_equal 1, find("French").speaker_count
  end

  # The two records share a callsign, so nothing about the order they arrive in
  # decides which level is kept. Without a rule, a fluent speaker reads as
  # someone who knows a few words.
  test "one person listing a language twice keeps the level they are surest of" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_BASIC)
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, PersonLanguage::PROFICIENCY_FLUENT, custom: "french")

    french = find("French")
    assert_equal [PersonLanguage::PROFICIENCY_FLUENT], french.speakers.map(&:proficiency)
    assert_equal 1, french.count_of(PersonLanguage::PROFICIENCY_FLUENT)
    assert_equal 0, french.count_of(PersonLanguage::PROFICIENCY_BASIC)
  end

  test "the surest level wins whichever record is stored first" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_FLUENT)
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, PersonLanguage::PROFICIENCY_BASIC, custom: "french")

    assert_equal [PersonLanguage::PROFICIENCY_FLUENT], find("French").speakers.map(&:proficiency)
  end

  test "a level no one set loses to any stated level" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_UNKNOWN)
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, PersonLanguage::PROFICIENCY_BASIC, custom: "french")

    assert_equal [PersonLanguage::PROFICIENCY_BASIC], find("French").speakers.map(&:proficiency)
  end

  test "speakers stay in callsign order after duplicates are folded together" do
    speaks(@also_on_site, "French", PersonLanguage::PROFICIENCY_BASIC)
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_BASIC)
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, PersonLanguage::PROFICIENCY_FLUENT, custom: "french")

    assert_equal ["CustomGender", "TestRanger"], find("French").speakers.map(&:callsign)
  end

  test "languages come back in alphabetical order regardless of case" do
    speaks(@on_site, "Spanish")
    speaks(@on_site, "French")
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "asturian")
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "Zulu")

    result = LanguagesKnownReport.execute
    assert_equal %w[French Spanish], result.common.map(&:name)
    assert_equal %w[asturian Zulu], result.other.map(&:name)
  end

  # --- counts ---------------------------------------------------------------

  test "people are counted once even when they speak several languages" do
    speaks(@on_site, "French")
    speaks(@on_site, "Spanish")
    speaks(@also_on_site, "French")

    result = LanguagesKnownReport.execute
    assert_equal 2, result.language_count
    assert_equal 2, result.people_count
  end

  test "a language counts its speakers by how well they speak it" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_FLUENT)
    speaks(@also_on_site, "French", PersonLanguage::PROFICIENCY_BASIC)
    speaks(@retired, "French", PersonLanguage::PROFICIENCY_BASIC)

    french = find("French")
    assert_equal 1, french.count_of(PersonLanguage::PROFICIENCY_FLUENT)
    assert_equal 2, french.count_of(PersonLanguage::PROFICIENCY_BASIC)
    assert_equal 0, french.count_of(PersonLanguage::PROFICIENCY_INTERMEDIATE)
  end

  test "a level no one set reads as not stated" do
    speaks(@on_site, "French", PersonLanguage::PROFICIENCY_UNKNOWN)

    assert_equal "Not Stated", find("French").speakers.first.proficiency_label
  end

  # --- lookup ---------------------------------------------------------------

  test "a language is found without regard to case or spacing" do
    speaks(@on_site, "French")

    assert_equal "French", LanguagesKnownReport.find_language("  fRenCh ")&.name
  end

  test "a language no one speaks is not found" do
    speaks(@on_site, "French")

    assert_nil LanguagesKnownReport.find_language("Spanish")
    assert_nil LanguagesKnownReport.find_language("")
    assert_nil LanguagesKnownReport.find_language(nil)
  end

  # --- what a speaker is doing right now ------------------------------------

  test "someone on a shift is marked on duty with the shift they are on" do
    speaks(@on_site, "French")
    start_shift(@on_site)

    speaker = find("French").speakers.first
    assert_predicate speaker, :on_duty?
    assert_equal positions(:ood_position).title, speaker.position
    assert_equal 1, find("French").on_duty_count
  end

  test "someone whose shift has ended is not on duty" do
    speaks(@on_site, "French")
    start_shift(@on_site, off_duty: Time.zone.local(Current.year, 8, 28, 16))

    speaker = find("French").speakers.first
    assert_not_predicate speaker, :on_duty?
    assert_nil speaker.position
    assert_equal 0, find("French").on_duty_count
  end

  # An entry left open in a past year is a mistake in the records, not somebody
  # standing out there right now.
  test "a shift left open in an earlier year does not count as on duty" do
    speaks(@on_site, "French")
    start_shift(@on_site, on_duty: Time.zone.local(Current.year - 1, 8, 28, 10))

    assert_not_predicate find("French").speakers.first, :on_duty?
  end

  test "someone listed on two open shifts is still one speaker" do
    speaks(@on_site, "French")
    start_shift(@on_site)
    start_shift(@on_site, position: positions(:mentor_lead))

    french = find("French")
    assert_equal 1, french.speaker_count
    assert_equal 1, french.on_duty_count
  end

  test "someone holding a radio is marked as carrying one" do
    speaks(@on_site, "French")
    check_out_radio(@on_site)

    assert_predicate find("French").speakers.first, :radio?
    assert_equal 1, find("French").radio_count
  end

  test "a radio that has been handed back does not count" do
    speaks(@on_site, "French")
    check_out_radio(@on_site, checked_in: Current.time)

    assert_not_predicate find("French").speakers.first, :radio?
  end

  test "checking out something that is not a radio does not count" do
    speaks(@on_site, "French")
    check_out_radio(@on_site, asset: asset(:gear_no_description))

    assert_not_predicate find("French").speakers.first, :radio?
  end

  # What kind of thing it is decides this, not what it is called. A base station
  # described as a radio is not something a reader can raise somebody on.
  test "a base station described as a radio does not count" do
    speaks(@on_site, "French")
    check_out_radio(@on_site, asset: asset(:desktop_radio))

    assert_not_predicate find("French").speakers.first, :radio?
  end

  # The reader is looking for somebody to go get. Whoever is standing a shift
  # comes first, then whoever can be raised on the radio.
  test "speakers are listed by how easily they can be reached" do
    speaks(@on_site, "French")        # TestRanger -- radio
    speaks(@also_on_site, "French")   # CustomGender -- on a shift
    speaks(@retired, "French")        # RetiredRanger -- neither
    check_out_radio(@on_site)
    start_shift(@also_on_site)

    assert_equal %w[CustomGender TestRanger RetiredRanger], find("French").speakers.map(&:callsign)
  end

  # --- searching by name ----------------------------------------------------

  test "a search matches part of a language name" do
    speaks(@on_site, "Spanish")
    speaks(@on_site, "French")

    result = LanguagesKnownReport.execute(query: "pani")
    assert_equal ["Spanish"], result.languages.map(&:name)
  end

  test "a search matches a language somebody typed in" do
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "Klingon")

    assert_equal ["Klingon"], LanguagesKnownReport.execute(query: "kling").languages.map(&:name)
  end

  # Typed-in languages are stored under a marker name. Searching for that marker
  # must not hand back every typed-in language at once.
  test "searching for the marker used by typed-in languages finds nothing" do
    speaks(@on_site, PersonLanguage::LANGUAGE_NAME_CUSTOM, custom: "Klingon")

    assert_empty LanguagesKnownReport.execute(query: PersonLanguage::LANGUAGE_NAME_CUSTOM).languages
  end

  test "a search reaches a language only spoken by someone who is away" do
    speaks(@away, "French")

    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON).languages

    french = LanguagesKnownReport.execute(query: "french").languages.first
    assert_equal 1, french.speaker_count
    assert_equal 0, french.on_site_count
    assert_predicate french, :off_site_only?
  end

  # The filter says who counts, and searching does not talk it out of that.
  test "a search is still held to the people the filter covers" do
    speaks(@away, "French")

    assert_empty LanguagesKnownReport.execute(query: "french",
                                              site: LanguagesKnownReport::SITE_ON).languages
    assert_empty LanguagesKnownReport.execute(query: "french",
                                              site: LanguagesKnownReport::SITE_ON_DUTY).languages
  end

  test "a search still leaves out someone whose status is not active" do
    speaks(@bonked, "French")

    assert_empty LanguagesKnownReport.execute(query: "french",
                                              site: LanguagesKnownReport::SITE_EVERYONE).languages
  end

  test "a search counts everyone it lists" do
    speaks(@on_site, "French")
    speaks(@away, "French")

    result = LanguagesKnownReport.execute(query: "french", site: LanguagesKnownReport::SITE_EVERYONE)
    assert_equal 2, result.people_count
    assert_equal 2, result.languages.first.speaker_count
  end

  test "searching for nothing lists everything the filter covers" do
    speaks(@on_site, "French")
    speaks(@away, "Spanish")

    assert_equal ["French"],
                 LanguagesKnownReport.execute(query: "  ", site: LanguagesKnownReport::SITE_ON)
                                     .languages.map(&:name)
  end

  test "a search can be held to the people on site" do
    speaks(@on_site, "French")
    speaks(@away, "Spanish")

    result = LanguagesKnownReport.execute(query: "s", site: LanguagesKnownReport::SITE_ON)
    assert_empty result.languages
  end

  # --- filtering by where people are ----------------------------------------

  test "the list holds everybody by default" do
    speaks(@on_site, "French")
    speaks(@away, "Spanish")

    result = LanguagesKnownReport.execute
    assert_equal %w[French Spanish], result.languages.map(&:name)
    assert_equal 2, result.people_count
  end

  test "the list can be held to the people on site" do
    speaks(@on_site, "French")
    speaks(@away, "Spanish")

    result = LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON)
    assert_equal ["French"], result.languages.map(&:name)
    assert_equal 1, result.people_count
  end

  test "the list can be held to the people who are away" do
    speaks(@on_site, "French")
    speaks(@away, "Spanish")

    result = LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_OFF)
    assert_equal ["Spanish"], result.languages.map(&:name)
    assert_equal [false], result.languages.first.speakers.map(&:on_site?)
  end

  test "asking for the people who are away still leaves out anyone not active" do
    speaks(@bonked, "French")
    @bonked.update!(on_site: false)

    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_OFF).languages
  end

  test "one language counts the same people the list did" do
    speaks(@on_site, "French")
    speaks(@away, "French")

    assert_equal ["TestRanger"], find_on_site("French").speakers.map(&:callsign)
    assert_equal ["RANGER1"],
                 LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_OFF)
                                     .speakers.map(&:callsign)

    everyone = find("French")
    assert_equal 2, everyone.speaker_count
    assert_equal 1, everyone.on_site_count
    assert_equal 1, everyone.off_site_count
  end

  test "a language no one on site speaks is still found by default" do
    speaks(@away, "French")

    assert_nil find_on_site("French")
    assert_equal 1, find("French").speaker_count
    assert_equal 1, LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_OFF).speaker_count
  end

  # Someone who is here can be fetched; someone who is away cannot. The list
  # says so by putting everyone here first, whatever their callsign.
  test "speakers who are away are listed after everyone who is here" do
    speaks(@also_on_site, "French") # CustomGender, here
    speaks(@away, "French")         # RANGER1, away -- sorts first by callsign

    french = LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_EVERYONE)
    assert_equal %w[CustomGender RANGER1], french.speakers.map(&:callsign)
    assert_equal [true, false], french.speakers.map(&:on_site?)
  end

  test "the list can be held to the people on a shift right now" do
    speaks(@on_site, "French")
    speaks(@also_on_site, "Spanish")
    start_shift(@on_site)

    result = LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON_DUTY)
    assert_equal ["French"], result.languages.map(&:name)
    assert_equal 1, result.people_count
    assert_equal 1, result.languages.first.on_duty_count
  end

  test "someone whose shift has ended is left out of the on duty list" do
    speaks(@on_site, "French")
    start_shift(@on_site, off_duty: Time.zone.local(Current.year, 8, 28, 16))

    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON_DUTY).languages
  end

  test "a shift left open in an earlier year does not put anyone on the on duty list" do
    speaks(@on_site, "French")
    start_shift(@on_site, on_duty: Time.zone.local(Current.year - 1, 8, 28, 10))

    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON_DUTY).languages
  end

  # The shift record is what says somebody is out there. Whether they were also
  # marked as arrived does not come into it.
  test "someone on a shift counts as on duty even when they are not marked on site" do
    speaks(@away, "French")
    start_shift(@away)

    result = LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON_DUTY)
    assert_equal ["French"], result.languages.map(&:name)
    assert_equal 1, LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_ON_DUTY)
                                        .speaker_count
  end

  test "asking for the people on duty still leaves out anyone not active" do
    speaks(@bonked, "French")
    start_shift(@bonked)

    assert_empty LanguagesKnownReport.execute(site: LanguagesKnownReport::SITE_ON_DUTY).languages
  end

  test "one language holds only its speakers on duty when asked" do
    speaks(@on_site, "French")
    speaks(@also_on_site, "French")
    start_shift(@also_on_site)

    french = LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_ON_DUTY)
    assert_equal ["CustomGender"], french.speakers.map(&:callsign)
  end

  # The column is borrowed from the person table, so it arrives as a digit. Zero
  # counts as true in Ruby, which would call everybody present.
  test "being away is read as away and not as a number" do
    speaks(@away, "French")

    speaker = LanguagesKnownReport.find_language("French", site: LanguagesKnownReport::SITE_OFF).speakers.first
    assert_equal false, speaker.on_site?
  end

  private

  def speaks(person, name, proficiency = PersonLanguage::PROFICIENCY_FLUENT, custom: nil)
    PersonLanguage.create!(person:, language_name: name, language_custom: custom, proficiency:)
  end

  def start_shift(person, position: positions(:ood_position), on_duty: nil, off_duty: nil)
    Timesheet.create!(person:, position:, off_duty:,
                      on_duty: on_duty || Time.zone.local(Current.year, 8, 28, 10),
                      additional_notes: "signed in for a test")
  end

  def check_out_radio(person, asset: asset(:radio_current_year), checked_in: nil)
    PersonAsset.create!(person:, asset:, checked_in:,
                        checked_out: Time.zone.local(Current.year, 8, 28, 9))
  end

  def find(name) = LanguagesKnownReport.find_language(name)

  def find_on_site(name) = LanguagesKnownReport.find_language(name, site: LanguagesKnownReport::SITE_ON)
end
