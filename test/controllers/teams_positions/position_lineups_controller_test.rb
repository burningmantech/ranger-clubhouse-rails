# frozen_string_literal: true

require "test_helper"

class TeamsPositions::PositionLineupsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @mentor = positions(:mentor_lead)
    @training = positions(:training_lead)

    @lineup = PositionLineup.create!(description: "Mentor and Mentee")
    PositionLineupMember.create!(position_lineup_id: @lineup.id, position_id: @mentor.id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "denies access without the admin or tech ninja role" do
    sign_in_as(@outsider)

    get teams_positions_position_lineups_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Tech Ninja role required to manage position lineups.", flash[:error]
  end

  test "allows access with only the tech ninja role" do
    sign_in_as(@tech_ninja)

    get teams_positions_position_lineups_path

    assert_response :success
  end

  # ----------------------------------------------------------------- index

  test "index lists each lineup with its positions and an edit link" do
    get teams_positions_position_lineups_path

    assert_response :success
    assert_select "*", text: @lineup.description
    assert_select "*", text: @mentor.title
    assert_select "a[href=?]", teams_positions_edit_position_lineup_path(@lineup)
  end

  test "index shows an empty state when no lineups exist" do
    PositionLineupMember.delete_all
    PositionLineup.delete_all

    get teams_positions_position_lineups_path

    assert_response :success
    assert_select "*", text: /No position lineups have been added yet/
  end

  # ------------------------------------------------------------ new / create

  test "new renders the form with every position offered" do
    get teams_positions_new_position_lineup_path

    assert_response :success
    assert_select "input[type=checkbox][name=?][value=?]", "position_lineup[position_ids][]", @training.id.to_s
    # The row is the label, so min-h-9 is what makes the 36px tap target.
    assert_select "label.min-h-9 input[name=?]", "position_lineup[position_ids][]"
  end

  # The picker has to say which lineup already holds a position, or the reader
  # only learns of the clash after submitting.
  test "the form marks a position that already belongs to another lineup" do
    get teams_positions_new_position_lineup_path

    assert_response :success
    assert_select "*", text: /in #{@lineup.description}/
  end

  test "create saves a lineup with its members" do
    assert_difference "PositionLineup.count", 1 do
      post teams_positions_create_position_lineup_path,
           params: { position_lineup: { description: "Green Dot Pair",
                                        position_ids: [@training.id.to_s] } }
    end

    assert_redirected_to teams_positions_position_lineups_path
    lineup = PositionLineup.find_by(description: "Green Dot Pair")
    assert_equal [@training.id], PositionLineupMember.where(position_lineup_id: lineup.id).pluck(:position_id)
  end

  test "create re-renders with an error when the description is blank" do
    assert_no_difference "PositionLineup.count" do
      post teams_positions_create_position_lineup_path,
           params: { position_lineup: { description: "", position_ids: [] } }
    end

    assert_response :unprocessable_entity
  end

  # Upstream's insertOrIgnore silently drops the position and reports success.
  test "create refuses a position that already belongs to another lineup" do
    assert_no_difference "PositionLineup.count" do
      post teams_positions_create_position_lineup_path,
           params: { position_lineup: { description: "Rival Lineup",
                                        position_ids: [@mentor.id.to_s] } }
    end

    assert_response :unprocessable_entity
    assert_select "*", text: /belongs to one lineup at a time/
    assert_equal @lineup.id, PositionLineupMember.find_by(position_id: @mentor.id).position_lineup_id
  end

  # ----------------------------------------------------------- edit / update

  test "edit renders the form with the lineup's current members checked" do
    get teams_positions_edit_position_lineup_path(@lineup)

    assert_response :success
    assert_select "input[type=checkbox][name=?][value=?][checked]",
                  "position_lineup[position_ids][]", @mentor.id.to_s
  end

  test "update changes the description and the membership" do
    patch teams_positions_position_lineup_path(@lineup),
          params: { position_lineup: { description: "Renamed Lineup",
                                       position_ids: [@training.id.to_s] } }

    assert_redirected_to teams_positions_position_lineups_path
    assert_equal "Renamed Lineup", @lineup.reload.description
    assert_equal [@training.id], PositionLineupMember.where(position_lineup_id: @lineup.id).pluck(:position_id)
  end

  test "update with no positions empties the lineup" do
    patch teams_positions_position_lineup_path(@lineup),
          params: { position_lineup: { description: @lineup.description, position_ids: [] } }

    assert_empty PositionLineupMember.where(position_lineup_id: @lineup.id)
  end

  test "position ids that are not ids are reported, not dropped" do
    patch teams_positions_position_lineup_path(@lineup),
          params: { position_lineup: { description: @lineup.description, position_ids: ["", "abc"] } }

    assert_response :unprocessable_entity
    assert_match "were not submitted correctly", response.body
    assert_equal [@mentor.id], PositionLineupMember.where(position_lineup_id: @lineup.id).pluck(:position_id)
  end

  # --------------------------------------------------------------- destroy

  test "destroy removes the lineup but not its positions" do
    delete teams_positions_position_lineup_path(@lineup)

    assert_redirected_to teams_positions_position_lineups_path
    assert_not PositionLineup.exists?(@lineup.id)
    assert Position.exists?(@mentor.id)
  end
end
