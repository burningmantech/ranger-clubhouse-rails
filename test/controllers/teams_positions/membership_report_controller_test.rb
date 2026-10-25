# frozen_string_literal: true

require "test_helper"

class TeamsPositions::MembershipReportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper
  # The summary line is built with pluralize; the expectations spell it the same
  # way rather than hard-coding plurals that only hold for the current fixtures.
  include ActionView::Helpers::TextHelper

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @team = teams(:dirt_team)            # two members and a manager, below
    @unmanaged = teams(:operations_team) # one member, deliberately no manager
    @empty = teams(:non_eligible_team)   # no members, no managers
    @inactive = teams(:inactive_cadre)

    # Memberships are built here rather than in test/fixtures because this file
    # asserts on exact counts: a shared fixture another test file grew would
    # silently change every count assertion here.
    PersonTeam.create!(team_id: @team.id, person_id: @admin.id)
    PersonTeam.create!(team_id: @team.id, person_id: person(:retired_ranger).id)
    PersonTeam.create!(team_id: @unmanaged.id, person_id: @admin.id)
    TeamManager.create!(team_id: @team.id, person_id: person(:inactive_ranger).id)

    @active_count = Team.where(active: true).count

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # The drill-down rows, in the order the page drew them. Counts are read back
  # out of each row's meta text -- a manager count of zero is not printed at all
  # (the badge says it instead), so no match reads as 0, which is correct.
  def rendered_rows
    css_select("a[id^=team-]").map do |row|
      text = row.text.gsub(/\s+/, " ")
      { id: row["id"].delete_prefix("team-").to_i,
        members: text[/(\d+) members?/, 1].to_i,
        managers: text[/(\d+) managers?/, 1].to_i }
    end
  end

  def rendered_team_ids = rendered_rows.map { |row| row[:id] }

  # ---------------------------------------------------------------- access

  test "denies access without the admin or event management role" do
    sign_in_as(@outsider)
    get teams_positions_membership_report_path

    assert_redirected_to me_root_path
  end

  test "denies the roster page without the admin or event management role" do
    sign_in_as(@outsider)
    get teams_positions_membership_report_team_path(@team)

    assert_redirected_to me_root_path
  end

  test "admits event management without the admin role" do
    sign_in_as(@event_manager)
    get teams_positions_membership_report_path

    assert_response :success
  end

  # ---------------------------------------------------------------- index

  test "lists every active team and no inactive one" do
    get teams_positions_membership_report_path

    assert_response :success
    assert_equal Team.where(active: true).order(:title).ids, rendered_team_ids
    assert_select "#team-#{@inactive.id}", false,
                  "an inactive team is off the report by definition"
    assert_unique_dom_ids
  end

  test "reports each team's member and manager counts" do
    get teams_positions_membership_report_path

    rows = rendered_rows.index_by { |row| row[:id] }

    assert_equal({ members: 2, managers: 1 }, rows[@team.id].slice(:members, :managers))
    assert_equal({ members: 1, managers: 0 }, rows[@unmanaged.id].slice(:members, :managers))
    assert_equal({ members: 0, managers: 0 }, rows[@empty.id].slice(:members, :managers))
  end

  # A zero manager count is left out of the meta text because the row's badge
  # already says it; printing both says the same thing twice.
  test "omits the manager count from a row that has none" do
    get teams_positions_membership_report_path

    assert_select "#team-#{@unmanaged.id}", text: /1 member/
    assert_select "#team-#{@unmanaged.id}", { text: /0 managers/, count: 0 },
                  "the No managers badge carries this, not the meta line"
  end

  test "summarises the listed teams in one line" do
    get teams_positions_membership_report_path

    memberships = PersonTeam.where(team_id: Team.where(active: true).select(:id))

    assert_select "span", text: "#{@active_count} teams · " \
                                "#{pluralize(memberships.count, "membership")} · " \
                                "#{pluralize(memberships.distinct.count(:person_id), "person")} · " \
                                "#{@active_count - 1} without managers"
  end

  test "flags a team with no managers" do
    get teams_positions_membership_report_path

    assert_select "#team-#{@unmanaged.id}", text: /No managers/
    assert_select "#team-#{@team.id}", text: /No managers/, count: 0
  end

  # ---------------------------------------------------------------- filters

  # The summary line sits directly above these rows, so every number in it has
  # to describe the filtered set, not the whole report.
  test "narrows to teams without managers, and the summary line narrows with it" do
    get teams_positions_membership_report_path(managers: "missing")

    assert_response :success
    assert_not_includes rendered_team_ids, @team.id, "the managed team is filtered out"
    assert_includes rendered_team_ids, @unmanaged.id
    assert_equal @active_count - 1, rendered_team_ids.size

    shown_memberships = rendered_rows.sum { |row| row[:members] }
    expected = "#{@active_count - 1} of #{@active_count} teams · " \
               "#{pluralize(shown_memberships, "membership")} · "
    assert_select "span", text: /\A#{Regexp.escape(expected)}/
  end

  test "narrows to teams that have managers" do
    get teams_positions_membership_report_path(managers: "present")

    assert_equal [@team.id], rendered_team_ids
  end

  test "narrows by type" do
    get teams_positions_membership_report_path(type: Team::TYPE_CADRE)

    assert_not_includes rendered_team_ids, @team.id, "a team is not a cadre"
    assert_includes rendered_team_ids, teams(:council_cadre).id
  end

  test "narrows by name" do
    get teams_positions_membership_report_path(title: "DIRT")

    assert_equal [@team.id], rendered_team_ids
  end

  # A LIKE wildcard typed into a search box is a literal, not a pattern -- an
  # unescaped "%" would quietly match every team and read as a broken filter.
  test "treats a percent sign in the name search as a literal" do
    get teams_positions_membership_report_path(title: "%")

    assert_empty rendered_team_ids
    assert_select "*", text: /No teams match the current filters/
  end

  test "ignores a filter value the page does not offer" do
    get teams_positions_membership_report_path(managers: "nonsense", type: { evil: 1 })

    assert_response :success
    assert_equal @active_count, rendered_team_ids.size
  end

  test "draws a removable chip for each applied filter" do
    get teams_positions_membership_report_path(managers: "missing", type: Team::TYPE_TEAM)

    assert_select "a[href=?]", teams_positions_membership_report_path(type: Team::TYPE_TEAM),
                  text: /No managers assigned/
    assert_select "a[href=?]", teams_positions_membership_report_path(managers: "missing"),
                  text: /Team/
  end

  test "sorts by member count, most first" do
    get teams_positions_membership_report_path(sort: "members")

    members = rendered_rows.map { |row| row[:members] }

    assert_equal members.sort.reverse, members
    assert_equal @team.id, rendered_team_ids.first, "the two-member team leads"
  end

  test "sorts by manager count, fewest first" do
    get teams_positions_membership_report_path(sort: "managers")

    managers = rendered_rows.map { |row| row[:managers] }

    assert_equal managers.sort, managers
    assert_equal @team.id, rendered_team_ids.last, "the only managed team sorts last"
  end

  # Ruby's sort_by is not stable, so a count sort has to carry the query's title
  # order as its tiebreaker or equal-count teams reshuffle between requests.
  test "keeps title order among teams with equal counts" do
    get teams_positions_membership_report_path(sort: "managers")

    unmanaged_ids = rendered_team_ids.first(@active_count - 1)
    assert_equal Team.where(id: unmanaged_ids).order(:title).ids, unmanaged_ids
  end

  # ---------------------------------------------------------------- roster

  test "shows the roster, callsign ordered, with managers and members" do
    get teams_positions_membership_report_team_path(@team)

    assert_response :success
    assert_select "h1", text: /#{@team.title}/
    assert_select "#manager-#{person(:inactive_ranger).id}"

    members = css_select("tr[id^=member-] th").map { |cell| cell.text.strip }
    assert_equal Person.where(id: PersonTeam.where(team_id: @team.id).select(:person_id))
                       .order(:callsign).pluck(:callsign),
                 members
    assert_unique_dom_ids
  end

  # The browser tab says which team, not just "Ranger Secret Clubhouse".
  test "titles the page after the team" do
    get teams_positions_membership_report_team_path(@team)

    assert_select "title", text: /#{@team.title} Roster/
  end

  test "links each person to their page" do
    get teams_positions_membership_report_team_path(@team)

    assert_select "#member-#{@admin.id} a[href=?]", person_path(@admin), text: @admin.callsign
  end

  # Upstream fetches each person's status and never renders it, which leaves an
  # inactive member reading exactly like an active one. Every row carries its
  # status now that the column exists; only the non-active ones get a badge.
  test "badges a member who is not active and leaves active ones plain" do
    get teams_positions_membership_report_team_path(@team)

    assert_select "#member-#{person(:retired_ranger).id} .badge", text: /retired/
    assert_select "#member-#{@admin.id} td", text: "active"
    assert_select "#member-#{@admin.id} .badge", false,
                  "the common case is plain text, not a badge"
  end

  # Managers usually hold membership too, so the two stat boxes are not a head
  # count -- the closing line says so rather than leaving the reader to add them.
  test "qualifies how the manager and member lists overlap" do
    PersonTeam.create!(team_id: @team.id, person_id: person(:inactive_ranger).id)

    get teams_positions_membership_report_team_path(@team)

    assert_select "p", text: /1 manager · 1 of them also on the member list/
  end

  test "counts the members who are not active" do
    get teams_positions_membership_report_team_path(@team)

    assert_select "div", text: "1Not Active" # only the retired member
  end

  test "calls out a team with no managers" do
    get teams_positions_membership_report_team_path(@unmanaged)

    assert_response :success
    assert_select "*", text: /No managers assigned/
  end

  test "calls out a team with no members" do
    get teams_positions_membership_report_team_path(@empty)

    assert_response :success
    assert_select "*", text: /No one holds membership on this team/
  end

  # A bookmark kept after the team was deactivated: the roster would contradict
  # the report it was reached from, so it lands back on the list with a reason.
  test "sends an inactive team back to the report" do
    get teams_positions_membership_report_team_path(@inactive)

    assert_redirected_to teams_positions_membership_report_path
    assert_match(/no longer an active team/, flash[:warning])
  end

  test "404s an unknown team" do
    get teams_positions_membership_report_team_path(0)

    assert_response :not_found
  end

  # The reader came from a filtered list; Back has to return them to it rather
  # than to every active team.
  test "carries the filters onto the roster page and back" do
    get teams_positions_membership_report_team_path(@team, managers: "present", type: Team::TYPE_TEAM)

    assert_response :success
    assert_select "a[href=?]",
                  teams_positions_membership_report_path(managers: "present", type: Team::TYPE_TEAM)
  end
end
