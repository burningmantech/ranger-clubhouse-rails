# frozen_string_literal: true

require "test_helper"

class TeamsPositions::PositionSanityCheckerControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer

  INDEX = "/teams-positions/position-sanity-checker"

  # Every finding on this page is planted here rather than in test/fixtures:
  # the assertions are about exact sets, and a shared fixture another file grew
  # would quietly change them.
  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    grant_role(@admin, Role::ADMIN)

    # The subject of every revoke-band test. Revoking from @admin is refused on
    # purpose -- see "a revoke aimed at yourself is refused".
    @other = person(:ranger_with_custom_gender)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def check_path(key) = "#{INDEX}/#{key.to_s.dasherize}"

  def repair_path(key) = "#{check_path(key)}/repair"

  # An all_members position of a team, which is what the two team checks are
  # about. Fixture positions all default to the "public" category.
  def team_position(team, title)
    Position.create!(title:, team_id: team.id, active: true,
                     team_category: Position::TEAM_CATEGORY_ALL_MEMBERS)
  end

  # --- the gate ---

  test "an Event Management reader is refused" do
    reader = person(:echelon_ranger)
    grant_role(reader, Role::EVENT_MANAGEMENT)
    sign_in_as(reader)

    get INDEX
    assert_response :redirect
  end

  test "a Tech Ninja reads the board" do
    ninja = person(:inactive_ranger)
    grant_role(ninja, Role::TECH_NINJA)
    sign_in_as(ninja)

    get INDEX
    assert_response :success
  end

  test "the board lists every check" do
    get INDEX
    assert_response :success

    PositionSanityCheck::KEYS.each do |key|
      assert_select "a[href=?]", check_path(key), 1,
                    "the board is missing a row for #{key}"
    end
  end

  # A band's title says what to do, and the card says what is under each band on
  # the board. With every check clear there is no band, so there is no card.
  test "the card says what is under a band on the board, and a clear board has none" do
    get INDEX

    assert_select "h2", text: "Clear"
    assert_report_card count: 0

    bonked = person(:bonked_ranger)
    PersonPosition.create!(person_id: bonked.id, position_id: positions(:ood_position).id)
    get INDEX

    revoke = TeamsPositions::PositionSanityCheckerHelper::BAND_META[:revoke]
    assert_report_card
    assert_equal revoke[:what], card_answer("What is under “#{revoke[:title]}”?")
  end

  # Three parallel tables keyed by check key, plus a fourth keyed by band.
  # Without this they drift, and the first sign of it is a page raising KeyError
  # in front of a reader -- the board itself never touches COLUMNS or BAND_META
  # for a check that found nothing.
  test "every check has copy, columns, and a band" do
    helper = TeamsPositions::PositionSanityCheckerHelper

    assert_equal PositionSanityCheck::KEYS.sort, helper::CHECK_META.keys.sort
    assert_equal PositionSanityCheck::KEYS.sort, helper::COLUMNS.keys.sort
    assert_equal PositionSanityCheck::BANDS.sort, helper::BAND_META.keys.sort
  end

  # The blurb is the check page's hero description, which says one thing. What
  # the repair does is printed beside the button, so every check has to say it.
  test "every check's blurb is one sentence and every check says what its repair does" do
    TeamsPositions::PositionSanityCheckerHelper::CHECK_META.each do |key, meta|
      assert_equal 1, meta[:blurb].scan(/[.!?](?=\s|\z)/).size, "#{key}: #{meta[:blurb]}"
      assert_predicate meta[:repair], :present?, "#{key} has no repair: line"
    end
  end

  test "every check key resolves to a class under the namespace" do
    PositionSanityCheck::KEYS.each do |key|
      checker = PositionSanityCheck.checker(key)
      assert checker&.<(PositionSanityCheck::Base), "#{key} does not resolve to a check class"
    end
  end

  # const_get on a module searches Object, so a key naming a class that is not
  # defined here would hand back an unrelated top-level constant.
  test "a key naming a top-level constant is not a check" do
    assert_nil PositionSanityCheck.checker("person")
  end

  test "an unknown check lands back on the board with a reason" do
    get check_path(:not_a_check)

    assert_redirected_to INDEX
    assert_equal TeamsPositions::PositionSanityCheckerController::UNKNOWN_CHECK, flash[:error]
  end

  # --- deactivated accounts ---

  test "a deactivated account holding a position is found and stripped" do
    bonked = person(:bonked_ranger)
    PersonPosition.create!(person_id: bonked.id, position_id: positions(:ood_position).id)
    PersonTeam.create!(person_id: bonked.id, team_id: teams(:dirt_team).id)

    get check_path(:deactivated_accounts)
    assert_response :success
    assert_select "input[value=?]", bonked.id.to_s
    # What the repair does is out of the hero and beside the button that does it.
    meta = TeamsPositions::PositionSanityCheckerHelper::CHECK_META[:deactivated_accounts]
    assert_select "section.me-hero-panel", text: /#{Regexp.escape(meta[:repair])}/, count: 0
    assert_select "form", text: /#{Regexp.escape(meta[:repair])}/

    post repair_path(:deactivated_accounts), params: { keys: [bonked.id.to_s] }
    assert_response :unprocessable_entity

    assert_empty PersonPosition.where(person_id: bonked.id)
    assert_empty PersonTeam.where(person_id: bonked.id)
  end

  # Two positions in live data carry both all_rangers and new_user_eligible,
  # and both passes of the check reach them.
  test "a position carrying both flags is listed and granted once" do
    both = positions(:non_eligible_position)
    both.update!(all_rangers: true, new_user_eligible: true, active: true)

    finding = PositionSanityCheck::MissingPositions.findings.find { _1.person_id == @admin.id }
    assert_equal [[both.id, both.title]], finding.detail
  end

  # --- retired accounts ---

  test "a retired account keeps only the new-user positions" do
    retired = person(:retired_ranger)
    keeper = positions(:non_eligible_position)
    keeper.update!(new_user_eligible: true)
    extra = positions(:ood_position)
    PersonPosition.create!(person_id: retired.id, position_id: extra.id)

    get check_path(:retired_accounts)
    assert_response :success

    post repair_path(:retired_accounts), params: { keys: [retired.id.to_s] }
    assert_response :unprocessable_entity

    held = PersonPosition.where(person_id: retired.id).pluck(:position_id)
    assert_equal [keeper.id], held
  end

  # --- deactivated positions (grouped) ---

  test "a switched-off position is grouped under its title and revoked" do
    dead = positions(:ood_position)
    dead.update!(active: false)
    PersonPosition.create!(person_id: @other.id, position_id: dead.id)

    get check_path(:deactivated_positions)
    assert_response :success
    # ui_section titles are a div carrying role=heading rather than an <h2>.
    assert_select "[role=heading]", text: /#{Regexp.escape(dead.title)}/
    assert_select "[data-controller=scroll-to-top]", 0

    post repair_path(:deactivated_positions), params: { keys: ["#{@other.id}:#{dead.id}"] }
    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"

    assert_not PersonPosition.exists?(person_id: @other.id, position_id: dead.id)
  end

  # PersonPosition.remove_ids_from_person has no authorization guard, so an
  # Admin selecting everything on a revoke page could take away the position
  # granting their own Admin role and be locked out on the next request.
  test "a revoke aimed at yourself is refused" do
    dead = positions(:ood_position)
    dead.update!(active: false)
    PersonPosition.create!(person_id: @admin.id, position_id: dead.id)

    post repair_path(:deactivated_positions), params: { keys: ["#{@admin.id}:#{dead.id}"] }
    assert_response :unprocessable_entity

    assert PersonPosition.exists?(person_id: @admin.id, position_id: dead.id),
           "the repair took away the reader's own position"
    assert_select "body", text: /Repairing your own access here is not allowed/
  end

  # Granting yourself something your status or team already entitles you to is
  # not the hazard the guard above exists for.
  test "a grant aimed at yourself still goes through" do
    basic = positions(:non_eligible_position)
    basic.update!(all_rangers: true, active: true)

    post repair_path(:missing_positions), params: { keys: [@admin.id.to_s] }
    assert_response :unprocessable_entity

    assert PersonPosition.exists?(person_id: @admin.id, position_id: basic.id)
  end

  # --- deactivated teams (grouped) ---

  test "a switched-off team loses its members and their member positions" do
    dead = teams(:inactive_cadre)
    position = team_position(dead, "Inactive Cadre Member")
    # Public positions are open to the whole organization and are not the
    # team's to take away -- TeamMembershipReport::REVOCABLE_CATEGORIES is the
    # app's answer to what leaving a team costs, and Roster Management and Bulk
    # Teams both ask it.
    public_position = Position.create!(title: "Inactive Cadre Open House", team_id: dead.id,
                                       active: true, team_category: "public")
    PersonTeam.create!(person_id: @other.id, team_id: dead.id)
    PersonPosition.create!(person_id: @other.id, position_id: position.id)
    PersonPosition.create!(person_id: @other.id, position_id: public_position.id)

    get check_path(:deactivated_teams)
    assert_response :success

    post repair_path(:deactivated_teams), params: { keys: ["#{@other.id}:#{dead.id}"] }
    assert_response :unprocessable_entity

    assert_not PersonTeam.exists?(person_id: @other.id, team_id: dead.id)
    assert_not PersonPosition.exists?(person_id: @other.id, position_id: position.id)
    assert PersonPosition.exists?(person_id: @other.id, position_id: public_position.id),
           "the repair revoked a Public position the team does not own"
  end

  # --- Event Management Year Round ---

  test "a direct Event Management grant with nothing behind it is revoked" do
    grant_role(@other, Role::EVENT_MANAGEMENT)

    get check_path(:emyr)
    assert_response :success
    assert_select "input[value=?]", @other.id.to_s

    post repair_path(:emyr), params: { keys: [@other.id.to_s] }
    assert_response :unprocessable_entity

    assert_not PersonRole.exists?(person_id: @other.id, role_id: Role::EVENT_MANAGEMENT)
  end

  test "an Event Management grant backed by a team is left alone" do
    grant_role(@other, Role::EVENT_MANAGEMENT)
    team = teams(:dirt_team)
    PersonTeam.create!(person_id: @other.id, team_id: team.id)
    TeamRole.create!(team_id: team.id, role_id: Role::EVENT_MANAGEMENT)

    get check_path(:emyr)
    assert_response :success
    assert_select "input[value=?]", @other.id.to_s, 0
  end

  # Every other revoke check excludes deactivated accounts because those rows
  # belong to Deactivated Accounts. Without the same filter here the board
  # counted one person twice and the Emyr repair settled only half of them.
  test "a deactivated account with a direct grant is not an Event Management finding" do
    bonked = person(:bonked_ranger)
    grant_role(bonked, Role::EVENT_MANAGEMENT)

    get check_path(:emyr)
    assert_response :success
    assert_select "input[value=?]", bonked.id.to_s, 0
  end

  # --- missing basic positions ---

  test "an account short of an All Rangers position is granted it" do
    basic = positions(:non_eligible_position)
    basic.update!(all_rangers: true, active: true)

    get check_path(:missing_positions)
    assert_response :success
    assert_select "input[value=?]", @admin.id.to_s

    post repair_path(:missing_positions), params: { keys: [@admin.id.to_s] }
    assert_response :unprocessable_entity

    assert PersonPosition.exists?(person_id: @admin.id, position_id: basic.id)
  end

  # --- team positions ---

  test "a team member short of a basic team position is granted it" do
    team = teams(:dirt_team)
    position = team_position(team, "DIRT Member")
    PersonTeam.create!(person_id: @admin.id, team_id: team.id)

    get check_path(:team_positions)
    assert_response :success

    post repair_path(:team_positions), params: { keys: ["#{@admin.id}:#{position.id}"] }
    assert_response :unprocessable_entity

    assert PersonPosition.exists?(person_id: @admin.id, position_id: position.id)
  end

  test "a team position of a switched-off team is not offered" do
    dead = teams(:inactive_cadre)
    team_position(dead, "Inactive Cadre Member")
    PersonTeam.create!(person_id: @admin.id, team_id: dead.id)

    get check_path(:team_positions)
    assert_response :success
    assert_select "input[name='keys[]']", 0
  end

  # --- team membership ---

  test "holding a basic team position without the membership adds the team" do
    team = teams(:dirt_team)
    position = team_position(team, "DIRT Member")
    PersonPosition.create!(person_id: @admin.id, position_id: position.id)

    get check_path(:team_membership)
    assert_response :success

    post repair_path(:team_membership), params: { keys: ["#{@admin.id}:#{team.id}"] }
    assert_response :unprocessable_entity

    assert PersonTeam.exists?(person_id: @admin.id, team_id: team.id)
  end

  # --- shiny pennies ---

  test "a stale Shiny Penny loses the position and this year's Alpha gains it" do
    Position.create!(id: Position::DIRT_SHINY_PENNY, title: "Dirt - Shiny Penny", active: true)
    Position.create!(id: Position::ALPHA, title: "Alpha", active: true)

    stale = person(:inactive_ranger)
    PersonPosition.create!(person_id: stale.id, position_id: Position::DIRT_SHINY_PENNY)

    penny = person(:alpha_ranger)
    penny.update!(status: Person::ACTIVE)
    Timesheet.create!(person_id: penny.id, position_id: Position::ALPHA,
                      on_duty: Current.time - 6.hours, off_duty: Current.time - 1.hour,
                      additional_notes: "walked Alpha")

    get check_path(:shiny_pennies)
    assert_response :success

    post repair_path(:shiny_pennies), params: { keys: [stale.id.to_s, penny.id.to_s] }
    assert_response :unprocessable_entity

    assert_not PersonPosition.exists?(person_id: stale.id,
                                      position_id: Position::DIRT_SHINY_PENNY)
    assert PersonPosition.exists?(person_id: penny.id,
                                  position_id: Position::DIRT_SHINY_PENNY)
  end

  # --- the repair contract ---

  test "a key that is not a finding grants nothing" do
    team = teams(:dirt_team)
    position = team_position(team, "DIRT Member")

    # @admin is on no team, so this pair is not a finding. Upstream took the
    # position id from the browser and granted it regardless.
    post repair_path(:team_positions), params: { keys: ["#{@admin.id}:#{position.id}"] }
    assert_response :unprocessable_entity

    assert_not PersonPosition.exists?(person_id: @admin.id, position_id: position.id)
  end

  test "repairing nothing says so rather than reporting a repair" do
    post repair_path(:emyr), params: {}
    assert_response :unprocessable_entity
    assert_select "body", text: /Nothing Was Selected/
  end

  # The page cannot tell a row another Admin settled from a key that was never
  # a finding, so it must not name one of them as the cause.
  test "a skipped key is reported without blaming another Admin" do
    post repair_path(:emyr), params: { keys: %w[99999999 lolwat] }
    assert_response :unprocessable_entity

    assert_select "body", text: /no longer findings/
    assert_select "body", { text: /someone else repairs/, count: 0 }
  end
end
