# frozen_string_literal: true

require "test_helper"

class MentorHelperTest < ActionView::TestCase
  include UiComponents::UiHeroPanelHelper
  include IconHelper

  Mentoring = Struct.new(:year, :current_status)
  MenteeEvent = Struct.new(:alphas)
  Subject = Struct.new(:callsign)

  PASSED = Mentoring.new(2019, PersonMentor::STATUS_PASS)
  NEVER_AN_ALPHA = Mentoring.new(nil, nil)
  TWO_YEARS = [MenteeEvent.new([1, 2, 3]), MenteeEvent.new([4])].freeze

  test "the self-serve description is one sentence whichever halves apply" do
    assert_equal "View your Alpha Shift mentors for 2019 and the 4 Alphas you've mentored across 2 years.",
                 me_mentoring_description(PASSED, TWO_YEARS)
    assert_equal "View your Alpha Shift mentors for 2019.", me_mentoring_description(PASSED, [])
    assert_equal "View the 1 Alpha you've mentored across 1 year.",
                 me_mentoring_description(NEVER_AN_ALPHA, [MenteeEvent.new([1])])
    assert_equal "", me_mentoring_description(NEVER_AN_ALPHA, [])
  end

  # An Alpha page offers four results and an ART roster all six (ruled
  # 2026-10-27), in one order.
  test "a result select offers the verdicts its page records" do
    assert_equal %w[Pending Passed Bonked Self-bonked],
                 mentor_result_options(PersonMentor::ALPHA_STATUSES).map(&:first)
    assert_equal ["Pending", "Passed", "Bonked", "Self-bonked", "Abstained", "Not completed"],
                 mentor_result_options(PersonMentor::STATUSES).map(&:first)
  end

  test "mentors are only offered to someone who passed" do
    bonked = Mentoring.new(2019, PersonMentor::STATUS_BONK)

    assert_equal "", me_mentoring_description(bonked, [])
  end

  test "the admin description is one sentence whichever halves apply" do
    hubcap = Subject.new("Hubcap")

    assert_equal "Hubcap's Alpha Shift mentors for 2019 and the 4 Alphas Hubcap has mentored across 2 years.",
                 person_mentoring_description(hubcap, PASSED, TWO_YEARS)
    assert_equal "Hubcap's Alpha Shift mentors for 2019.", person_mentoring_description(hubcap, PASSED, [])
    assert_equal "The 4 Alphas Hubcap has mentored across 2 years.",
                 person_mentoring_description(hubcap, NEVER_AN_ALPHA, TWO_YEARS)
    assert_equal "", person_mentoring_description(hubcap, NEVER_AN_ALPHA, [])
  end

  test "a callsign that opens the sentence keeps the casing it is stored with" do
    assert_equal "frankenstein's Alpha Shift mentors for 2019.",
                 person_mentoring_description(Subject.new("frankenstein"), PASSED, [])
  end

  # common/mentoring/index hands the description to hero_panel inside a String,
  # so whatever these return is escaped there. Returning it already escaped
  # printed "you&#39;ve" on the page.
  test "an apostrophe reaches the hero escaped once, not twice" do
    [me_mentoring_description(PASSED, TWO_YEARS),
     person_mentoring_description(Subject.new("O'Brien"), PASSED, TWO_YEARS)].each do |description|
      html = hero_panel(icon: "handshake", description: "#{description}") { |panel| panel.title { "Mentoring" } }

      assert_includes html, "&#39;"
      assert_not_includes html, "&amp;#39;"
    end
  end
end
