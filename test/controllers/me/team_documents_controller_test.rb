# frozen_string_literal: true

require "test_helper"

class Me::TeamDocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
    # person_team.yml puts active_ranger on khaki_team and not on dirt_team.
    @team = teams(:khaki_team)
  end

  def publish_document(team, body: "<p>Khaki hands out the radios.</p>")
    team.update_column(:resource_tag, "#{team.title.parameterize}-resources")
    Document.create!(tag: team.resource_tag, description: "#{team.title} Resources", body:,
                     person_create_id: @person.id, person_update_id: @person.id)
  end

  test "a member reads their team's document" do
    publish_document(@team, body: "<p>Khaki hands out the radios.</p><script>alert(1)</script>")

    get me_team_document_path(@team)

    assert_response :success
    assert_select ".lexxy-content script", count: 0
    assert_select ".lexxy-content", text: /Khaki hands out the radios\./
    assert_select "h1", text: /Khaki Delegation Document/
  end

  test "a team the person is not on is not found" do
    publish_document(teams(:dirt_team))

    get me_team_document_path(teams(:dirt_team))

    assert_response :not_found
  end

  test "a team with no document says so" do
    get me_team_document_path(@team)

    assert_response :success
    assert_match "Khaki Delegation has not published a team document yet.", response.body
  end

  # A tag that outlived its document reads the same as no tag at all.
  test "a team whose document was deleted says so" do
    @team.update_column(:resource_tag, "khaki-resources")

    get me_team_document_path(@team)

    assert_response :success
    assert_match "has not published a team document yet", response.body
  end

  # Team Records takes the pointer as typed, so a tag no team document may have --
  # a bookmark- page anyone can read without signing in -- is never served as one
  # (Document.resource_tag, as Team Resources follows it).
  test "a tag no team document may have reads as no document" do
    @team.update_column(:resource_tag, "#{Document::BOOKMARK_TAG_PREFIX}khaki")
    Document.create!(tag: @team.resource_tag, description: "Khaki Bookmark", body: "<p>Not for members.</p>",
                     person_create_id: @person.id, person_update_id: @person.id)

    get me_team_document_path(@team)

    assert_response :success
    assert_match "has not published a team document yet", response.body
    assert_no_match "Not for members.", response.body
  end

  test "the operational summary links only the teams that have a document" do
    # PersonEventInfo looks the In-Person Training position up by id.
    Position.create!(id: Position::TRAINING, title: "Training", type: Position::TYPE_TRAINING, active: true)
    publish_document(@team)

    get me_operational_summary_path

    assert_response :success
    assert_select "a[href=?]", me_team_document_path(@team), text: /View Team Document/
    assert_select "a[href=?]", me_team_document_path(teams(:council_cadre)), count: 0
  end
end
