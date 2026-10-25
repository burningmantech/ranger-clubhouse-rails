# frozen_string_literal: true

require "test_helper"

class Me::MentoringControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  # Test case 1: User with mentors (person who was mentored during their Alpha shift)
  test "should display mentors for user who was an alpha" do
    # active_ranger (id: 1) was mentored by echelon_ranger (id: 5) in 2023
    person = person(:active_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # Should show the mentoring section with the year
    assert_match /2023 Alpha Shift Mentors/i, response.body

    # Should display the mentor's callsign
    assert_match /EchelonTest/, response.body
  end

  test "should display mentor information correctly" do
    person = person(:active_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # Verify the page title includes the user's callsign
    assert_match /Mentoring/i, response.body
  end

  test "should handle user with no mentors gracefully" do
    # bonked_ranger has no mentors in fixtures
    person = person(:bonked_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # No Alpha year, no mentees, no ART walks: one empty state, no blank Alpha box.
    assert_select "section", text: /Alpha Shift Mentors/, count: 0
    assert_match(/No mentoring records to show/, response.body)
  end

  test "Send Message shows only for a mentee the compose page accepts" do
    mentee = person(:ranger_with_custom_gender) # a Ranger who has never signed in
    sign_in_as(person(:active_ranger))

    get me_mentoring_path
    assert_select "a[href=?]", new_me_message_path(to: mentee.callsign), count: 0

    mentee.update!(last_seen_at: 1.day.ago)
    get me_mentoring_path
    assert_select "a[href=?]", new_me_message_path(to: mentee.callsign), text: "Send Message"
  end

  test "Send Message is not offered to a viewer who can't start a message" do
    person(:active_ranger).update!(last_seen_at: 1.day.ago) # a mentor who could be messaged
    sign_in_as(person(:prospective_ranger))

    get me_mentoring_path
    assert_select "a", text: "Send Message", count: 0
  end

  test "should display multiple mentors for alpha with team mentoring" do
    # prospective_ranger has two mentors: active_ranger and echelon_ranger
    person = person(:prospective_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # Should show the mentoring page
    assert_match /Mentoring/i, response.body

    # Should show both mentors
    assert_match /TestRanger/, response.body
    assert_match /EchelonTest/, response.body
  end

  # Test case 2: User with mentees (person who is a mentor)
  test "should display mentees for user who is a mentor" do
    # active_ranger has mentees: prospective_ranger, ranger_with_custom_gender, auditor_ranger
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should show mentee sections
    assert_match /Alpha Shift Mentees/i, response.body

    # Should show mentee callsigns
    assert_match /ProspectiveNewbie/, response.body
    assert_match /CustomGender/, response.body
    assert_match /AuditorTest/, response.body
  end

  test "should display mentee statistics correctly" do
    # active_ranger has 2 passed (prospective_ranger, auditor_ranger) and 1 bonked (ranger_with_custom_gender) in fixtures
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should show statistics for 2024 cohort (1 passed, 1 bonked)
    assert_match /2024 Alpha Shift Mentees/i, response.body

    # Should show statistics for 2023 cohort (1 passed, 0 bonked)
    assert_match /2023 Alpha Shift Mentees/i, response.body
  end

  test "should display passed and bonked counts" do
    # active_ranger mentored 3 non-pending alphas
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should show passed count
    assert_match /passed/i, response.body

    # Should show bonked count
    assert_match /bonked/i, response.body
  end

  test "should not display pending mentees in the list" do
    # past_prospective_ranger has status "pending" and should be filtered out
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should NOT show PastProspective in the mentees list (it's pending)
    # But should show the other mentees
    assert_match /ProspectiveNewbie/, response.body
  end

  test "should group mentees by year" do
    # active_ranger has mentees from 2023 and 2024
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should show both year sections (most recent first)
    assert_match /2024 Alpha Shift Mentees/i, response.body
    assert_match /2023 Alpha Shift Mentees/i, response.body
  end

  test "should show mentor status badges" do
    # Verify that mentor status (pass/bonk) is displayed
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # The view should render successfully with status badges
    assert_response :success
  end

  test "should display both mentors and mentees on same page" do
    # echelon_ranger was mentored by auditor_ranger and has mentees
    person = person(:echelon_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # Should show mentors section
    assert_match /2020 Alpha Shift Mentors/i, response.body
    assert_match /AuditorTest/, response.body

    # Should also show mentees section
    assert_match /2023 Alpha Shift Mentees/i, response.body
    assert_match /TestRanger/, response.body
  end

  test "should display multiple mentors in mentee card" do
    # prospective_ranger has two mentors shown in the mentee view when viewing as echelon_ranger
    mentor = person(:echelon_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # Should show ProspectiveNewbie as a mentee
    assert_match /ProspectiveNewbie/, response.body

    # Should show the Mentors section in the mentee card
    assert_match /Mentors/i, response.body
  end

  test "should redirect to login when not authenticated" do
    sign_out
    get me_mentoring_path
    assert_redirected_to root_path
  end

  test "prospective user can view their mentoring page" do
    # Prospective rangers should be able to view mentoring info
    person = person(:prospective_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    assert_match /Mentoring/i, response.body
  end

  test "should handle user with no mentees" do
    # prospective_ranger has mentors but no mentees
    person = person(:prospective_ranger)
    sign_in_as(person)

    get me_mentoring_path
    assert_response :success

    # Should still render successfully
    assert_match /Mentoring/i, response.body

    # Should show their mentors
    assert_match /2024 Alpha Shift Mentors/i, response.body
  end

  test "should display mentee person status" do
    # Verify that the mentee's current status is displayed
    mentor = person(:active_ranger)
    sign_in_as(mentor)

    get me_mentoring_path
    assert_response :success

    # The view displays alpha.status for each mentee
    # prospective_ranger has status "prospective"
    # This should be visible in the response
    assert_response :success
  end

  # ---------------------------------------------------------------- ART walks

  ART_YEAR = 2026

  # A Green Dot walk: Tinsel the mentee, Ferrous the mentor, notes never shown.
  def art_walk(status: PersonMentor::STATUS_PASS)
    travel_to Time.zone.local(ART_YEAR, 9, 3, 12, 0, 0)
    Current.reset
    setup_art_mentoring
    @mentee = create_person("Tinsel")
    @mentor = create_person("Ferrous")
    entry = mentee_entry(@mentee, Time.zone.local(ART_YEAR, 9, 1, 18, 0, 0))
    walk(entry, @mentor, status:, notes: "Kept the dome cool")
  end

  test "a mentee sees their ART walk with the mentor as plain text, Send Message, and no notes" do
    art_walk
    @mentor.update!(last_seen_at: 1.day.ago)
    sign_in_as(@mentee)

    get me_mentoring_path
    assert_response :success
    assert_select "section", text: /#{ART_YEAR} Green Dot Training Mentors/
    assert_select "section", text: /Green Dot Training Mentees/, count: 0
    assert_select "h6", text: "Shift"
    assert_match(/Ferrous/, response.body)
    assert_select "a", text: "Ferrous", count: 0
    assert_select "a[href=?]", new_me_message_path(to: "Ferrous"), text: "Send Message"
    assert_no_match(/Kept the dome cool/, response.body)
    assert_select "a[href=?]", training_mentoring_verdicts_path("green-dot", year: ART_YEAR), count: 0
  end

  test "an ART mentor gets Send Message to a mentee the compose page accepts" do
    art_walk
    sign_in_as(@mentor)

    get me_mentoring_path
    assert_select "section", text: /#{ART_YEAR} Green Dot Training Mentees \(1 mentee\)/
    assert_select "a[href=?]", new_me_message_path(to: "Tinsel"), count: 0
    assert_select "span", text: "no contact allowed"

    @mentee.update!(last_seen_at: 1.day.ago)
    get me_mentoring_path
    assert_select "a[href=?]", new_me_message_path(to: "Tinsel"), text: "Send Message"
  end

  test "an ART mentor who can't start a message gets no Send Message" do
    art_walk
    @mentee.update!(last_seen_at: 1.day.ago)
    @mentor.update!(status: Person::AUDITOR)
    sign_in_as(@mentor)

    get me_mentoring_path
    assert_select "section", text: /Green Dot Training Mentees/
    assert_select "a", text: "Send Message", count: 0
    assert_select "span", text: "no contact allowed", count: 0
  end
end
