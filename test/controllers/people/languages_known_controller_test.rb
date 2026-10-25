# frozen_string_literal: true

require "test_helper"

class People::LanguagesKnownControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  # Two people on site speak between them: French (both), Spanish, Chinese
  # (Mandarin), and a typed-in Klingon. A third on-site person is bonked, so
  # nothing they speak should reach the page.
  setup do
    Rails.cache.clear
    Current.reset
    PersonLanguage.delete_all

    @admin = person(:echelon_ranger)
    @event_manager = person(:plate_collision_ranger)
    @vc = person(:inactive_ranger)
    @outsider = person(:active_ranger)

    @speaker = person(:ranger_with_custom_gender) # CustomGender, active
    @other_speaker = person(:retired_ranger)      # RetiredRanger, retired
    @bonked = person(:bonked_ranger)              # BonkedTest, bonked

    [@speaker, @other_speaker, @bonked].each { |p| p.update!(on_site: true) }

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::VC, "Volunteer Coordinator")

    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
    grant_role(@vc, Role::VC)

    speaks(@speaker, "French", PersonLanguage::PROFICIENCY_FLUENT)
    speaks(@other_speaker, "French", PersonLanguage::PROFICIENCY_BASIC)
    speaks(@speaker, "Spanish", PersonLanguage::PROFICIENCY_INTERMEDIATE)
    speaks(@speaker, "Chinese (Mandarin)", PersonLanguage::PROFICIENCY_UNKNOWN)
    speaks(@other_speaker, PersonLanguage::LANGUAGE_NAME_CUSTOM,
           PersonLanguage::PROFICIENCY_FLUENT, custom: "Klingon")
    speaks(@bonked, "German", PersonLanguage::PROFICIENCY_FLUENT)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- access ---------------------------------------------------------------

  test "admin may read both levels" do
    assert_reads_both_levels(@admin)
  end

  test "event management may read both levels" do
    assert_reads_both_levels(@event_manager)
  end

  # This page says where a person is standing right now, which is a narrower
  # thing to know than the roster the VC role is for.
  test "vc is turned away from both levels" do
    sign_in_as(@vc)

    get people_languages_known_path
    assert_redirected_to me_root_path

    get people_languages_known_detail_path("French")
    assert_redirected_to me_root_path
  end

  test "a person without any of those roles is turned away from both levels" do
    sign_in_as(@outsider)

    get people_languages_known_path
    assert_redirected_to me_root_path

    get people_languages_known_detail_path("French")
    assert_redirected_to me_root_path
  end

  test "a signed out visitor is sent to login" do
    get people_languages_known_path
    assert_redirected_to root_path
  end

  # --- index ----------------------------------------------------------------

  test "index lists each language with its speaker count" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_response :success
    assert_select "a[href=?]", people_languages_known_detail_path("French") do
      assert_select "*", text: /2 speakers/
    end
    assert_select "a[href=?]", people_languages_known_detail_path("Spanish") do
      assert_select "*", text: /1 speaker/
    end
  end

  test "index splits the standard languages from the typed-in ones" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_equal ["Chinese (Mandarin)", "French", "Spanish"], group_languages("Common Languages")
    assert_equal ["Klingon"], group_languages("Other Languages")
  end

  test "index counts people rather than the languages they list" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_match "Showing 4 languages spoken by 2 people", response.body.squish
  end

  test "index leaves out a language only someone inactive speaks" do
    # Proves the record is really there to be left out, so the assertion below
    # cannot pass just because the fixture went missing.
    assert_equal 1, PersonLanguage.where(person_id: @bonked.id).count

    sign_in_as(@admin)
    get people_languages_known_path

    assert_no_match "German", response.body
    assert_no_match "BonkedTest", response.body
  end

  test "index says so when no one has listed a language" do
    PersonLanguage.delete_all

    sign_in_as(@admin)
    get people_languages_known_path

    assert_response :success
    assert_match "No one has listed a language yet.", response.body.squish
  end

  test "index renders unique dom ids" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_unique_dom_ids
  end

  # --- detail ---------------------------------------------------------------

  test "detail lists the speakers in callsign order with a link to each person" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_response :success
    assert_equal %w[CustomGender RetiredRanger], roster_callsigns
    assert_select "a[href=?]", person_path(@speaker)
    assert_select "a[href=?]", person_path(@other_speaker)
  end

  test "detail shows how well each person speaks the language" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_match "Fluent", response.body
    assert_match "Basic", response.body
  end

  test "detail counts the speakers at each level" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    # The value and its label are adjacent blocks, so they read as one word here.
    stats = css_select("#languages-known-stats > div").map { |box| box.text.squish }
    assert_equal ["2Speakers", "0On Duty", "0Radios", "1Fluent", "1Basic"], stats
  end

  # Every level with someone at it gets a box, so a reader adding the levels up
  # reaches the speaker count instead of coming up short.
  test "detail counts add up to the number of speakers" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("Chinese (Mandarin)")

    stats = css_select("#languages-known-stats > div").map { |box| box.text.squish }
    assert_equal ["1Speakers", "0On Duty", "0Radios", "1Not Stated"], stats
  end

  test "detail says not stated when no one set a level" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("Chinese (Mandarin)")

    assert_response :success
    assert_equal %w[CustomGender], roster_callsigns
    assert_match "Not Stated", response.body
  end

  test "detail finds a language whatever case it is asked for" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("frEnch")

    assert_response :success
    assert_equal %w[CustomGender RetiredRanger], roster_callsigns
  end

  test "detail finds a typed-in language" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("Klingon")

    assert_response :success
    assert_equal %w[RetiredRanger], roster_callsigns
  end

  test "detail reads a language whose name carries a dot" do
    speaks(@speaker, PersonLanguage::LANGUAGE_NAME_CUSTOM,
           PersonLanguage::PROFICIENCY_BASIC, custom: "U.S. Sign")

    sign_in_as(@admin)
    get people_languages_known_detail_path("U.S. Sign")

    assert_response :success
    assert_equal %w[CustomGender], roster_callsigns
  end

  # People really do type these -- "Indonesian/Malay" is on file. The index has
  # to be able to link to one, and the link has to come back to the same page.
  test "detail reads a language whose name carries a slash" do
    speaks(@speaker, PersonLanguage::LANGUAGE_NAME_CUSTOM,
           PersonLanguage::PROFICIENCY_BASIC, custom: "Indonesian/Malay")

    sign_in_as(@admin)
    get people_languages_known_path
    assert_response :success
    assert_select "a[href=?]", people_languages_known_detail_path("Indonesian/Malay")

    get people_languages_known_detail_path("Indonesian/Malay")
    assert_response :success
    assert_equal %w[CustomGender], roster_callsigns
  end

  test "detail says so when no one speaks the language asked for" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("Esperanto")

    assert_response :success
    assert_match "No one has listed this language.", response.body.squish
    assert_match "Esperanto", response.body
  end

  test "detail renders unique dom ids" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_unique_dom_ids
  end

  # --- searching ------------------------------------------------------------

  test "index narrows the list to the languages asked for" do
    sign_in_as(@admin)
    get people_languages_known_path(q: "ren")

    assert_response :success
    assert_equal ["French"], group_languages("Common Languages")
    assert_no_match "Spanish", response.body
    assert_match "Showing 1 language matching", response.body.squish
  end

  test "a search reaches a language only spoken by someone who is away" do
    @speaker.update!(on_site: false)
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_path(site: "on_site")

    assert_match "No one on site has listed a language yet.", response.body

    get people_languages_known_path(q: "spanish")
    assert_response :success
    assert_equal ["Spanish"], group_languages("Common Languages")
    assert_match "Off site only", response.body
  end

  # The filter says who counts, and searching does not talk it out of that.
  test "a search is still held to the people the filter covers" do
    @speaker.update!(on_site: false)
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_path(q: "spanish", site: "on_site")

    assert_response :success
    assert_match "No language matches", response.body
  end

  test "index says so when a search finds nothing" do
    sign_in_as(@admin)
    get people_languages_known_path(q: "esperanto")

    assert_response :success
    assert_match "No language matches", response.body
  end

  # The term is written back into the page, so it has to arrive as text.
  test "index does not run what was typed into the search box" do
    sign_in_as(@admin)
    get people_languages_known_path(q: "<script>alert(1)</script>")

    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "index rows carry the name the filter matches on" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_select "[data-list-filter-target=row][data-name=?]", "french"
  end

  # --- what a speaker is doing right now ------------------------------------

  test "detail shows the shift a speaker is on and the radio they hold" do
    start_shift(@speaker)
    check_out_radio(@other_speaker)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_response :success
    assert_match "On duty", response.body
    assert_match positions(:ood_position).title, response.body
    assert_match "Radio", response.body
  end

  test "detail counts who is on a shift and who has a radio" do
    start_shift(@speaker)
    check_out_radio(@speaker)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    stats = css_select("#languages-known-stats > div").map { |box| box.text.squish }
    assert_equal ["2Speakers", "1On Duty", "1Radios", "1Fluent", "1Basic"], stats
  end

  test "detail lists whoever can be reached first" do
    check_out_radio(@other_speaker) # RetiredRanger -- sorts last by callsign

    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_equal %w[RetiredRanger CustomGender], roster_callsigns
  end

  # --- speakers who are away ------------------------------------------------

  test "detail leaves out speakers who are away when asked" do
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French", site: "on_site")

    assert_response :success
    assert_equal %w[CustomGender], roster_callsigns
  end

  test "detail holds the speakers who are away by default" do
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French")

    assert_response :success
    assert_equal %w[CustomGender RetiredRanger], roster_callsigns
    # The badge marks the one who is away, and only that one.
    rows = css_select("tbody tr").map(&:to_s)
    assert_no_match "Off site", rows.first
    assert_match "Off site", rows.last
  end

  # Everyone in this list is away, so saying it on each row says nothing.
  test "detail can be held to the speakers who are away" do
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French", site: "off_site")

    assert_response :success
    assert_equal %w[RetiredRanger], roster_callsigns
    assert_no_match "Off site", css_select("tbody").to_s
  end

  test "detail says who it looked at when it found no one" do
    sign_in_as(@admin)

    get people_languages_known_detail_path("Esperanto")
    assert_match "No one has listed this language.", response.body.squish

    get people_languages_known_detail_path("Esperanto", site: "off_site")
    assert_match "No one off site has listed this language.", response.body

    get people_languages_known_detail_path("Esperanto", site: "on_site")
    assert_match "No one on site has listed this language.", response.body
  end

  # A page for no language would build every one of its own addresses as the
  # list, so its filter would walk away from it.
  test "a blank language goes to the list instead of a page for nothing" do
    sign_in_as(@admin)
    get "/people/languages-known/%20?site=off_site"

    assert_redirected_to people_languages_known_path(site: "off_site")
  end

  test "drilling into a language keeps the search" do
    sign_in_as(@admin)
    get people_languages_known_path(q: "french")

    assert_select "a[href=?]", people_languages_known_detail_path("French", q: "french")

    get people_languages_known_detail_path("French", q: "french")
    assert_select "a[href=?]", people_languages_known_path(q: "french")
  end

  test "the search keeps a narrower filter out of the address" do
    sign_in_as(@admin)

    get people_languages_known_path
    assert_select "form input[name=site]", false

    get people_languages_known_path(site: "off_site")
    assert_select "form input[type=hidden][name=site][value=off_site]"
  end

  # The people on a shift are not all here, so this list is the one narrowing
  # where being away is still worth saying.
  test "the on duty list still says who has not arrived" do
    @other_speaker.update!(on_site: false)
    start_shift(@other_speaker)

    sign_in_as(@admin)
    get people_languages_known_detail_path("French", site: "on_duty")

    assert_equal %w[RetiredRanger], roster_callsigns
    assert_match "Off site", css_select("tbody").to_s
  end

  # The two would argue with each other: somebody is standing a shift.
  test "a language with someone on duty is not called off site only" do
    @speaker.update!(on_site: false)
    @other_speaker.update!(on_site: false)
    start_shift(@other_speaker) # RetiredRanger speaks French and Klingon

    sign_in_as(@admin)
    get people_languages_known_path

    # French and Klingon are the two RetiredRanger speaks, so they carry the
    # count and not the badge. Spanish and Chinese have no one on a shift.
    assert_equal ["1 on duty", "1 on duty", "Off site only", "Off site only"], row_badges.sort
  end

  test "row badges are sized to sit in the row" do
    start_shift(@other_speaker)
    sign_in_as(@admin)
    get people_languages_known_path

    assert_select "a[href*='languages-known/'] .badge.text-base", minimum: 1
    assert_select "a[href*='languages-known/'] .badge.text-xs", false
  end

  # --- the filter itself ----------------------------------------------------

  test "index filters the list by where people are" do
    @other_speaker.update!(on_site: false) # RetiredRanger speaks French and Klingon

    sign_in_as(@admin)

    get people_languages_known_path(site: "on_site")
    assert_equal ["Chinese (Mandarin)", "French", "Spanish"], group_languages("Common Languages")
    assert_empty group_languages("Other Languages")

    get people_languages_known_path(site: "off_site")
    assert_equal ["French"], group_languages("Common Languages")
    assert_equal ["Klingon"], group_languages("Other Languages")

    get people_languages_known_path
    assert_equal ["Chinese (Mandarin)", "French", "Spanish"], group_languages("Common Languages")
    assert_equal ["Klingon"], group_languages("Other Languages")
  end

  test "index says which people it counted" do
    sign_in_as(@admin)

    get people_languages_known_path
    assert_match "spoken by 2 people", response.body.squish

    get people_languages_known_path(site: "on_site")
    assert_match "spoken by 2 people on site", response.body.squish

    get people_languages_known_path(site: "off_site")
    assert_match "No one off site has listed a language yet.", response.body
  end

  test "index can be held to the people on a shift right now" do
    start_shift(@other_speaker) # RetiredRanger speaks French and Klingon
    sign_in_as(@admin)

    get people_languages_known_path(site: "on_duty")
    assert_equal ["French"], group_languages("Common Languages")
    assert_equal ["Klingon"], group_languages("Other Languages")
    assert_match "spoken by 1 person on duty", response.body.squish
  end

  test "the on duty list says so once rather than on every language" do
    start_shift(@other_speaker)
    sign_in_as(@admin)

    get people_languages_known_path(site: "on_duty")
    assert_empty row_badges

    # RetiredRanger speaks two languages, so the count rides on both rows.
    get people_languages_known_path(site: "on_site")
    assert_equal ["1 on duty", "1 on duty"], row_badges
  end

  test "detail can be held to the people on a shift right now" do
    start_shift(@other_speaker)
    sign_in_as(@admin)

    get people_languages_known_detail_path("French", site: "on_duty")
    assert_equal ["RetiredRanger"], roster_callsigns

    # The shift itself still reads, but the badge saying there is one would sit
    # on every row, and the count would only repeat the speaker count.
    assert_match positions(:ood_position).title, css_select("tbody").to_s
    assert_no_match "On duty", css_select("tbody").to_s

    stats = css_select("#languages-known-stats > div").map { |box| box.text.squish }
    assert_equal ["1Speakers", "0Radios", "1Basic"], stats
  end

  test "a language no one on duty speaks says so" do
    sign_in_as(@admin)
    get people_languages_known_detail_path("French", site: "on_duty")

    assert_match "No one on duty has listed this language.", response.body
  end

  test "the filter bar holds the choice in use and a chip that drops it" do
    sign_in_as(@admin)

    [people_languages_known_path(site: "off_site"),
     people_languages_known_detail_path("French", site: "off_site")].each do |page|
      get page
      assert_select "select[name=site] option[value=off_site][selected]"
      assert_select "a[aria-label=?]", "Remove filter: Speakers: Off site"
    end
  end

  # Counting everybody is where the page starts, so there is nothing to remove.
  test "counting everybody draws no chip" do
    sign_in_as(@admin)
    get people_languages_known_path

    assert_select "select[name=site] option[value=all][selected]"
    assert_no_match(/Speakers:/, response.body)
  end

  test "the filter follows a language into its own page and back" do
    @other_speaker.update!(on_site: false)

    sign_in_as(@admin)
    get people_languages_known_path(site: "off_site")

    assert_select "a[href=?]", people_languages_known_detail_path("French", site: "off_site")

    get people_languages_known_detail_path("French", site: "off_site")
    assert_select "a[href=?]", people_languages_known_path(site: "off_site")
  end

  # A filter the page does not know must not stop it, and must not quietly
  # narrow it either.
  test "a filter no one offers counts everybody" do
    sign_in_as(@admin)
    get people_languages_known_path(site: "mars")

    assert_response :success
    assert_match "spoken by 2 people", response.body.squish
    assert_no_match(/Speakers:/, response.body)
  end

  test "a search keeps the filter it was run under" do
    sign_in_as(@admin)
    get people_languages_known_path(q: "french", site: "on_site")

    assert_response :success
    assert_select "select[name=site] option[value=on_site][selected]"
    # Applying a filter from here has to keep the search alongside it.
    assert_select "#languages-known-filters-panel input[name=q][value=french]"
  end

  private

  def start_shift(person, position: positions(:ood_position))
    Timesheet.create!(person:, position:, on_duty: Time.zone.local(Current.year, 8, 28, 10),
                      additional_notes: "signed in for a test")
  end

  def check_out_radio(person)
    PersonAsset.create!(person:, asset: asset(:radio_current_year),
                        checked_out: Time.zone.local(Current.year, 8, 28, 9))
  end

  def assert_reads_both_levels(reader)
    sign_in_as(reader)

    get people_languages_known_path
    assert_response :success

    get people_languages_known_detail_path("French")
    assert_response :success
  end

  def speaks(person, name, proficiency, custom: nil)
    PersonLanguage.create!(person:, language_name: name, language_custom: custom, proficiency:)
  end

  # The language names listed under one of the index headings. The heading
  # carries its count in a badge, so the title is matched without it.
  def group_languages(heading)
    nodes = css_select("[role=heading], a[href*='languages-known/']")
            .drop_while { |node| node.text.strip.sub(/\s+\d+\z/, "") != heading }
    nodes.drop(1).take_while { |node| node.name == "a" }
         .map { |link| link.text.squish[/\A[^•]+/].to_s.strip }
  end

  def roster_callsigns
    css_select("tbody th[scope=row] a").map { |link| link.text.strip }
  end

  # The badges riding alongside the language names on the index.
  def row_badges
    css_select("a[href*='languages-known/'] .badge").map { |badge| badge.text.squish }
  end
end
