# frozen_string_literal: true

require "test_helper"

# Mentoring > Post Season Summary: a year's whole Prospective/Alpha class,
# including the people who washed out, split by what the Mentors concluded.
class Mentoring::PostSeasonSummaryControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include IntakeTestHelper
  include PersonTestFactory
  include ReportCardTestHelper # card_answer
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to view the post season summary."

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @shift = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 20, 17, 0, 0),
                                          description: "Alpha Walk")
    @last_year_shift = create_slot(@alpha_position, begins: Time.zone.local(YEAR - 1, 8, 20, 17, 0, 0),
                                                    description: "Alpha Walk")

    @mentor_one = create_person("Ratchet")
    @mentor_two = create_person("Firehose")
    # Walks with @bonked alone, so filtering by any other mentor removes their
    # only mentee -- which is what proves the mentor select is built unfiltered.
    @mentor_three = create_person("Sandpaper")

    # Signed up and walked with two mentors, verdict pass. The clean case.
    @passed = create_prospective("Sparkplug")
    place_in_pipeline(@passed, YEAR)
    sign_up(@passed, @shift)
    walk(@passed, [@mentor_one, @mentor_two], status: PersonMentor::STATUS_PASS)

    # Walked and was bonked -- Section A, and still on the roster, which is what
    # separates this page from /mentoring/alpha-status.
    @bonked = create_prospective("Cinderblock")
    place_in_pipeline(@bonked, YEAR)
    place_in_pipeline(@bonked, YEAR, new_status: Person::BONKED)
    sign_up(@bonked, @shift)
    walk(@bonked, [@mentor_one, @mentor_three], status: PersonMentor::STATUS_BONK)

    # Walked and self-bonked.
    @self_bonked = create_prospective("Dustpan")
    place_in_pipeline(@self_bonked, YEAR)
    sign_up(@self_bonked, @shift)
    walk(@self_bonked, [@mentor_two], status: PersonMentor::STATUS_SELF_BONK)

    # Uberbonked: the account status, not a mentor verdict.
    @uberbonked = create_prospective("Tumbleweed")
    place_in_pipeline(@uberbonked, YEAR)
    @uberbonked.update_column(:status, Person::UBERBONKED)

    # Booked a shift and never walked it: no mentors for the year.
    @no_walk = create_prospective("Turnstile")
    place_in_pipeline(@no_walk, YEAR)
    sign_up(@no_walk, @shift)

    # Never signed up at all.
    @no_signup = create_prospective("Moonwrench")
    place_in_pipeline(@no_signup, YEAR)

    # Passed, but carries a mentor rank of 4 for the year -- Section A on the
    # rank alone, which is the half of the split that is not about bonks.
    @ranked = create_prospective("Kerosene")
    place_in_pipeline(@ranked, YEAR)
    sign_up(@ranked, @shift)
    walk(@ranked, [@mentor_one], status: PersonMentor::STATUS_PASS)
    PersonIntake.create!(person_id: @ranked.id, year: YEAR, mentor_rank: Intake::FLAG)

    # The other half of the section's own title, "Bonked or Mentor Rank 3/4":
    # rank 3 must claim Section A exactly as rank 4 does.
    @ranked_three = create_prospective("Bottlecap")
    place_in_pipeline(@ranked_three, YEAR)
    sign_up(@ranked_three, @shift)
    walk(@ranked_three, [@mentor_two], status: PersonMentor::STATUS_PASS)
    PersonIntake.create!(person_id: @ranked_three.id, year: YEAR, mentor_rank: Intake::BELOW_AVERAGE)

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")

    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization -------------------------------------------------------

  test "an admin can view the page" do
    sign_in_as(@admin)

    get mentoring_post_season_summary_path

    assert_response :success
    assert_match "#{YEAR} Post Season Summary", response.body
  end

  test "a mentor can view the page" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get mentoring_post_season_summary_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the detail frame requires the same roles" do
    sign_in_as(@outsider)

    get mentoring_post_season_summary_detail_path(@passed)

    assert_redirected_to me_root_path
  end

  # --- the roster ----------------------------------------------------------

  test "everyone who entered this year's class is listed" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_response :success
    [@passed, @bonked, @self_bonked, @uberbonked, @no_walk, @no_signup, @ranked].each do |target|
      assert_match target.callsign, response.body
    end
  end

  # The distinguishing fact of this page. /mentoring/alpha-status subtracts
  # whoever washed out during the year; here they are most of the point.
  test "someone who washed out during the same year is kept" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_match @bonked.callsign, response.body
    assert_equal :flagged, section_for(@bonked)
  end

  test "a class from another year is not listed" do
    sign_in_as(@mentor)
    stale = create_prospective("Driftwood")
    place_in_pipeline(stale, YEAR - 2)

    get mentoring_post_season_summary_path

    assert_no_match(/#{stale.callsign}/, response.body)
  end

  # --- the two sections ----------------------------------------------------

  test "both section titles are rendered" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    Mentoring::PostSeasonSummaryHelper::SECTIONS.each_value do |meta|
      assert_match meta[:title], response.body
    end
    assert_equal 2, Mentoring::PostSeasonSummaryHelper::SECTIONS.size
  end

  test "the sections between them render every person exactly once" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    rendered = Mentoring::PostSeasonSummaryHelper::SECTIONS.keys.flat_map { |key| section_ids(key) }
    assert_equal rendered.size, rendered.uniq.size
    assert_equal Intake.retrieve_post_season_class(YEAR).map { |summary| summary[:person].id }.sort,
                 rendered.sort
  end

  test "a bonk of either kind claims section a" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_equal :flagged, section_for(@bonked)
    assert_equal :flagged, section_for(@self_bonked)
  end

  # Read off the account status, not the mentor verdict -- this person never
  # walked, so there is no person_mentor row to read one from.
  test "an uberbonked person claims section a on their status alone" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_equal :flagged, section_for(@uberbonked)
  end

  test "a mentor rank of 3 or 4 claims section a without any bonk" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_equal PersonMentor::STATUS_PASS, summary_for(@ranked)[:mentor_status]
    assert_equal PersonMentor::STATUS_PASS, summary_for(@ranked_three)[:mentor_status]
    assert_equal :flagged, section_for(@ranked)
    assert_equal :flagged, section_for(@ranked_three)
  end

  # The boundary itself: rank 2 is the highest rank that stays in Section B.
  test "a mentor rank below 3 does not claim section a" do
    sign_in_as(@mentor)
    PersonIntake.create!(person_id: @passed.id, year: YEAR, mentor_rank: Intake::AVERAGE)

    get mentoring_post_season_summary_path

    assert_equal :other, section_for(@passed)
  end

  # The split is the viewed year's mentor rank, so an old rank must not drag
  # somebody into Section A years later.
  test "a mentor rank from an earlier year does not claim section a" do
    sign_in_as(@mentor)
    PersonIntake.create!(person_id: @passed.id, year: YEAR - 3, mentor_rank: Intake::FLAG)

    get mentoring_post_season_summary_path

    assert_equal 0, summary_for(@passed)[:mentor_rank]
    assert_equal :other, section_for(@passed)
  end

  test "a clean pass lands in section b" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_equal :other, section_for(@passed)
    assert_equal :other, section_for(@no_walk)
    assert_equal :other, section_for(@no_signup)
  end

  # --- the sign-up chip ----------------------------------------------------

  # Asserted on the rendered row, not on a re-derived state: the chip IS the
  # feature, and _row_extras reaching the page at all depends on the shared
  # partial's new locals being wired up.
  test "the three sign-up states are told apart on the row" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_select "#person-#{@passed.id}", text: /Walked a shift/
    assert_select "#person-#{@no_walk.id}", text: /Signed up, did not walk/
    assert_select "#person-#{@no_signup.id}", text: /No Alpha sign-up/
    # Each row carries exactly one of the three, so a state can never double up.
    assert_select "#person-#{@passed.id}", text: /No Alpha sign-up|did not walk/, count: 0
  end

  # The verdict chip, which only a pass raises, sits in the pane; the bonk is
  # the line's own lead chip and is not chipped twice.
  test "a passing verdict is chipped and a bonk is not chipped twice" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(person: @passed.id)

    assert_select "aside", text: /Passed/
    assert_select "#person-#{@bonked.id}", text: /#{YEAR} mentor bonked/
    assert_select "#person-#{@bonked.id}", text: /Passed/, count: 0

    get mentoring_post_season_summary_path(person: @bonked.id)

    assert_select "aside", text: /Passed/, count: 0
  end

  # The bonk chip is the viewed year's on this page, unlike the shared strip's
  # any-year-latest: a prior-year bonk chip beside this year's pass would
  # contradict the section, the Outcome filter, and the stat box on one row.
  test "a bonk from another year is not chipped and does not claim section a" do
    sign_in_as(@mentor)
    walk(@passed, [@mentor_one], status: PersonMentor::STATUS_BONK, year: YEAR - 3)

    get mentoring_post_season_summary_path

    assert_select "#person-#{@passed.id}", text: /mentor bonked/, count: 0
    assert_equal :other, section_for(@passed)
  end

  # Mentors dominate the sign-up state: a recorded walk whose sign-up row has
  # since gone (bulk-deleted slots, a worksheet walk-up) must not read as
  # "No Alpha sign-up" beside a recorded pass.
  test "a walker without a surviving sign-up row still reads as walked" do
    sign_in_as(@mentor)
    walkup = create_prospective("Latchkey")
    place_in_pipeline(walkup, YEAR)
    walk(walkup, [@mentor_one], status: PersonMentor::STATUS_PASS)

    get mentoring_post_season_summary_path

    assert_select "#person-#{walkup.id}", text: /Walked a shift/
    assert_select "#person-#{walkup.id}", text: /No Alpha sign-up/, count: 0
  end

  # The tiles and the Alpha-shift filter read the same mentors-first state as
  # the line, so that walk-up counts as walked and signed up, and nowhere as
  # never signed up -- the No Alpha sign-up tile is a link to that filter.
  test "a walker without a surviving sign-up row is not counted as never signed up" do
    sign_in_as(@mentor)
    walkup = create_prospective("Latchkey")
    place_in_pipeline(walkup, YEAR)
    walk(walkup, [@mentor_one], status: PersonMentor::STATUS_PASS)

    get mentoring_post_season_summary_path

    assert_equal 6, stat_value("Walked a shift")
    assert_equal 2, stat_value("No Alpha sign-up")

    get mentoring_post_season_summary_path(signup: "none")

    assert_select "#person-#{@no_signup.id}"
    assert_select "#person-#{walkup.id}", count: 0

    get mentoring_post_season_summary_path(signup: "signed-up")

    assert_select "#person-#{walkup.id}"
  end

  # Upstream paints the first two identically; its own spec says they differ.
  test "each sign-up state carries its own color and icon" do
    variants = Mentoring::PostSeasonSummaryHelper::SIGNUP_CHIPS.values

    assert_equal variants.size, variants.map { |chip| chip[:variant] }.uniq.size
    assert_equal variants.size, variants.map { |chip| chip[:icon] }.uniq.size
  end

  # A sign-up for a DIFFERENT year's Alpha shift must not read as this year's.
  # Asserted on the rendered chip, not a re-derived state, so the assertion
  # tracks the app's own definition.
  test "an alpha sign-up in another year does not count" do
    sign_in_as(@mentor)
    sign_up(@no_signup, @last_year_shift)

    get mentoring_post_season_summary_path

    assert_not summary_for(@no_signup)[:signed_up]
    assert_select "#person-#{@no_signup.id}", text: /No Alpha sign-up/
  end

  # --- the mentors line ----------------------------------------------------

  # The mentors are in the pane, under the selected person, and off the line
  # (ruling R5): the list stays one line per person.
  test "the pane names the mentors who walked with the person" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(person: @passed.id)

    assert_select "aside" do
      assert_select "a", text: @mentor_one.callsign
      assert_select "a", text: @mentor_two.callsign
    end
    assert_select "li#person-#{@passed.id} a", text: @mentor_one.callsign, count: 0
  end

  # The card explains the pane and the chip in the words every pipeline page
  # shares, beside this page's own pair.
  test "the card explains the pane and the chip" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_match(/Select a name/, card_answer("How do I read someone’s history?"))
    assert_match(/most serious mark/, card_answer("What is the colored chip on an entry?"))
    assert_match(/what the Mentors concluded/, card_answer("What does each person's entry show?"))
  end

  test "a pane with no mentors says so" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(person: @no_signup.id)

    assert_select "aside", text: /None assigned/
  end

  # The mentors are the viewed year's, so a later year's pairing must not
  # appear on this year's pane.
  test "mentors from another year are not listed" do
    sign_in_as(@mentor)
    walk(@no_signup, [@mentor_one], year: YEAR - 1)

    get mentoring_post_season_summary_path(person: @no_signup.id)

    assert_select "aside", text: /None assigned/
  end

  # --- filters -------------------------------------------------------------

  test "the sign-up filter narrows to who walked" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(signup: "walked")

    assert_match @passed.callsign, response.body
    assert_no_match(/#{@no_walk.callsign}/, response.body)
    assert_no_match(/#{@no_signup.callsign}/, response.body)
  end

  test "the sign-up filter narrows to who never signed up" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(signup: "none")

    assert_match @no_signup.callsign, response.body
    assert_no_match(/#{@passed.callsign}/, response.body)
  end

  test "the outcome filter separates the two kinds of bonk" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(outcome: PersonMentor::STATUS_SELF_BONK)

    assert_match @self_bonked.callsign, response.body
    assert_no_match(/#{@bonked.callsign}/, response.body)
  end

  test "the outcome filter reads uber-bonk off the account status" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(outcome: "uber-bonk")

    assert_match @uberbonked.callsign, response.body
    assert_no_match(/#{@bonked.callsign}/, response.body)
  end

  test "the rank filter selects one rank" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(rank: Intake::FLAG.to_s)

    assert_match @ranked.callsign, response.body
    assert_no_match(/#{@passed.callsign}/, response.body)
  end

  test "the rank filter selects the unranked" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(rank: "none")

    assert_match @passed.callsign, response.body
    assert_no_match(/#{@ranked.callsign}/, response.body)
  end

  test "the notes filter selects on a mentor note in the viewed year" do
    sign_in_as(@mentor)
    PersonIntakeNote.create!(person_id: @passed.id, year: YEAR, type: "mentor",
                             note: "Strong walk.", person_source_id: @mentor.id)

    get mentoring_post_season_summary_path(notes: "any")

    assert_match @passed.callsign, response.body
    assert_no_match(/#{@no_signup.callsign}/, response.body)
  end

  # `have_notes` upstream means somebody wrote something -- an automatic log
  # entry is not that.
  test "a log-only note does not count as having notes" do
    sign_in_as(@mentor)
    PersonIntakeNote.create!(person_id: @passed.id, year: YEAR, type: "mentor", is_log: true,
                             note: "Status changed.", person_source_id: @mentor.id)

    get mentoring_post_season_summary_path(notes: "any")

    assert_no_match(/#{@passed.callsign}/, response.body)
  end

  test "the mentor filter narrows to one mentor's mentees" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(mentor: @mentor_two.id.to_s)

    assert_match @passed.callsign, response.body
    assert_match @self_bonked.callsign, response.body
    assert_no_match(/#{@bonked.callsign}/, response.body)
  end

  # The list of mentors you can pick from comes from the unfiltered roster, so
  # narrowing must never empty the select you narrowed with. @mentor_three is
  # the test: their only mentee is filtered OUT here, so they survive the
  # select only if the options are built before the filter runs.
  test "the mentor options survive a filter" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(mentor: @mentor_two.id.to_s)

    assert_no_match(/#{@bonked.callsign}/, response.body)
    assert_select "select[name=mentor] option[value=?]", @mentor_three.id.to_s
  end

  # Two facets the selects actually offer: walked AND self-bonk keeps only the
  # walker who self-bonked, dropping walkers with other outcomes.
  test "the facets narrow together" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(signup: "walked", outcome: PersonMentor::STATUS_SELF_BONK)

    assert_match @self_bonked.callsign, response.body
    assert_no_match(/#{@passed.callsign}/, response.body)
  end

  # Only values the selects offer are accepted. A typo'd value must read as
  # inactive, not silently narrow the roster (?signup=typo used to act as the
  # walked filter, ?rank=abc as "no rank"), and an array-shaped param must not
  # crash the :rank arm's to_i.
  test "an unrecognized facet value is ignored" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(signup: "typo", rank: "abc")

    assert_response :success
    assert_match "Showing 8 of 8 people", response.body
    assert_match @no_signup.callsign, response.body
  end

  test "an array-shaped facet param does not crash the page" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(rank: ["3"], signup: { "a" => "b" })

    assert_response :success
    assert_match "Showing 8 of 8 people", response.body
  end

  # The chips are the filter bar's memory: each names its filter in page
  # words (a mentor chip shows the callsign, not the id), its URL drops only
  # that filter, and the year -- page state, not a filter -- survives both the
  # chip URLs and Clear all.
  test "filter chips keep the year and name the mentor by callsign" do
    sign_in_as(@mentor)
    year = YEAR - 1
    place_in_pipeline(@passed, year)
    walk(@passed, [@mentor_two], year: year)

    get mentoring_post_season_summary_path(year: year, signup: "walked", mentor: @mentor_two.id.to_s)

    assert_select "a", text: "Mentor: #{@mentor_two.callsign}" do |chips|
      href = chips.first["href"]
      assert_includes href, "year=#{year}", "removing a chip must keep the viewed year"
      assert_includes href, "signup=walked", "removing a chip must keep the other filters"
      assert_not_includes href, "mentor="
    end
    assert_select "a[href=?]", mentoring_post_season_summary_path(year: year), text: "Clear All Filters"
  end

  test "a filter matching no one says so" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(q: "NoSuchCallsign")

    assert_response :success
    assert_match "No one in the #{YEAR} class matched those filters.", response.body
  end

  # A section emptied by a filter must not report that as a fact about the
  # class: "Everyone in this class bonked" is a very different claim.
  test "a section emptied by a filter blames the filter" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(rank: Intake::FLAG.to_s)

    assert_select "#post-season-other", text: /No one matched those filters/
    assert_select "#post-season-other",
                  text: /#{Regexp.escape(Mentoring::PostSeasonSummaryHelper::SECTIONS[:other][:empty])}/,
                  count: 0
  end

  test "an unfiltered empty section states the fact about the class" do
    sign_in_as(@mentor)
    clean = create_prospective("Bellwether")
    place_in_pipeline(clean, YEAR - 1)

    get mentoring_post_season_summary_path(year: YEAR - 1)

    assert_select "#post-season-other", text: /#{clean.callsign}/
    assert_select "#post-season-flagged",
                  text: /#{Regexp.escape(Mentoring::PostSeasonSummaryHelper::SECTIONS[:flagged][:empty])}/
  end

  # Training is forced off rather than dropped -- the concern's filter would
  # otherwise reject every row on a missing key. "trained" is the value NOBODY
  # in this class holds (none of them has a training record), so the assertion
  # fails the moment the force is removed.
  test "no training filter is offered and none is applied" do
    sign_in_as(@mentor)

    assert_equal "none", summary_for(@passed)[:training_status]

    get mentoring_post_season_summary_path(training: "trained")

    assert_response :success
    assert_match @passed.callsign, response.body
    assert_select "select[name=training]", false
  end

  # --- counts --------------------------------------------------------------

  test "the stat boxes count the class" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_equal 8, stat_value("Mentees")
    assert_equal 5, stat_value("Walked a shift")
    assert_equal 5, stat_value("Bonked or ranked 3/4")
    assert_equal 2, stat_value("No Alpha sign-up")
  end

  test "filtering does not change the stat boxes" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(signup: "none")

    assert_equal 8, stat_value("Mentees")
    assert_equal 5, stat_value("Walked a shift")
  end

  # --- year scoping --------------------------------------------------------

  test "the year selector picks which class is reported on" do
    sign_in_as(@mentor)
    last_year = create_prospective("Bellwether")
    place_in_pipeline(last_year, YEAR - 1)

    get mentoring_post_season_summary_path(year: YEAR - 1)

    assert_response :success
    assert_match "#{YEAR - 1} Post Season Summary", response.body
    assert_match last_year.callsign, response.body
    assert_no_match(/#{@passed.callsign}/, response.body)
  end

  # Setup places everyone in YEAR, so the year before has no class.
  test "a year with no class says so" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(year: YEAR - 1)

    assert_response :success
    assert_select ".empty-state", text: "No one became a Prospective or an Alpha in #{YEAR - 1}."
  end

  test "a year below the floor falls back to the current year" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(year: 1999)

    assert_response :success
    assert_match "#{YEAR} Post Season Summary", response.body
  end

  # --- the rows ------------------------------------------------------------

  # Unlike its /mentoring siblings, this page HAS a year, so a line's link and
  # the pane it fills must carry it or they would render another year's history.
  test "selecting a name carries the year into the pane" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(person: @passed.id)

    assert_select "li#person-#{@passed.id} a[aria-current=true][href=?]",
                  mentoring_post_season_summary_path(year: YEAR, person: @passed.id)
    assert_select "aside turbo-frame#uf-pane [data-review-id=?]", @passed.id.to_s
  end

  # In a past year the pane reads that year's history and files its notes in
  # it. Pinned to the pane's own links: every tile and chip on the page also
  # carries the year, so a match anywhere in the body proves nothing.
  test "selecting a name in a past year keeps the pane in that year" do
    sign_in_as(@admin)
    year = YEAR - 1
    place_in_pipeline(@bonked, year)

    get mentoring_post_season_summary_path(year:, person: @bonked.id)

    assert_response :success
    assert_select "li#person-#{@bonked.id} a[aria-current=true][href=?]",
                  mentoring_post_season_summary_path(year:, person: @bonked.id)
    assert_select "aside turbo-frame#uf-pane [data-review-id=?]", @bonked.id.to_s do
      assert_select "a[href=?]", new_person_intake_note_path(@bonked, origin: "mentoring_post_season",
                                                                      origin_year: year, type: "mentor", year:)
      assert_select "a[href*='year=#{YEAR}']", count: 0
      # This year's mentors walked in YEAR, so the past year's pane has none.
      assert_select "*", text: /None assigned/
    end
  end

  # The page's extras -- the verdict chip and the mentors line -- come with the
  # pane when a line loads it alone, not only on a full render.
  test "a line loads only the pane, with this page's extras" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path(person: @passed.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_select "turbo-frame#uf-pane [data-review-id=?]", @passed.id.to_s do
      assert_select "a", text: @mentor_one.callsign
    end
    assert_select "li[id^=person-]", count: 0
    assert_no_match "<html", response.body
  end

  test "the detail frame renders one person's history without the page chrome" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_detail_path(@passed, year: YEAR)

    assert_response :success
    assert_match "uf-frame-#{@passed.id}", response.body
    assert_no_match "<html", response.body
  end

  # The row partial is shared with four other pages, and this page is the only
  # one handing it extras. A default that stopped defaulting would put an Alpha
  # sign-up chip and a mentors line on all of them.
  test "the shared row carries no extras for a page that passes none" do
    sign_in_as(@admin)

    get mentoring_potential_alphas_path

    assert_response :success
    assert_select "[id^=person-]" do |rows|
      assert_predicate rows, :any?, "the sibling page rendered no rows to check"
      rows.each do |row|
        assert_no_match(/Alpha sign-up|did not walk|Walked a shift|None assigned/, row.text)
      end
    end
  end

  # Writable, like upstream: recording what the Mentors concluded is the point.
  test "note controls are offered" do
    sign_in_as(@admin)

    get mentoring_post_season_summary_detail_path(@passed, year: YEAR)

    assert_response :success
    assert_match(/Add Mentor Note/, response.body)
  end

  # The page has its own origin token because the siblings' "mentoring" one
  # returns to the current-standing Potential Alphas roster, which cannot hold
  # a past year's washed-out mentee. The year has to survive the round trip too.
  test "filing a note returns to this page and this year" do
    sign_in_as(@admin)
    year = YEAR - 1
    place_in_pipeline(@bonked, year)

    get mentoring_post_season_summary_detail_path(@bonked, year: year)

    assert_response :success
    origin = "origin=mentoring_post_season"
    assert_match origin, response.body
    assert_match "origin_year=#{year}", response.body

    post person_intake_notes_path(@bonked), params: {
      origin: "mentoring_post_season", origin_year: year,
      intake_note_form: { type: "mentor", year: year, note: "Bonked after a short walk." }
    }

    assert_redirected_to mentoring_post_season_summary_path(year: year, person: @bonked.id)
  end


  # --- the stat tiles ------------------------------------------------------

  # Each tile is also the filter for what it counts: the two sign-up tiles
  # send the Alpha-shift facet, the bonked tile sends the section, and the
  # Mentees tile clears them. The year rides every one.
  test "the stat tiles narrow the class to what they count" do
    sign_in_as(@mentor)

    get mentoring_post_season_summary_path

    assert_select "a[href=?]", mentoring_post_season_summary_path(year: YEAR)
    assert_select "a[href=?]", mentoring_post_season_summary_path(year: YEAR, signup: "walked")
    assert_select "a[href=?]", mentoring_post_season_summary_path(year: YEAR, section: "flagged")
    assert_select "a[href=?]", mentoring_post_season_summary_path(year: YEAR, signup: "none")

    get mentoring_post_season_summary_path(section: "flagged")

    assert_response :success
    assert_match "Section: Bonked or Mentor Rank 3/4", response.body
    assert_equal :flagged, section_for(@bonked)
    assert_nil section_for(@passed)
    assert_select "a.ring-primary[href=?]", mentoring_post_season_summary_path(year: YEAR, section: "flagged")
  end


  # The section tile and the Section select read this page's own split, the
  # Mentors' verdict, and nothing else. The shared index's ?section= filter on
  # Intake's display groups once applied here too, which hid the uber-bonked
  # (Intake :other) from the tile's own link and anyone with an earlier-year
  # bonk (Intake :flagged) from "Other Mentees".
  test "the section filter lists everyone its section counts" do
    sign_in_as(@mentor)
    walk(@passed, [@mentor_one], status: PersonMentor::STATUS_BONK, year: YEAR - 3)

    get mentoring_post_season_summary_path(section: "flagged")

    assert_match "Showing 5 of 8 people", response.body
    assert_includes section_ids(:flagged), @uberbonked.id

    get mentoring_post_season_summary_path(section: "other")

    assert_includes section_ids(:other), @passed.id
  end

  private

  def section_for(target)
    Mentoring::PostSeasonSummaryHelper::SECTIONS.keys.find do |key|
      css_select("#post-season-#{key} #person-#{target.id}").any?
    end
  end

  def section_ids(key)
    css_select("#post-season-#{key} [id^='person-']").map { |node| node["id"].delete_prefix("person-").to_i }
  end

  def summaries
    @summaries ||= Intake.retrieve_post_season_class(YEAR)
  end

  def summary_for(target)
    summaries.find { |summary| summary[:person].id == target.id }
  end

  def stat_value(label)
    node = css_select("div").find { |div| div.text.strip == label }
    node.parent.text.strip.delete_suffix(label).to_i
  end

  def create_prospective(callsign)
    create_person(callsign, status: Person::PROSPECTIVE)
  end

  def sign_up(target, slot)
    PersonSlot.create!(person_id: target.id, slot_id: slot.id)
  end

  def walk(target, mentors, status: PersonMentor::STATUS_PASS, year: YEAR)
    mentors.each do |mentor|
      PersonMentor.create!(person_id: target.id, mentor_id: mentor.id, mentor_year: year, status: status)
    end
  end
end
