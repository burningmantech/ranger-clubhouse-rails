# frozen_string_literal: true

require "test_helper"

class Mentoring::PotentialAlphasControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include ReportCardTestHelper # card_answer
  include ActiveSupport::Testing::TimeHelpers

  DENY_MESSAGE = "Admin or Mentor role required to view potential Alphas."

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # Status prospective, and carries a multi-year intake history in the
    # fixtures including a 2026 personnel_rank of 4 -- the flag that
    # quarantines a row.
    @prospective = person(:prospective_ranger)
    @alpha = person(:alpha_ranger)

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
    travel_back
  end

  # --- authorization -------------------------------------------------------

  test "admin can view potential alphas" do
    sign_in_as(@admin)

    get mentoring_potential_alphas_path

    assert_response :success
    assert_match "Potential Alphas", response.body
  end

  test "mentor can view potential alphas" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
  end

  # The VC role opens the /vc twin but has no business on the mentor page.
  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get mentoring_potential_alphas_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "detail frame requires the same roles" do
    sign_in_as(@outsider)

    get mentoring_potential_alphas_detail_path(@prospective)

    assert_redirected_to me_root_path
  end

  # --- the cohort split ----------------------------------------------------

  # Each cohort is split again by whether anything has been raised against the
  # person, so a mentor never has to pick the people needing a decision out of
  # the people who don't.
  test "each cohort gets a with-issues and a without-issues section" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
    Mentoring::PotentialAlphasHelper::SECTIONS.each do |section|
      assert_match section[:title], response.body
    end
    assert_equal 4, Mentoring::PotentialAlphasHelper::SECTIONS.size
    assert_match @prospective.callsign, response.body
    assert_match @alpha.callsign, response.body
  end

  # The stat box and the section it summarizes must never disagree -- both
  # count the display groups, not summary[:flagged], which is true for anyone
  # marked in any year rather than where they stand now.
  test "the with-issues stat boxes match their sections" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
    roster = Intake.retrieve_current_potentials(2026)
    Mentoring::PotentialAlphasHelper::COHORTS.each do |cohort, meta|
      status = (cohort == :alpha ? Person::ALPHA : Person::PROSPECTIVE)
      expected = roster.count do |row|
        row[:person].status == status &&
          Mentoring::PotentialAlphasHelper::ISSUE_GROUPS.include?(row[:group])
      end

      # A stat box renders as icon + value + label, so its text is the count
      # followed by the label.
      assert_select "div", text: meta[:issue_title] do |labels|
        assert_equal "#{expected}#{meta[:issue_title]}", labels.first.parent.text.strip
      end
    end
  end

  # The severity split survives inside the with-issues sections: a Personnel
  # flag quarantines someone and a rank 3/4 does not.
  test "the with-issues sections keep their severity subheadings" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
    assert_select "h3", text: /Personnel Flag Raised/
    # ...and the without-issues sections have nothing left to subdivide.
    assert_no_match(/No flags raised/, response.body)
  end

  test "each person is sorted into their own status cohort" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_includes cohort_ids(:prospective), @prospective.id
    assert_includes cohort_ids(:alpha), @alpha.id
    assert_not_includes cohort_ids(:alpha), @prospective.id
  end

  # The roster is current standing, so someone who has left the pipeline
  # entirely is gone -- unlike the /vc twin, which reads status history and
  # keeps them.
  test "someone who is no longer a prospective or alpha is not listed" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_no_match(/#{person(:past_prospective_ranger).callsign}/, response.body)
    assert_no_match(/#{person(:bonked_ranger).callsign}/, response.body)
  end

  # Moves everyone by the roster's own scope, so it holds whoever the fixtures
  # add later.
  test "says so plainly when no one holds either status" do
    Person.where(status: Intake::PNV_STATUSES).update_all(status: Person::ACTIVE)
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
    assert_select ".empty-state", text: "No one currently holds Prospective or Alpha status."
  end

  # only_flagged is off here: a clean record still belongs on the page.
  test "a prospective with no adverse marks is still listed" do
    sign_in_as(@mentor)
    clean = person(:prospective_ranger)
    PersonIntake.where(person_id: clean.id).delete_all
    PersonMentor.where(person_id: clean.id).delete_all

    get mentoring_potential_alphas_path

    assert_response :success
    assert_match clean.callsign, response.body
    assert_equal :other, group_for(clean)
  end

  test "a personnel-flagged prospective is quarantined into their own group" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_response :success
    assert_match "Personnel Flag Raised", response.body
    assert_equal :personnel, group_for(@prospective)
  end

  # --- year scoping --------------------------------------------------------

  # No year selector: the roster is who holds the status now, so honouring
  # ?year= would clip ranks and notes to a past year while still listing
  # today's Prospectives.
  test "the page ignores a year parameter" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(year: 2019)

    assert_response :success
    assert_match @prospective.callsign, response.body
    assert_match "Personnel Flag Raised", response.body
  end

  # --- the review pane -----------------------------------------------------

  # ?person= names the line whose history the pane shows. The line is marked,
  # brought into view, and its link carries the page's filters so selecting
  # someone does not drop them. No year rides along: this page has none.
  test "selecting a name fills the review pane" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_select "aside .empty-state", text: /Select a name/
    assert_select "li#person-#{@prospective.id} a[href=?]", mentoring_potential_alphas_path(person: @prospective.id)
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_no_match(/potential-alphas\?[^"]*year=/, response.body)

    get mentoring_potential_alphas_path(person: @prospective.id, training: "none")

    assert_response :success
    assert_select "li#person-#{@prospective.id} a[aria-current=true][href=?]",
                  mentoring_potential_alphas_path(person: @prospective.id, training: "none")
    assert_select "aside turbo-frame#uf-pane [data-review-id=?]", @prospective.id.to_s do
      assert_select "a", text: @prospective.callsign
    end
    # Upstream's mentorNotesOnly, in the pane as in the detail frame.
    assert_match(/Add Mentor Note/, response.body)
    assert_no_match(/Add VC Note/, response.body)
  end

  # Only a person on the page can be selected: a stale link shows the empty
  # pane rather than a history the list disowns, a person the filters hide is
  # not selected either, and an array-shaped param does not crash the page.
  test "only a person on the page can be selected" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(person: 999_999)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_select "aside .empty-state", text: /Select a name/

    get mentoring_potential_alphas_path(q: @alpha.callsign, person: @prospective.id)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0

    get mentoring_potential_alphas_path(person: ["1"])

    assert_response :success

    # An empty roster has no workspace to select in.
    Person.where(status: Intake::PNV_STATUSES).update_all(status: Person::ACTIVE)

    get mentoring_potential_alphas_path(person: @prospective.id)

    assert_response :success
    assert_select "aside.review-pane", count: 0
  end

  # Selecting a line loads only the pane's frame, which advances the URL; the
  # list stays put and review_pane_controller moves the selection. This page
  # answers that frame request itself, with the pane alone.
  test "a line loads only the pane" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(person: @prospective.id)

    assert_select "[data-controller=review-pane]" do
      assert_select "li#person-#{@prospective.id} a[data-turbo-frame=uf-pane][data-review-pane-target=line]" \
                    "[aria-current=true][data-review-id=?]", @prospective.id.to_s
      assert_select "aside.review-pane[data-review-pane-target=pane] " \
                    "turbo-frame#uf-pane[target=_top][data-turbo-action=advance] [data-review-id=?]", @prospective.id.to_s
    end

    get mentoring_potential_alphas_path(person: @prospective.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_select "turbo-frame#uf-pane [data-review-id=?]", @prospective.id.to_s
    assert_select "li[id^=person-]", count: 0
    assert_no_match "<html", response.body
  end

  # The card explains the pane and the chip in the words every pipeline page
  # shares, beside this page's own pair.
  test "the card explains the pane and the chip" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path

    assert_match(/Select a name/, card_answer("How do I read someone’s history?"))
    assert_match(/most serious mark/, card_answer("What is the colored chip on an entry?"))
    assert_match(/listed separately/, card_answer("Where are the people already made Alpha?"))
  end

  test "detail frame renders one person's history without the page chrome" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_detail_path(@prospective)

    assert_response :success
    assert_match "uf-frame-#{@prospective.id}", response.body
    assert_no_match "<html", response.body
  end

  # Turbo drives links descending from a frame; without target="_top" the note
  # form resolves to nothing and the writer gets turbo:frame-missing.
  test "the pane's frame lets its links navigate the whole page" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(person: @prospective.id)

    assert_match(/<turbo-frame[^>]*id="uf-pane"[^>]*target="_top"/, response.body)
  end

  # --- note writing --------------------------------------------------------

  # Upstream's mentorNotesOnly, reached through the per-team role map instead
  # of a flag: a Mentor may file a Mentor note and nothing else.
  test "a mentor is offered the mentor team only" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_detail_path(@prospective)

    assert_response :success
    assert_match "Add Mentor Note", response.body
    assert_no_match(/Add VC Note/, response.body)
    assert_no_match(/Add Personnel Note/, response.body)
  end

  test "add-note links carry the origin that returns here" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_detail_path(@prospective)

    assert_response :success
    assert_match "origin=mentoring", response.body
  end

  # With the person selected, not anchored: the page fills the pane and
  # scrolls to the line, where a #person-N would be dropped after the form's
  # submission.
  test "a note filed from here returns to this page with the person selected" do
    sign_in_as(@mentor)

    post person_intake_notes_path(@prospective, origin: "mentoring"),
         params: { intake_note_form: { type: "mentor", year: 2026, note: "Paired with Tinsel.", ranking: "" } }

    assert_redirected_to mentoring_potential_alphas_path(person: @prospective.id)
    assert_equal "Note saved.", flash[:success]
  end

  # --- filtering -----------------------------------------------------------

  test "search matches a callsign and drops everyone else" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(q: @prospective.callsign)

    assert_response :success
    assert_match @prospective.callsign, response.body
    assert_no_match(/#{@alpha.callsign}/, response.body)
  end

  test "the training filter keeps only that cohort" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(training: "none")

    assert_response :success
    assert_match @prospective.callsign, response.body

    get mentoring_potential_alphas_path(training: "trained")

    assert_response :success
    assert_no_match(/#{@prospective.callsign}/, response.body)
  end

  test "the flagged filter keeps only people carrying that team's mark" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(flagged: "personnel")

    assert_response :success
    assert_match @prospective.callsign, response.body
    # alpha_ranger has no intake rows at all, so no team has flagged them.
    assert_no_match(/#{@alpha.callsign}/, response.body)
  end

  # "0 Prospectives" beside "No one currently holds Prospective status" would
  # both be false while a filter is on -- the roster figures describe the
  # roster, and an emptied cohort says the filters emptied it.
  test "a filtered-out cohort says so and the stat boxes keep the roster count" do
    sign_in_as(@mentor)
    prospectives = Person.where(status: Person::PROSPECTIVE).count
    labels = Mentoring::PotentialAlphasHelper::COHORTS[:prospective]

    get mentoring_potential_alphas_path(q: @alpha.callsign)

    assert_response :success
    # Each emptied section names itself. Titles come from the constant rather
    # than being spelled out here, so renaming a section is not a test failure.
    assert_match "No #{labels[:issue_title].downcase} matched those filters.", response.body
    assert_match "No #{labels[:clear_title].downcase} matched those filters.", response.body
    # The reason that must NOT be given: the status is held by 114 people.
    assert_no_match(/#{labels[:empty]}/, response.body)
    assert_select "div", text: prospectives.to_s
  end

  test "filters that match no one say so instead of rendering an empty list" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(q: "nobodyisnamedthis")

    assert_response :success
    assert_match "matched those filters", response.body
    # The card describes the roster, not the filtered view, so the legend stays.
    assert_select "details dt", text: "What do the ranks mean?"
  end

  test "a filter chip drops just its own filter" do
    sign_in_as(@mentor)

    get mentoring_potential_alphas_path(q: @prospective.callsign, flagged: "personnel")

    assert_response :success
    # The chip that drops the search keeps the flagged filter, and neither
    # chip smuggles in a year -- this page has none.
    assert_match "flagged=personnel", response.body
    assert_no_match(/potential-alphas\?[^"]*year=/, response.body)
  end

  private

  def summaries
    @summaries ||= Intake.retrieve_current_potentials(2026)
  end

  def group_for(target)
    summaries.find { |row| row[:person].id == target.id }&.dig(:group)
  end

  def cohort_ids(cohort)
    status = (cohort == :alpha ? Person::ALPHA : Person::PROSPECTIVE)
    summaries.select { |row| row[:person].status == status }.map { |row| row[:person].id }
  end
end
