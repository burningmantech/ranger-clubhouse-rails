# frozen_string_literal: true

require "application_system_test_case"

# A link to a place on the same page is the browser's to follow, not Turbo's
# (application.js, turbo:click): Turbo 8.0.23 would fetch the page again and
# replace it. Me › Trainer/Mentor Feedback's jump links are the case tested.
class Me::FeedbackTest < ApplicationSystemTestCase
  include SurveyTestHelper

  YEAR = 2026

  test "a jump link scrolls to its survey without Turbo fetching the page again" do
    setup_survey_positions
    trainer = person(:active_ranger)
    bay = create_slot(@dirt, begins: Time.zone.local(YEAR, 6, 6, 9), description: "Bay Area, CA")
    trainees = create_survey(position: @dirt, year: YEAR, title: "#{YEAR} Training Feedback")
    peers = create_survey(position: @dirt, year: YEAR, type: Survey::TRAINER, title: "#{YEAR} Trainer Feedback")
    [trainees, peers].each do |survey|
      group = create_survey_group(survey, title: "About You", type: SurveyGroup::TYPE_TRAINER)
      create_survey_answer(create_survey_question(survey, group), person: person(:echelon_ranger), trainer:,
                                                                  slot: bay)
    end

    sign_in(trainer)
    visit me_feedback_path
    # Flags on <html>, which outlives a Turbo render: one for a Turbo visit of
    # any kind, one for the browser's own move to a fragment.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-visit", () => document.documentElement.dataset.turboVisit = "1")
      window.addEventListener("hashchange", () => document.documentElement.dataset.hashChange = "1")
    JS
    click_link peers.title

    assert_selector "html[data-hash-change]"
    assert_no_selector "html[data-turbo-visit]"
    assert_equal "#survey-#{peers.id}", page.evaluate_script("window.location.hash")
  end
end
