# frozen_string_literal: true

require "test_helper"

# Mentoring > Alpha Status: who the year's class is (read from the status audit
# trail, not from standing status), and which of the four action sections each
# person is sorted into.
class Mentoring::AlphaStatusControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include IntakeTestHelper
  include ReportCardTestHelper # card_answer
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to view Alpha status."

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @training = Position.create!(id: Position::TRAINING, title: "Training",
                                 type: Position::TYPE_TRAINING, active: true)
    @session = create_slot(@training, begins: Time.zone.local(YEAR, 3, 1, 9, 0, 0), description: "Bright Eyes")
    # Still to come at the travelled-to date, which is what makes a sign-up read
    # "pending" rather than "not passed".
    @upcoming = create_slot(@training, begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0), description: "Late Bloomers")

    # Carries a YEAR personnel_rank of 4 in the fixtures -- the flag that
    # quarantines a row into "Resolve first" whatever else is true of them.
    @flagged = person(:prospective_ranger)
    place_in_pipeline(@flagged, YEAR)
    pass(@flagged, @session)

    # Passed training, still a Prospective: the convertible set.
    @ready = create_prospective("Sparkplug")
    place_in_pipeline(@ready, YEAR)
    pass(@ready, @session)

    # Signed up, session has not ended.
    @signed_up = create_prospective("Turnstile")
    place_in_pipeline(@signed_up, YEAR)
    PersonSlot.create!(person_id: @signed_up.id, slot_id: @upcoming.id)

    # Sat a session and did not pass -- a different next action from either of
    # the two above, so it gets its own subheading.
    @failed = create_prospective("Dustpan")
    place_in_pipeline(@failed, YEAR)
    pass(@failed, @session, status: TraineeStatus::STATUS_NOT_PASSED)

    # No sign-up at all -- the chase list.
    @no_signup = create_prospective("Moonwrench")
    place_in_pipeline(@no_signup, YEAR)

    # Already converted. Clean record in the fixtures, so nothing else claims them.
    @alpha = person(:alpha_ranger)
    place_in_pipeline(@alpha, YEAR)
    place_in_pipeline(@alpha, YEAR, new_status: Person::ALPHA)

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

    get mentoring_alpha_status_path

    assert_response :success
    assert_match "#{YEAR} Alpha Status", response.body
  end

  test "a mentor can view the page" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_response :success
  end

  # The VC role opens the /vc twin but has no business on a mentor page.
  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get mentoring_alpha_status_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the detail frame requires the same roles" do
    sign_in_as(@outsider)

    get mentoring_alpha_status_detail_path(@flagged)

    assert_redirected_to me_root_path
  end

  # --- the roster ----------------------------------------------------------

  test "everyone who entered this year's class is listed" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_response :success
    [@flagged, @ready, @signed_up, @no_signup, @alpha].each do |target|
      assert_match target.callsign, response.body
    end
  end

  # The roster is the year's audit trail, not current standing -- which is what
  # separates this page from /mentoring/potential-alphas.
  test "a current prospective with no audit row this year is not listed" do
    sign_in_as(@mentor)
    stale = create_prospective("Driftwood")
    place_in_pipeline(stale, YEAR - 2)

    get mentoring_alpha_status_path

    assert_no_match(/#{stale.callsign}/, response.body)
  end

  # Upstream's exclude_bonks, which the Ember route always requests.
  test "someone who washed out during the same year is dropped" do
    sign_in_as(@mentor)
    bonked = create_prospective("Cinderblock")
    place_in_pipeline(bonked, YEAR)
    place_in_pipeline(bonked, YEAR, new_status: Person::BONKED)

    get mentoring_alpha_status_path

    assert_no_match(/#{bonked.callsign}/, response.body)
  end

  test "washing out in a later year does not drop someone from this year's class" do
    sign_in_as(@mentor)
    place_in_pipeline(@no_signup, YEAR + 1, new_status: Person::BONKED)

    get mentoring_alpha_status_path

    assert_match @no_signup.callsign, response.body
  end

  # Setup's class is YEAR's, so the next January has no one in it yet -- what
  # the page shows every year until its first Prospective.
  test "a year with no class yet says so" do
    travel_to Time.zone.local(YEAR + 1, 1, 15, 12, 0, 0) do
      sign_in_as(@mentor)

      get mentoring_alpha_status_path

      assert_response :success
      assert_select ".empty-state", text: "No one has been made a Prospective or an Alpha in #{YEAR + 1}."
    end
  end

  # --- the four sections ---------------------------------------------------

  test "every section title is rendered" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_response :success
    # Read off each section, not the page: the card names every title too.
    Mentoring::AlphaStatusHelper::SECTIONS.each do |section|
      assert_select "#alpha-status-#{section[:key]}", text: /#{Regexp.escape(section[:title])}/
    end
    assert_equal 4, Mentoring::AlphaStatusHelper::SECTIONS.size
  end

  test "the card says who is under each section" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    Mentoring::AlphaStatusHelper::SECTIONS.each do |section|
      assert_equal section[:who], card_answer("Who is under “#{section[:title]}”?")
    end
  end

  # The sections partition the roster: no one is dropped and no one is listed
  # twice. Worth asserting because both are silent failures -- the "Waiting on
  # training" subheadings key off Intake's training_status strings, so a new
  # status there would render a row nowhere while still counting in the badge.
  test "the sections between them render every person exactly once" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    rendered = Mentoring::AlphaStatusHelper::SECTIONS.flat_map { |section| section_ids(section[:key]) }
    assert_equal rendered.size, rendered.uniq.size
    assert_equal Intake.retrieve_year_class(YEAR).map { |summary| summary[:person].id }.sort, rendered.sort
  end

  test "each person lands in the section their standing calls for" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_equal :resolve, section_for(@flagged)
    assert_equal :ready, section_for(@ready)
    assert_equal :alpha, section_for(@alpha)
    assert_equal :waiting, section_for(@signed_up)
    assert_equal :waiting, section_for(@no_signup)
  end

  # First match wins: a raised concern outranks training standing, so a flagged
  # person appears once, under Resolve first.
  test "a flagged person is claimed by resolve first, whatever their training" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_equal "trained", summary_for(@flagged)[:training_status]
    assert_equal :resolve, section_for(@flagged)
    # The section they would otherwise have claimed, and who is actually in it.
    assert_equal [@ready.id], section_ids(:ready)
  end

  # The Shiny Penny case: made an Alpha, then made Active. Reading standing
  # status would drop them back into "ready for Alpha status" and tell a mentor
  # to convert a Ranger.
  test "an alpha since made active is still counted as having become an alpha" do
    sign_in_as(@mentor)
    @alpha.update_column(:status, Person::ACTIVE)

    get mentoring_alpha_status_path

    assert_equal :alpha, section_for(@alpha)
    assert_equal [@ready.id], section_ids(:ready)
  end

  test "waiting on training is split by how far off training is" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_select "h3", text: /No Training Sign-Up/
    assert_select "h3", text: /Signed Up for a Session/
    assert_select "h3", text: /Did Not Pass a Session/
    assert_equal "none", summary_for(@no_signup)[:training_status]
    assert_equal "pending", summary_for(@signed_up)[:training_status]
    assert_equal "not passed", summary_for(@failed)[:training_status]
    assert_equal :waiting, section_for(@failed)
  end

  test "resolve first keeps the severity subheadings" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_select "h3", text: /Personnel Flag Raised/
  end

  # --- counts --------------------------------------------------------------

  # Upstream's statusEligibleCount reads a field the API never sets, so it is
  # always 0 there. It is the "Ready for Alpha status" section here.
  test "the ready stat box counts the ready section" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_response :success
    assert_select "div", text: "Ready for Alpha Status" do |labels|
      assert_equal "1Ready for Alpha Status", labels.first.parent.text.strip
    end
  end

  test "the personnel flag callout names the flagged count" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_match "A Personnel Black Flag is raised on 1 person.", response.body
  end

  # Stat boxes describe the class; only the section badges follow the filter.
  test "filtering does not change the stat boxes" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(q: @no_signup.callsign)

    assert_response :success
    assert_match @no_signup.callsign, response.body
    assert_no_match(/#{@ready.callsign}/, response.body)
    assert_select "div", text: "Ready for Alpha Status" do |labels|
      assert_equal "1Ready for Alpha Status", labels.first.parent.text.strip
    end
  end

  # --- filters -------------------------------------------------------------

  test "the training filter narrows the roster" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(training: "none")

    assert_response :success
    assert_match @no_signup.callsign, response.body
    assert_no_match(/#{@ready.callsign}/, response.body)
  end

  test "the flagged filter selects on a raised personnel flag" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(flagged: "personnel")

    assert_response :success
    assert_match @flagged.callsign, response.body
    assert_no_match(/#{@ready.callsign}/, response.body)
  end

  test "a filter matching no one says so" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(q: "NoSuchCallsign")

    assert_response :success
    assert_match "No one in this year&#39;s class matched those filters.", response.body
  end

  # --- year scoping --------------------------------------------------------

  # No year selector, so a stray ?year= must not clip the ranks and notes on
  # rows the page is still listing.
  test "the page ignores a year parameter" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(year: 2019)

    assert_response :success
    assert_match "#{YEAR} Alpha Status", response.body
    assert_match @flagged.callsign, response.body
  end

  # --- the review pane -----------------------------------------------------

  # ?person= names the line whose history the pane shows. The line is marked,
  # brought into view, and its link carries the page's filters so selecting
  # someone does not drop them. No year rides along: this page has none.
  test "selecting a name fills the review pane" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_select "aside .empty-state", text: /Select a name/
    assert_select "li#person-#{@flagged.id} a[href=?]", mentoring_alpha_status_path(person: @flagged.id)
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_no_match(/alpha-status\?[^"]*year=/, response.body)

    get mentoring_alpha_status_path(person: @flagged.id, flagged: "personnel")

    assert_response :success
    assert_select "li#person-#{@flagged.id} a[aria-current=true][href=?]",
                  mentoring_alpha_status_path(person: @flagged.id, flagged: "personnel")
    assert_select "aside turbo-frame#uf-pane [data-review-id=?]", @flagged.id.to_s do
      assert_select "a", text: @flagged.callsign
    end
  end

  # Only a person on the page can be selected: a stale link shows the empty
  # pane rather than a history the list disowns, a person the filters hide is
  # not selected either, and an array-shaped param does not crash the page.
  test "only a person on the page can be selected" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(person: 999_999)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_select "aside .empty-state", text: /Select a name/

    get mentoring_alpha_status_path(q: @ready.callsign, person: @flagged.id)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0

    get mentoring_alpha_status_path(person: ["1"])

    assert_response :success

    # A year with no class has no workspace to select in.
    travel_to Time.zone.local(YEAR + 1, 1, 15, 12, 0, 0) do
      get mentoring_alpha_status_path(person: @flagged.id)

      assert_response :success
      assert_select "aside.review-pane", count: 0
    end
  end

  # Selecting a line loads only the pane's frame, which advances the URL; the
  # list stays put and review_pane_controller moves the selection. This page
  # answers that frame request itself, with the pane alone.
  test "a line loads only the pane" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path(person: @flagged.id)

    assert_select "[data-controller=review-pane]" do
      assert_select "li#person-#{@flagged.id} a[data-turbo-frame=uf-pane][data-review-pane-target=line]" \
                    "[aria-current=true][data-review-id=?]", @flagged.id.to_s
      assert_select "aside.review-pane[data-review-pane-target=pane] " \
                    "turbo-frame#uf-pane[target=_top][data-turbo-action=advance] [data-review-id=?]", @flagged.id.to_s
    end

    get mentoring_alpha_status_path(person: @flagged.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_select "turbo-frame#uf-pane [data-review-id=?]", @flagged.id.to_s
    assert_select "li[id^=person-]", count: 0
    assert_no_match "<html", response.body
  end

  # The card explains the pane and the chip in the words every pipeline page
  # shares, beside this page's own pairs.
  test "the card explains the pane and the chip" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_path

    assert_match(/Select a name/, card_answer("How do I read someone’s history?"))
    assert_match(/most serious mark/, card_answer("What is the colored chip on an entry?"))
    # The lines show no status: the card sends the reader to the pane for it.
    alpha = Mentoring::AlphaStatusHelper::SECTIONS.find { |section| section[:key] == :alpha }
    assert_match(/select a name and the status beside it says which/,
                 card_answer("Who is under “#{alpha[:title]}”?"))
  end

  test "the detail frame renders one person's history without the page chrome" do
    sign_in_as(@mentor)

    get mentoring_alpha_status_detail_path(@flagged)

    assert_response :success
    assert_match "uf-frame-#{@flagged.id}", response.body
    assert_no_match "<html", response.body
  end

  # Read-only: the two sibling pages are where a mentor writes. Even an Admin,
  # who may write every team's notes, gets no Add, Edit or Delete in the pane.
  test "no note controls are offered" do
    sign_in_as(@admin)

    get mentoring_alpha_status_detail_path(@flagged)

    assert_response :success
    assert_no_match(/Add .* Note/, response.body)

    get mentoring_alpha_status_path(person: @flagged.id)

    assert_response :success
    assert_select "aside", text: /No notes yet|Training/
    assert_no_match(/Add .* Note/, response.body)
    # Scoped to the pane: the navbar's own logout link is a Turbo delete too.
    assert_select "aside a", text: "Edit", count: 0
    assert_select "aside [data-turbo-method=delete]", count: 0
  end

  private

  # Read back off the rendered page rather than out of the controller: the
  # sections ARE the page, and re-deriving the rule here would only test a copy
  # of it. Rows carry id="person-N" and each section wraps them in its own id.
  def section_for(target)
    Mentoring::AlphaStatusHelper::SECTIONS.map { |section| section[:key] }.find do |key|
      css_select("#alpha-status-#{key} #person-#{target.id}").any?
    end
  end

  def section_ids(key)
    css_select("#alpha-status-#{key} [id^='person-']").map { |node| node["id"].delete_prefix("person-").to_i }
  end

  def summaries
    @summaries ||= Intake.retrieve_year_class(YEAR)
  end

  def summary_for(target)
    summaries.find { |summary| summary[:person].id == target.id }
  end

  def create_prospective(callsign)
    create_person(callsign, status: Person::PROSPECTIVE)
  end

  def pass(target, slot, status: TraineeStatus::STATUS_PASSED)
    PersonSlot.create!(person_id: target.id, slot_id: slot.id)
    TraineeStatus.create!(person_id: target.id, slot_id: slot.id, status:)
  end

  # The controller's own bucketing, read back off the rendered assigns.
end
