# frozen_string_literal: true

require "test_helper"

# Characterization net for the dashboard deepening refactor.
#
# The Milestones -> Dashboard -> task -> partial pipeline had no tests. This drives the
# REAL pipeline end-to-end for each person archetype and asserts it renders without error.
# It does not assert exact steps (that is the job of the fast seam-level unit tests); its
# purpose is to catch nil/crash regressions in the wiring as tasks move onto DashboardFacts.
class Me::DashboardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TrainingSlotTestHelper
  include DomIdTestHelper
  include MegaMenuTestHelper

  # NOTE: most archetypes can't be rendered from fixtures alone (the pipeline pulls
  # ~40 records + settings the fixtures don't supply) — that untestability is exactly
  # what the deepening fixes, and the real coverage lives in the seam-level unit tests
  # (dashboard_test.rb, *_task_test.rb). These few render cleanly and guard the
  # controller -> from_milestones -> Dashboard -> view wiring across the refactor.
  ARCHETYPES = %i[
    past_prospective_ranger
    bonked_ranger
  ].freeze

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset
  end

  ARCHETYPES.each do |fixture_name|
    test "dashboard renders without error for #{fixture_name}" do
      sign_in_as(person(fixture_name))
      get me_root_path
      assert_response :success
    end
  end

  # DashboardTasks::MissingBpguid fires for any non-auditor with a blank bpguid and
  # renders dashboard_tasks/_missing_bpguid. The partial was missing, so every such
  # person got a 500 on /me. Guards the task -> partial pairing.
  test "dashboard renders the missing Burner Profile task for a blank bpguid" do
    ranger = person(:active_ranger)
    ranger.update!(bpguid: "")

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "body", text: /Link Your Burner Profile/
  end

  # Upstream's DashboardLinks: the status-picked links document, under the task groups.
  test "dashboard renders the Links & Things document" do
    ranger = person(:active_ranger)
    Document.create!(tag: Document::DASHBOARD_LINKS_RANGER_TAG, description: "Dashboard links",
                     body: %(<p><a href="https://example.com/manual">Ranger Manual</a></p>),
                     person_create_id: ranger.id, person_update_id: ranger.id)

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "section#links-and-things", text: /Links & Things/
    assert_select ".lexxy-content a[href=?]", "https://example.com/manual", text: "Ranger Manual"
  end

  # Each task group renders its steps as a collection of its own, so an id built
  # from the step counter repeated from the second group on. The step cards must
  # sit in two groups, or no id could collide.
  test "dashboard repeats no DOM id across its task groups" do
    sign_in_as(person(:active_ranger))
    get me_root_path

    assert_response :success
    groups_with_steps = css_select("article").map { |card| card.ancestors("section").first }.uniq
    assert_operator groups_with_steps.size, :>=, 2
    assert_unique_dom_ids
  end

  # A screen reader moves through the page by heading, so none may sit more than
  # one level below the heading before it: the hero h1; progress, announcements
  # and each task group h2; each step h3.
  test "dashboard headings never skip a level" do
    sign_in_as(person(:active_ranger))
    get me_root_path

    assert_response :success
    levels = css_select("main h1, main h2, main h3, main h4, main h5, main h6, main [role=heading]")
               .map { |heading| (heading["aria-level"] || heading.name.delete_prefix("h")).to_i }
    assert_empty levels.each_cons(2).select { |above, below| below > above + 1 },
                 "heading levels in page order: #{levels.join(" ")}"
    assert_select "main section article h3", minimum: 2
  end

  # The In-Person Training partials read the session from facts.training.slot.
  # Training::EducationInfo has no date or location, so reading either raised
  # and /me 500'd for anyone whose training read FAIL.
  test "dashboard renders a failed In-Person Training with its session" do
    ranger = sign_up_for_in_person_training(begins: Time.zone.local(2026, 4, 11, 9, 0, 0),
                                            status: TraineeStatus::STATUS_NOT_PASSED)

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "p", text: /Training incomplete on Saturday, April 11, 2026/
    assert_select "p", text: "Location: Playa"
  end

  # Same crash on the common path: a session signed up for and not yet held.
  test "dashboard renders a pending In-Person Training with its session" do
    ranger = sign_up_for_in_person_training(begins: Time.zone.local(2026, 5, 2, 9, 0, 0))

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "b", text: "Sat May 2 @ 09:00"
    assert_match "Can't make it?", response.body
  end

  # Still inside the grace period, so the status reads pending -- but the session
  # is over, so the card says so instead of offering to reschedule it.
  test "dashboard tells a trainee awaiting a result that their session has ended" do
    ranger = sign_up_for_in_person_training(begins: Time.zone.local(2026, 4, 15, 9, 0, 0))

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "b", text: "Your training session has ended."
    assert_select "b", text: "Wed Apr 15 @ 09:00"
    assert_no_match "Can't make it?", response.body
  end

  # A trainer marked a no-show on the only session they signed up to teach.
  test "dashboard renders a missed In-Person Training teaching session" do
    ranger, slot, teaching = sign_up_to_teach_in_person_training(begins: Time.zone.local(2026, 4, 11, 9, 0, 0))
    TrainerStatus.create!(person: ranger, slot:, trainer_slot: teaching, status: TrainerStatus::STATUS_NO_SHOW)

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "p", text: /Missed teaching on Saturday, April 11, 2026/
  end

  # Nobody has marked the trainer yet. Before the session they are teaching it;
  # after it, they are told it has ended rather than that they are teaching it.
  test "dashboard tells an unmarked trainer they are teaching an upcoming session" do
    ranger, = sign_up_to_teach_in_person_training(begins: Time.zone.local(2026, 5, 2, 9, 0, 0))

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "b", text: "You're teaching this session."
    assert_match "Can't make it?", response.body
  end

  test "dashboard tells an unmarked trainer their teaching session has ended" do
    ranger, = sign_up_to_teach_in_person_training(begins: Time.zone.local(2026, 4, 11, 9, 0, 0))

    sign_in_as(ranger)
    get me_root_path

    assert_response :success
    assert_select "b", text: "Your teaching session has ended."
    assert_select "b", text: "You're teaching this session.", count: 0
    assert_no_match "Can't make it?", response.body
  end

  private

  # active_ranger holding In-Person Training with the online course done.
  def hold_in_person_training
    ranger = person(:active_ranger)
    person_online_course(:active_ranger_training_2026).update!(completed_at: Time.zone.local(2026, 4, 2))
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    PersonPosition.create!(person: ranger, position: training)
    [ranger, training]
  end

  # ...and signed up for one session, scored with +status+ when given.
  def sign_up_for_in_person_training(begins:, status: nil)
    ranger, training = hold_in_person_training
    slot = create_slot(training, begins:)
    PersonSlot.create!(person_id: ranger.id, slot_id: slot.id)
    TraineeStatus.create!(person: ranger, slot:, status:) if status
    ranger
  end

  # ...or signed up to teach one, with no trainer status recorded yet.
  def sign_up_to_teach_in_person_training(begins:)
    ranger, training = hold_in_person_training
    trainer = Position.create!(id: Position::TRAINER, title: "Trainer",
                               type: Position::TYPE_TRAINING, active: true)
    slot = create_slot(training, begins:)
    teaching = create_slot(trainer, begins:)
    PersonSlot.create!(person_id: ranger.id, slot_id: teaching.id)
    [ranger, slot, teaching]
  end
  # The first-sign-in tour: step templates for the onboarding controller until
  # the person has taken it, the id a step points at on the Links & Things
  # section, and the account menu's replay. ?tour=1 replays without recording.
  test "dashboard offers the tour to a person who has not taken it, and not again after" do
    ranger = person(:active_ranger)
    sign_in_as(ranger)

    get me_root_path
    assert_response :success
    assert_select "[data-controller=onboarding][data-onboarding-url-value=?]", me_onboarded_path, count: 1
    assert_select "[data-controller=onboarding] template[data-onboarding-target=step]", minimum: 5
    assert_select "[data-controller=onboarding] template[data-title=?]", "Welcome, Ranger #{ranger.callsign}"
    assert_select "[data-controller=onboarding] template[data-element='#links-and-things > [role=heading]']", count: 1
    assert_select "[data-controller=onboarding] template[data-onboarding-target=toast]", count: 1
    assert_includes response.body, "Tour complete. Replay it any time from the Account menu."
    assert_select "ul[aria-label='User menu'] a[href='/me?tour=1']", text: "Replay Onboarding", minimum: 1

    # ?tour=1 by someone never recorded is a recording run, not a replay.
    get me_root_path(tour: 1)
    assert_select "[data-controller=onboarding][data-onboarding-url-value=?]", me_onboarded_path, count: 1

    ranger.update_column(:on_boarded_at, Current.time)
    get me_root_path
    assert_select "[data-controller=onboarding]", count: 0

    get me_root_path(tour: 1)
    assert_select "[data-controller=onboarding]:not([data-onboarding-url-value])", count: 1
  end

  # The Menu step points at the navbar's Menu button, which a person with
  # nothing beyond My Clubhouse does not have (MegaMenu.offered?).
  test "the tour has a Menu step only for a person the menu is offered to" do
    ranger = person(:active_ranger)
    sign_in_as(ranger)
    menu_step = "[data-controller=onboarding] template[data-element='#menu-open, #menu-open-phone']"

    get me_root_path
    assert_response :success
    assert_select menu_step, count: 0
    assert_select "#menu-open", count: 0

    offer_mega_menu_to(ranger)
    get me_root_path
    assert_response :success
    assert_select menu_step, count: 1
    assert_select "#menu-open", count: 1
  end

  test "dashboard offers neither the tour nor its replay to a bonked person" do
    sign_in_as(person(:bonked_ranger))

    get me_root_path

    assert_response :success
    assert_select "[data-controller=onboarding]", count: 0
    assert_select "a[href='/me?tour=1']", count: 0
  end

  # The first-sign-in tour (me/dashboard/_onboarding) reports that it ran, however
  # it ended. A tour timestamp is not an audit event: no action log row, and no
  # validation pass over the row.
  test "the onboarding endpoint marks the person toured and logs nothing" do
    ranger = person(:active_ranger)
    assert_nil ranger.on_boarded_at

    sign_in_as(ranger)
    assert_no_difference -> { ActionLog.count } do
      patch me_onboarded_path
    end

    assert_response :no_content
    assert_equal Time.zone.local(2026, 4, 16, 12, 0, 0), ranger.reload.on_boarded_at
  end
