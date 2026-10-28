# frozen_string_literal: true

require "test_helper"

# Person › Mentoring: the ART walks below the Alpha sections, read-only, with
# no notes and no Send Message, and the Verdicts link for a reader who may open
# the ART's own mentoring pages.
class Person::MentoringControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 9, 3, 12, 0, 0)
    Rails.cache.clear
    Current.reset
    setup_art_mentoring
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")

    @mentee = create_person("Tinsel", last_seen_at: 1.day.ago)
    @mentor = create_person("Ferrous")
    entry = mentee_entry(@mentee, Time.zone.local(YEAR, 9, 1, 18, 0, 0))
    walk(entry, @mentor, status: PersonMentor::STATUS_BONK, notes: "Kept the dome cool")
  end

  test "the Alpha status select offers only the four Alpha verdicts" do
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_mentoring_path(@mentee)

    assert_select "select[name=?] option", "person_mentor_status_form[status]",
                  count: PersonMentor::ALPHA_STATUSES.size
  end

  test "an Admin sees the walk, the Verdicts link, and neither notes nor Send Message" do
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_mentoring_path(@mentee)
    assert_response :success
    assert_select "section", text: /#{YEAR} Green Dot Training Mentors/
    assert_select "a[href=?]", person_path(@mentor), text: "Ferrous"
    assert_select "span", text: "Bonked"
    assert_select "h6", text: "Shift"
    assert_select "a[href=?]", training_mentoring_verdicts_path("green-dot", year: YEAR), text: "View Verdicts"
    assert_no_match(/Kept the dome cool/, response.body)
    assert_select "a", text: "Send Message", count: 0

    get person_mentoring_path(@mentor)
    assert_select "section", text: /#{YEAR} Green Dot Training Mentees \(1 mentee\)/
    assert_select "a[href=?]", person_path(@mentee), text: "Tinsel"
    assert_select "span", text: "1 bonked"
    assert_select "span", text: "no contact allowed", count: 0
  end

  test "a Mentor without the ART's trainer role gets the walk but no Verdicts link" do
    mentor = person(:echelon_ranger)
    grant_role(mentor, Role::MENTOR)
    sign_in_as(mentor)

    get person_mentoring_path(@mentee)
    assert_response :success
    assert_select "section", text: /#{YEAR} Green Dot Training Mentors/
    assert_select "a[href=?]", training_mentoring_verdicts_path("green-dot", year: YEAR), count: 0
    assert_no_match(/Kept the dome cool/, response.body)
  end
end
