# frozen_string_literal: true

require "test_helper"

# Person › Mentoring: the ART walks below the Alpha sections, read-only, with
# no notes and no Send Message, and the Verdicts link for a reader who may open
# the ART's own mentoring pages.
class Person::MentoringControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include AlphaPositionTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include DomIdTestHelper
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

  test "the Alpha status select offers the three verdicts, never Pending or an ART-only one" do
    setup_alpha_position
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_mentoring_path(@mentee)

    assert_select "select[name=?] option", "person_mentor_status_form[status]", count: 3
    assert_select "select[name=?] option[value=?]", "person_mentor_status_form[status]",
                  PersonMentor::STATUS_PENDING, count: 0
  end

  test "a refused save shows its errors in that year's form and leaves the other years' forms alone" do
    setup_alpha_position
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    bonk = PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR - 1,
                                status: PersonMentor::STATUS_BONK)
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    # Pending is refused: the page lists no pending year, so the form would go with it.
    patch person_mentoring_update_path(@mentee, mentor_year: YEAR - 1),
          params: { person_mentor_status_form: { mentor_year: YEAR - 1, status: PersonMentor::STATUS_PENDING } }

    assert_response :unprocessable_entity
    assert_equal PersonMentor::STATUS_BONK, bonk.reload.status
    assert_select "#form-error-summary", count: 1
    assert_select "section", text: /#{YEAR - 1} Alpha Shift Mentors/ do
      assert_select "#form-error-summary"
    end
    assert_select "select##{YEAR}_person_mentor_status_form_status option[selected]", text: "Passed"

    patch person_mentoring_update_path(@mentee, mentor_year: YEAR - 1),
          params: { person_mentor_status_form: { mentor_year: YEAR - 1, status: PersonMentor::STATUS_PASS } }

    assert_redirected_to person_mentoring_path(@mentee)
    assert_equal PersonMentor::STATUS_PASS, bonk.reload.status
  end

  test "a refused save for a year the page does not list still says why" do
    setup_alpha_position
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    patch person_mentoring_update_path(@mentee, mentor_year: YEAR - 5),
          params: { person_mentor_status_form: { mentor_year: YEAR - 5, status: PersonMentor::STATUS_PASS } }

    assert_response :unprocessable_entity
    assert_select "#form-error-summary", count: 1, text: /no mentor records for that mentor year/
  end

  test "the person page lists a bonked year beside the passed one; /me lists the pass alone" do
    setup_alpha_position
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR, status: PersonMentor::STATUS_PASS)
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR - 1, status: PersonMentor::STATUS_BONK)
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR - 2,
                         status: PersonMentor::STATUS_SELF_BONK)
    PersonMentor.create!(person: @mentee, mentor: @mentor, mentor_year: YEAR - 3, status: PersonMentor::STATUS_PENDING)
    admin = person(:echelon_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_mentoring_path(@mentee)

    assert_select "section", text: /#{YEAR - 3} Alpha Shift Mentors/, count: 0
    [YEAR, YEAR - 1, YEAR - 2].each { |year| assert_select "section", text: /#{year} Alpha Shift Mentors/ }
    assert_select "section", text: /#{YEAR - 1} Alpha Shift Mentors/ do
      assert_select "span", text: "Bonked"
    end
    assert_select "span", text: "Self-bonked"
    assert_select "select[name=?]", "person_mentor_status_form[status]", count: 3
    assert_unique_dom_ids

    sign_in_as(@mentee)
    get me_mentoring_path

    assert_select "section", text: /#{YEAR} Alpha Shift Mentors/
    assert_select "section", text: /#{YEAR - 1} Alpha Shift Mentors/, count: 0
    assert_select "section", text: /#{YEAR - 2} Alpha Shift Mentors/, count: 0
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
    assert_select "h3", text: "Shift"
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