end

# Contract test for the in-memory adapter — the test-only sibling of
# +DashboardFacts.from_milestones+. Asserts each archetype produces a frozen,
# coherent DashboardFacts whose status routes Dashboard#type to the intended branch.
class DashboardFactsFactoryTest < ActiveSupport::TestCase
  test "active_ranger routes to :ranger and is frozen" do
    facts = DashboardFactsFactory.for(:active_ranger)
    assert facts.frozen?
    assert_equal Dashboard::TYPE_RANGER, Dashboard.new(facts).type
  end

  test "echelon routes to :ranger (echelon branch) and is frozen" do
    facts = DashboardFactsFactory.for(:echelon)
    assert facts.frozen?
    assert facts.is_echelon
    assert_equal Dashboard::TYPE_RANGER, Dashboard.new(facts).type
  end

  test "auditor routes to :auditor and is frozen" do
    facts = DashboardFactsFactory.for(:auditor)
    assert facts.frozen?
    assert_equal Dashboard::TYPE_AUDITOR, Dashboard.new(facts).type
  end

  test "applicant_prospective routes to :applicant and is frozen" do
    facts = DashboardFactsFactory.for(:applicant_prospective)
    assert facts.frozen?
    assert_equal Dashboard::TYPE_APPLICANT, Dashboard.new(facts).type
  end

  test "auditor_offseason routes to :auditor in the off-season and is frozen" do
    facts = DashboardFactsFactory.for(:auditor_offseason)
    assert facts.frozen?
    assert_equal DashboardTask::AFTER_EVENT, facts.period
    assert_equal Dashboard::TYPE_AUDITOR, Dashboard.new(facts).type
  end

  test "ticketing_open_ranger routes to :ranger with an open ticketing package" do
    facts = DashboardFactsFactory.for(:ticketing_open_ranger)
    assert facts.frozen?
    assert_equal "open", facts.ticketing_period
    assert_not_nil facts.ticketing_package
    assert_equal Dashboard::TYPE_RANGER, Dashboard.new(facts).type
  end

  test "survey_bearing_ranger routes to :ranger with outstanding surveys" do
    facts = DashboardFactsFactory.for(:survey_bearing_ranger)
    assert facts.frozen?
    assert facts.surveys.sessions.present?
    assert facts.surveys.trainers.present?
    assert facts.surveys.alpha_survey
    assert_equal Dashboard::TYPE_RANGER, Dashboard.new(facts).type
  end

  test "overrides win over archetype defaults" do
    facts = DashboardFactsFactory.for(:active_ranger, period: DashboardTask::AFTER_EVENT)
    assert_equal DashboardTask::AFTER_EVENT, facts.period
  end

  test "rejects unknown archetypes" do
    assert_raises(ArgumentError) { DashboardFactsFactory.for(:bogus) }
  end
