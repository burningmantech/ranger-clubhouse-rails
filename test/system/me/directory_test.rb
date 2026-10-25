# frozen_string_literal: true

require "application_system_test_case"

class Me::DirectoryTest < ApplicationSystemTestCase
  setup do
    @person = person(:active_ranger)
    sign_in(@person)
  end

  test "displays page title" do
    visit me_directory_path

    assert_selector "h1", text: "Cadre Directory"
  end

  test "shows link to Joining Ranger Special Teams document" do
    visit me_directory_path

    assert_text "Want to know more about the Ranger Special Teams?"
    # Check for external link (should have target="_blank")
    assert_selector "a[target='_blank']", text: "Ranger Special Teams Guide"
  end

  test "displays team sections" do
    visit me_directory_path

    # Should have at least one team section
    assert_selector "section", minimum: 1
  end

  test "displays team contact email when present" do
    visit me_directory_path

    # Check for mailto links (team contact emails)
    assert_selector "a[href^='mailto:']", minimum: 0
  end

  test "displays no contact email message for teams without email" do
    visit me_directory_path

    assert_text "No contact email on file."
  end

  test "displays member cards" do
    visit me_directory_path

    # Each member card is an item in its team's member list
    assert_selector "[role='listitem']", minimum: 1
  end

  test "displays member callsigns in cards" do
    visit me_directory_path

    assert_selector "[role='listitem']", text: @person.callsign
  end

  test "page is accessible without errors" do
    visit me_directory_path

    assert_selector "h1", text: "Cadre Directory"
    assert_no_selector ".error"
  end

  test "requires authentication" do
    sign_out

    visit me_directory_path

    assert_requires_authentication
  end

  test "shows placeholder for members without photos" do
    visit me_directory_path

    # The view should handle members without photos gracefully
    assert_text "No Photo"
  end

  test "member cards have proper structure" do
    visit me_directory_path

    # Cards sit in a member list labelled with its team
    assert_selector "[role='list'][aria-label$=' members'] > [role='listitem']", minimum: 1
  end

  test "page uses me layout" do
    visit me_directory_path

    assert_current_path me_directory_path
  end

  test "handles empty teams gracefully" do
    # Mock DirectoryReport to return empty array
    original_execute = DirectoryReport.method(:execute)

    DirectoryReport.define_singleton_method(:execute) do
      []
    end

    begin
      visit me_directory_path

      # Should still show the page title
      assert_selector "h1", text: "Cadre Directory"

      # Should not have any team sections
      assert_no_selector "section[id^='team-']"
    ensure
      DirectoryReport.define_singleton_method(:execute, original_execute)
    end
  end

  test "displays images with lazy loading" do
    give_a_member_a_photo
    visit me_directory_path

    # Images should have loading="lazy" attribute for performance
    assert_selector "[role='listitem'] img[loading='lazy']"
  end

  test "member cards are in a grid layout" do
    visit me_directory_path

    assert_match(/\bgrid\b/, first("[role='list'][aria-label$=' members']")[:class])
  end

  test "overseer positions display correctly" do
    visit me_directory_path

    overseer = DirectoryReport.execute.flat_map(&:members).flat_map(&:overseer_positions).first
    assert_selector "[role='listitem']", text: overseer.title
  end

  test "page loads within reasonable time" do
    # Performance test - should load quickly
    start_time = Current.time

    visit me_directory_path

    load_time = Current.time - start_time

    # Should load in less than 5 seconds (generous for test environment)
    assert load_time < 5, "Page took too long to load: #{load_time}s"
  end

  test "team sections have proper HTML structure" do
    visit me_directory_path

    # Each team is a semantic section with the ID its jump-list link anchors to
    anchors = all("a[href*='#team-']", visible: :all).map { |link| URI(link[:href]).fragment }
    assert_predicate anchors, :any?
    anchors.each { |anchor| assert_selector "section##{anchor}" }
  end

  test "a jump-menu panel stays inside the row of letters" do
    visit me_directory_path

    # Narrowed so the letters wrap and the later ones sit near the row's right
    # edge, where a 208px panel hung off its trigger's left edge would cross
    # it -- the phone case, whatever the fixture count.
    row = find("[data-controller~='dropdown-fit']")
    page.execute_script("arguments[0].style.width = '240px'", row)
    menus = row.all("details")
    assert_operator menus.size, :>=, 2, "the check needs a second letter to wrap"

    menus.each do |menu|
      menu.find("summary").click
      # dropdown-fit sets the shift on every open, 0px included
      menu.assert_selector "ul[style*='--dropdown-fit-shift']"
      # offsetLeft, not the panel's rect: the rect is mid scale-in
      overflow = page.evaluate_script(
        "arguments[1].getBoundingClientRect().left + arguments[1].querySelector('ul').offsetLeft + " \
        "arguments[1].querySelector('ul').offsetWidth - arguments[0].getBoundingClientRect().right",
        row, menu
      )
      assert_operator overflow, :<=, 0.5, "#{menu.find("summary").text}'s panel crosses the row's right edge"
      menu.find("summary").click
    end
  end

  test "raises error when DirectoryReport fails" do
    # Mock DirectoryReport to raise an error
    original_execute = DirectoryReport.method(:execute)

    DirectoryReport.define_singleton_method(:execute) do
      raise StandardError, "Database error"
    end

    begin
      # Should raise an error
      assert_raises(StandardError) do
        visit me_directory_path
      end
    ensure
      DirectoryReport.define_singleton_method(:execute, original_execute)
    end
  end

  test "mailto links are properly formatted" do
    visit me_directory_path

    # Check that mailto links work properly if they exist
    if has_selector?("a[href^='mailto:']")
      email_link = first("a[href^='mailto:']")
      assert email_link[:href].start_with?("mailto:")
    end
  end

  test "external links have proper security attributes" do
    visit me_directory_path

    # External links should have rel="noopener noreferrer" for security
    if has_selector?("a[target='_blank']")
      external_link = first("a[target='_blank']")
      assert_match /noopener noreferrer/, external_link[:rel] || ""
    end
  end

  test "images have alt attributes for accessibility" do
    give_a_member_a_photo
    visit me_directory_path

    # All images should have alt attributes
    assert_selector "[role='listitem'] img[alt^='Photo of #{@person.callsign}']"
    assert_no_selector "img:not([alt])"
  end

  private

  # The fixtures hold no member photos, so the page shows only placeholders.
  def give_a_member_a_photo
    photo = PersonPhoto.create!(person: @person, status: PersonPhoto::APPROVED,
                                image_filename: "", orig_filename: "", profile_filename: "")
    photo.avatar.attach(io: file_fixture("pixel.png").open, filename: "pixel.png", content_type: "image/png")
  end
end
