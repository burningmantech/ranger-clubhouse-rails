# frozen_string_literal: true

require "application_system_test_case"

class Me::AwardsTest < ApplicationSystemTestCase
  # Each trophy card is a plain bordered div (see app/views/common/_trophies.html.erb)
  CARD = ".border.rounded"

  setup do
    @person = person(:active_ranger)
    sign_in(@person)
  end

  test "viewing awards index shows page title" do
    visit me_awards_path

    assert_selector "h1", text: "Service Recognition"
  end

  test "awards index shows informational callouts" do
    visit me_awards_path

    assert_selector ".box-accent-info h4", text: "What These Awards Recognize"
    assert_text "Year-round volunteer efforts and special roles"
    assert_selector ".box-accent-warning h4", text: "Data Completeness Notice"
    assert_text "Many currently reflect activity only from 2020 onward"
  end

  test "awards index shows all three section headings when awards exist" do
    visit me_awards_path

    assert_selector "h3", text: "Cadre / Delegation and Selected Team Recognition"
    assert_selector "h3", text: "Special Position Recognition"
    assert_selector "h3", text: "Special Service Recognition"
  end

  test "awards index displays team awards" do
    visit me_awards_path

    assert_text "Khaki Delegation"
    assert_text "2020 - 2021, 2023"

    within award_card("Khaki Delegation") do
      assert_text(/service years/i)
      assert_text "2020 - 2021, 2023"
    end
  end

  test "awards index displays DIRT team award" do
    visit me_awards_path

    assert_text "DIRT Team"

    within award_card("DIRT Team") do
      assert_text "2022"
      assert_text(/service years/i)
    end
  end

  test "awards index displays position awards" do
    visit me_awards_path

    assert_text "Training Lead"

    within award_card("Training Lead") do
      assert_text "2021 - 2022"
      assert_text(/service years/i)
    end
  end

  test "awards index displays OOD position without service years" do
    visit me_awards_path

    assert_text "OOD (Officer of the Day)"

    within award_card("OOD (Officer of the Day)") do
      assert_text "2023"
      assert_text "no service years"
    end
  end

  test "awards index displays special service awards" do
    visit me_awards_path

    assert_text "Outstanding Service Award"

    within award_card("Outstanding Service Award") do
      assert_text "2020"
      assert_text(/service years/i)
    end

    assert_text "Volunteer Excellence"

    within award_card("Volunteer Excellence") do
      assert_text "2022"
      assert_text "no service years"
    end
  end

  test "awards index shows award icons" do
    visit me_awards_path

    assert_selector "i.fa-award", minimum: 1, visible: :all
  end

  test "awards index shows no awards message when user has no awards" do
    sign_out
    person_without_awards = person(:prospective_ranger)
    sign_in(person_without_awards)

    visit me_awards_path

    assert_selector ".empty-state", text: "No service recognition awards have been granted yet"
    assert_no_text "Cadre / Delegation and Selected Team Recognition"
  end

  test "awards cards are displayed in a flex layout" do
    visit me_awards_path

    assert_selector ".flex.flex-col #{CARD}", minimum: 1
  end

  test "each award card has proper structure" do
    visit me_awards_path

    within award_card("Khaki Delegation") do
      # Award icon badges flanking the title
      assert_selector "i.fa-award", minimum: 1, visible: :all

      # Title
      assert_text "Khaki Delegation"

      # Award years, prominently styled
      assert_selector ".font-bold", text: "2020 - 2021, 2023"

      # Service years block
      assert_text(/service years/i)
    end
  end

  test "year ranges are formatted correctly" do
    visit me_awards_path

    # Consecutive years should show as range
    assert_text "2020 - 2021, 2023" # Khaki (2020, 2021, 2023)

    # Two consecutive years should show as range
    assert_text "2021 - 2022" # Training Lead (2021, 2022)

    # Single year should show as is
    assert_text "2022" # DIRT Team (2022)
  end

  test "awards are grouped by category" do
    visit me_awards_path

    # Each section should contain appropriate awards
    within_section "Cadre / Delegation and Selected Team Recognition" do
      assert_text "Khaki Delegation"
      assert_text "DIRT Team"
    end

    within_section "Special Position Recognition" do
      assert_text "Training Lead"
      assert_text "OOD (Officer of the Day)"
    end

    within_section "Special Service Recognition" do
      assert_text "Outstanding Service Award"
      assert_text "Volunteer Excellence"
    end
  end

  test "awards with service years show separate service years section" do
    visit me_awards_path

    within award_card("Khaki Delegation") do
      assert_text(/service years/i)
      assert_text "2020 - 2021, 2023"
    end
  end

  test "awards without service years show muted text" do
    visit me_awards_path

    within award_card("Volunteer Excellence") do
      assert_selector ".me-muted.italic", text: "no service years"
    end
  end

  test "awards page renders without errors" do
    visit me_awards_path

    assert_current_path me_awards_path
    assert_selector "h1", text: "Service Recognition"
    assert_no_selector ".error"
  end

  test "awards are sorted alphabetically within each category" do
    visit me_awards_path

    # Card titles are the classless divs in each card's title row
    team_titles = section_content("Cadre / Delegation and Selected Team Recognition")
                    .all("#{CARD} > .flex > div:not([class])").map(&:text)

    assert_equal team_titles.sort, team_titles, "Team awards should be sorted alphabetically"
  end

  test "awards show correct background styling" do
    visit me_awards_path

    # Icon badges carry the amber award styling
    assert_selector ".ring-signature-edge", minimum: 1
  end

  test "empty category sections show appropriate message" do
    # Create a user with only team awards (no position or special awards)
    sign_out
    person_with_limited_awards = create_person("LimitedAwards")

    # Create only a team award for this person
    PersonAward.create!(
      person: person_with_limited_awards,
      team: teams(:khaki_team),
      year: 2023,
      awards_grants_service_year: true,
      notes: "Test award",
      creator_person_id: person_with_limited_awards.id
    )

    sign_in(person_with_limited_awards)
    visit me_awards_path

    # Should show team awards
    within_section "Cadre / Delegation and Selected Team Recognition" do
      assert_text "Khaki Delegation"
    end

    # Should show "no awards" for other categories
    within_section "Special Position Recognition" do
      assert_text "No special positions awards have been granted yet"
    end

    within_section "Special Service Recognition" do
      assert_text "No special service awards have been granted yet"
    end
  end

  private

  def award_card(title)
    find(CARD, text: title)
  end

  # Section content (card grid or empty state) is the element immediately
  # following the section's h3 heading — there is no wrapping container.
  def section_content(heading)
    find("h3", text: heading).find(:xpath, "following-sibling::*[1]")
  end

  def within_section(heading, &block)
    within(section_content(heading), &block)
  end
end