end

# View-render coverage that fixtures cannot reach: drives the real partial chain
# (Dashboard -> _dashboard_group -> _dashboard_step -> dashboard_tasks/*) from a
# hand-built DashboardFacts, proving every fact a partial reads now comes off the seam.
class DashboardRenderTest < ActionView::TestCase
  include ApplicationHelper
  include DashboardHelper
  include IconHelper
  include UrlHelper
  include UiComponents::UiSectionHelper
  include UiComponents::UiAccentCardHelper
  include UiComponents::BadgeHelper

  # Render every dashboard step a dashboard produces through the production
  # _dashboard_step -> dashboard_tasks/* partial chain. The factory supplies the
  # duck-typed rich objects each selected partial reads, so a clean render proves
  # no partial NoMethodErrors against the seam. Each render's output is joined
  # here because `rendered` holds only the last one (Rails 8.1.4).
  def render_dashboard_steps(facts)
    dashboard = Dashboard.new(facts)
    steps = Array(dashboard.groups).flat_map(&:steps)

    steps.each_with_index.filter_map do |step, index|
      next if step.partial.blank?

      render(
        partial: "common/dashboard_step",
        locals: {
          step:,
          step_counter: index,
          group: nil,
          facts:,
          total_steps: steps.length
        }
      )
    end.join
  end

  test "active_ranger dashboard renders the whole task chain without error" do
    assert render_dashboard_steps(DashboardFactsFactory.for(:active_ranger)).present?
  end

  test "auditor dashboard renders the whole task chain without error" do
    assert render_dashboard_steps(DashboardFactsFactory.for(:auditor)).present?
  end

  test "applicant_prospective dashboard renders the whole task chain without error" do
    assert render_dashboard_steps(DashboardFactsFactory.for(:applicant_prospective)).present?
  end

  test "echelon dashboard renders the whole task chain without error" do
    assert render_dashboard_steps(DashboardFactsFactory.for(:echelon)).present?
  end

  # --- #2-gap coverage: archetypes that reach the previously-unrendered partials ---

  test "auditor offseason renders the ranger_interest signup" do
    html = render_dashboard_steps(DashboardFactsFactory.for(:auditor_offseason))
    assert html.present?
    assert_includes html, "Interested in becoming a Ranger?"
    # _ranger_interest_signup reads step.payload.year
    assert_includes html, (Time.zone.now.year + 1).to_s
  end

  test "ticketing-open ranger renders the dashboard_tickets partial" do
    html = render_dashboard_steps(DashboardFactsFactory.for(:ticketing_open_ranger))
    assert html.present?
    # _dashboard_tickets reads step.payload.tickets and renders the claimed item.
    assert_includes html, "Go To Tickets &amp; Stuff"
  end

  test "survey-bearing ranger renders the survey partials" do
    html = render_dashboard_steps(DashboardFactsFactory.for(:survey_bearing_ranger))
    assert html.present?
    assert_includes html, "Quick feedback on your training:"
    assert_includes html, "Quick feedback on your Alpha shift"
    assert_includes html, "Thanks for teaching!"
  end

  # Mentoring sessions are listed with the training ones. Sent as a training
  # survey, a mentoring one is never found, and the reader gets "Survey not found."
  test "a mentoring session links to its own kind of survey" do
    mentoring = Survey::SurveySession.new(id: 301, type: Survey::MENTOR_FOR_MENTEES,
                                          begins: "2026-08-30 10:00:00", description: "Burn Night",
                                          position_id: 3, position_title: "Green Dot Mentor")
    surveys = Survey::UnansweredResult.new(sessions: [mentoring], trainers: nil, alpha_survey: nil)

    html = render_dashboard_steps(DashboardFactsFactory.for(:survey_bearing_ranger, surveys:))
    hrefs = Nokogiri::HTML5.fragment(html).css("a").map { |link| link["href"] }

    assert_includes hrefs, me_surveys_path(slot_id: 301, type: Survey::MENTOR_FOR_MENTEES)
  end

  # As upstream, the course launch sits beside each ART that has an online
  # course, and says it came from an ART so the page can say where that course is.
  test "an ART with an online course links to the Online Course page" do
    arts = [
      Training::EducationInfo.new(status: Training::NO_SHIFT, position_title: "Green Dot Training", has_online_course: true),
      Training::EducationInfo.new(status: Training::NO_SHIFT, position_title: "Tow Truck Training", has_online_course: false)
    ]

    html = render_dashboard_steps(DashboardFactsFactory.for(:active_ranger, art_trainings: arts))
    hrefs = Nokogiri::HTML5.fragment(html).css("a").map { |link| link["href"] }

    assert_equal 1, hrefs.count(me_online_course_path(art: 1))
  end
end
