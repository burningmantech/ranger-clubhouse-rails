# frozen_string_literal: true

require "test_helper"

class TeamsPositions::PositionGrantsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  CONTROLLER = TeamsPositions::PositionGrantsController
  HELPER = TeamsPositions::PositionGrantsHelper
  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:retired_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    # Built here rather than in test/fixtures because this file asserts on exact
    # counts: a shared fixture another file grew would silently change them.
    @held = positions(:council_manager)          # active_ranger holds it (fixture)
    @held.update!(type: Position::TYPE_HQ)

    @everyone = Position.create!(title: "Test All Rangers", active: true,
                                 type: Position::TYPE_FRONTLINE, all_rangers: true)
    @accounts = Position.create!(title: "Test All Accounts", active: true,
                                 type: Position::TYPE_TRAINING, new_user_eligible: true)
    @retired = Position.create!(title: "Test Retired Position", active: false,
                                type: Position::TYPE_OTHER)
    @retired_held = Position.create!(title: "Test Retired But Held", active: false,
                                     type: Position::TYPE_OTHER)

    # A deceased holder: invisible under the default status filter, which is the
    # point of the filter, and findable by asking for that status by name.
    PersonPosition.create!(person_id: person(:deceased_ranger).id, position_id: @held.id)
    PersonPosition.create!(person_id: @admin.id, position_id: @retired_held.id)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Every person the "all Rangers" flag expects to hold a position.
  def ranger_pool = Person.where(status: CONTROLLER::ALL_RANGERS_POOL)

  def rendered_position_ids
    css_select("a[id^=position-]").map { |row| row["id"].delete_prefix("position-").to_i }
  end

  def row_for(position)
    css_select("a#position-#{position.id}").first
  end

  def row_text(position) = row_for(position)&.text&.gsub(/\s+/, " ")

  # ---------------------------------------------------------------- access

  test "denies access without the admin or event management role" do
    sign_in_as(@outsider)
    get teams_positions_position_grants_path

    assert_redirected_to me_root_path
  end

  test "allows event management" do
    sign_in_as(@event_manager)
    get teams_positions_position_grants_path

    assert_response :success
  end

  test "denies the roster page without a role" do
    sign_in_as(@outsider)
    get teams_positions_position_grants_position_path(@held)

    assert_redirected_to me_root_path
  end

  # ----------------------------------------------------------------- index

  test "lists positions with their grant counts" do
    get teams_positions_position_grants_path

    assert_response :success
    assert_select "h1", /Position Grants/
    # The deceased holder is filtered out by the default status; the admin is not.
    assert_match(/1 person/, row_text(@held))
    assert_unique_dom_ids
  end

  test "keeps an inactive position that somebody holds and drops the one no one does" do
    get teams_positions_position_grants_path

    ids = rendered_position_ids
    assert_includes ids, @retired_held.id
    assert_not_includes ids, @retired.id
  end

  test "flags the people missing a position every ranger should hold" do
    get teams_positions_position_grants_path

    assert_match(/#{ranger_pool.count} unassigned/, row_text(@everyone))
    assert_match(/every Ranger expected/, row_text(@everyone))
    assert_match(/every account expected/, row_text(@accounts))
  end

  test "counts on-site holders separately" do
    person(:deceased_ranger).update_column(:on_site, true)
    @admin.update_column(:on_site, true)

    get teams_positions_position_grants_path

    assert_match(/1 on site/, row_text(@held))
  end

  # --------------------------------------------------------------- filters

  test "narrows by position type" do
    get teams_positions_position_grants_path(type: Position::TYPE_FRONTLINE)

    ids = rendered_position_ids
    assert_includes ids, @everyone.id
    assert_not_includes ids, @held.id
  end

  test "offers a jump link to every position on screen" do
    get teams_positions_position_grants_path(type: Position::TYPE_OTHER)

    shown = rendered_position_ids
    assert_includes shown, @retired_held.id

    # By href rather than the partial's chrome: the navbar carries daisyUI
    # dropdowns of its own, and "dropdown-content" catches those too.
    jumps = css_select("a[href^='#position-']").map { |link| link["href"] }
    assert_equal shown.map { |id| "#position-#{id}" }.sort, jumps.sort,
                 "the scroll list should name the filtered rows, no more and no fewer"
  end

  test "the default status filter hides locked-out holders and naming one finds them" do
    get teams_positions_position_grants_path

    assert_match(/1 person/, row_text(@held))

    get teams_positions_position_grants_path(status: Person::DECEASED)

    assert_match(/1 person/, row_text(@held))

    get teams_positions_position_grants_path(status: ALL)

    assert_match(/2 people/, row_text(@held))
  end

  test "the unassigned count ignores the status filter" do
    expected = /#{ranger_pool.count} unassigned/

    get teams_positions_position_grants_path
    assert_match expected, row_text(@everyone)

    get teams_positions_position_grants_path(status: Person::ACTIVE)
    assert_match expected, row_text(@everyone)
  end

  test "the on-site filter narrows the unassigned pool too" do
    get teams_positions_position_grants_path(on_site: HELPER::ON_SITE_ONLY)

    assert_no_match(/unassigned/, row_text(@everyone).to_s)
  end

  test "hides positions with no one matching when asked to" do
    get teams_positions_position_grants_path(status: Person::AUDITOR, matching: HELPER::MATCHING_ONLY)

    assert_not_includes rendered_position_ids, @held.id
  end

  test "an unknown status falls back to the rangering default rather than narrowing nothing" do
    get teams_positions_position_grants_path(status: "nonsense")

    assert_response :success
    assert_match(/1 person/, row_text(@held))
    assert_select "a", text: /Status: Rangering statuses/
  end

  test "clearing the filters asks for every status rather than dropping the param" do
    get teams_positions_position_grants_path(type: Position::TYPE_HQ)

    assert_select "a", text: /Clear All Filters/ do |links|
      assert_match(/status=all/, links.first["href"])
    end
  end

  # A chip has to spell its value the way the control that set it did, and "HQ"
  # titleizes to "Hq".
  test "a chip spells its type the way the select does" do
    get teams_positions_position_grants_path(type: Position::TYPE_HQ)

    assert_select "a", text: /Type: #{Position::TYPE_HQ}/
  end

  # Scoped to the help text itself rather than the page: the status select lists
  # every status by name a few lines below it, so a page-wide match would pass
  # on a sentence that named none of them.
  test "the status help text names every status the default hides" do
    get teams_positions_position_grants_path

    help = css_select("div").map(&:text).find { |text| text.start_with?("Rangering statuses leaves out") }
    assert help, "the status filter should explain what the Rangering default hides"

    (Person::ALL_STATUSES - CONTROLLER::RANGERING_STATUSES).each do |status|
      assert_includes help, status, "the status help should name #{status} as hidden"
    end
  end

  # ------------------------------------------------------------------ show

  test "shows the roster and carries the filters back to the index" do
    get teams_positions_position_grants_position_path(@held, type: Position::TYPE_HQ)

    assert_response :success
    assert_select "#member-#{@admin.id}"
    assert_select "#member-#{person(:deceased_ranger).id}", false,
                  "the default status filter should leave the deceased holder off the roster"
    # The default status is a real filter, so Back returns to it rather than to
    # the wider "every status" list the reader was not looking at.
    assert_select "a[href=?]", teams_positions_position_grants_path(type: Position::TYPE_HQ,
                                                                    status: HELPER::STATUS_RANGERING)
    assert_unique_dom_ids
  end

  test "lists the people missing an all-rangers position" do
    get teams_positions_position_grants_position_path(@everyone)

    assert_response :success
    assert_select "#unassigned-#{@admin.id}"
    assert_select "h1", /Test All Rangers/
  end

  test "a position no one is expected to hold gets no unassigned section" do
    get teams_positions_position_grants_position_path(@held)

    assert_select "[id^=unassigned-]", false
  end

  test "exports the roster the page is showing" do
    get teams_positions_position_grants_position_path(@held, format: :csv)

    assert_response :success
    assert_equal "Callsign,Status", response.body.lines.first.chomp
    assert_match(/^#{@admin.callsign},active$/, response.body)
    assert_no_match(/#{person(:deceased_ranger).callsign}/, response.body)

    get teams_positions_position_grants_position_path(@held, status: ALL, format: :csv)

    assert_match(/#{person(:deceased_ranger).callsign}/, response.body)
  end

  test "an unknown position is not found" do
    get teams_positions_position_grants_position_path(0)

    assert_response :not_found
  end
end
