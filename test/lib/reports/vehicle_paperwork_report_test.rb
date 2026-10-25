# frozen_string_literal: true

require "test_helper"

class VehiclePaperworkReportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    PersonEvent.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    Team.update_all(mvr_eligible: false, pvr_eligible: false)
    Position.update_all(mvr_eligible: false, pvr_eligible: false, mvr_signup_eligible: false)

    @ranger = person(:active_ranger)
    @prospective = person(:prospective_ranger)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # ------------------------------------------------------------ inclusion ----

  test "a member of a Motor Vehicle Record eligible team is listed with the team" do
    teams(:khaki_team).update!(mvr_eligible: true)

    row = only_row

    assert_equal @ranger.id, row.person.id
    assert_equal ["Khaki Delegation"], row.mvr_teams
    assert_empty row.pvr_teams
    assert row.mvr_eligible?
    assert_not row.pvr_eligible?
  end

  test "a member of a personal vehicle eligible team is listed with the team" do
    teams(:khaki_team).update!(pvr_eligible: true)

    row = only_row

    assert_equal ["Khaki Delegation"], row.pvr_teams
    assert_empty row.mvr_teams
    assert row.pvr_eligible?
  end

  test "a team flagged for both lands in both lists" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)

    row = only_row

    assert_equal ["Khaki Delegation"], row.mvr_teams
    assert_equal ["Khaki Delegation"], row.pvr_teams
  end

  test "an inactive team never lists anyone" do
    teams(:inactive_cadre).update!(mvr_eligible: true)
    PersonTeam.create!(person: @ranger, team: teams(:inactive_cadre))

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "holding a Motor Vehicle Record eligible position lists it without a sign-up" do
    position = positions(:ood_position)
    position.update!(mvr_eligible: true)
    PersonPosition.create!(person: @ranger, position:)

    row = only_row

    assert_equal [position.title], row.mvr_positions
    assert_empty row.pvr_positions
    assert_empty row.mvr_signups
    assert row.mvr_eligible?
  end

  test "a sign-up in a Motor Vehicle Record eligible position is not a grant" do
    positions(:ood_position).update!(mvr_eligible: true)
    sign_up(@ranger, positions(:ood_position), day: 10)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "holding a position lists no one unless it is Motor Vehicle Record eligible" do
    # Upstream's grant query reads every active position and drops the others
    # only once its roster is built. active_ranger already holds three active
    # positions here, and personal vehicle eligibility still needs a sign-up.
    positions(:ood_position).update!(pvr_eligible: true)
    PersonPosition.create!(person: @ranger, position: positions(:ood_position))

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "signing up for a shift in a personal vehicle eligible position lists the position once" do
    position = positions(:ood_position)
    position.update!(pvr_eligible: true)
    sign_up(@ranger, position, day: 10)
    sign_up(@ranger, position, day: 11)

    row = only_row

    assert_equal [position.title], row.pvr_positions
    assert_empty row.mvr_positions
    assert row.pvr_eligible?
  end

  test "a sign-up-eligible shift is listed as a dated sign-up" do
    position = positions(:ood_position)
    position.update!(mvr_signup_eligible: true)
    sign_up(@ranger, position, day: 11)
    sign_up(@ranger, position, day: 10)

    row = only_row

    assert_equal [position.title, position.title], row.mvr_signups.map(&:position_title)
    assert row.mvr_eligible?
    # Earliest shift first, whatever order the rows came back in.
    assert_equal [10, 11], row.mvr_signups.map { |signup| Time.zone.parse(signup.begins.to_s).day }
  end

  test "a sign-up in another year is not listed" do
    positions(:ood_position).update!(pvr_eligible: true)
    sign_up(@ranger, positions(:ood_position), day: 10, year: YEAR - 1)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "an inactive shift is not listed" do
    positions(:ood_position).update!(pvr_eligible: true)
    sign_up(@ranger, positions(:ood_position), day: 10, active: false)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "an inactive position never lists anyone" do
    position = positions(:non_eligible_position)
    position.update!(mvr_eligible: true, pvr_eligible: true, active: false)
    PersonPosition.create!(person: @ranger, position:)
    sign_up(@ranger, position, day: 10)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "each Event Info flag on its own puts a person on the list" do
    %i[signed_motorpool_agreement org_vehicle_insurance mvr_eligible may_request_stickers].each do |flag|
      PersonEvent.delete_all
      PersonEvent.create!(person_id: @ranger.id, year: YEAR, flag => true)

      rows = VehiclePaperworkReport.for_year(YEAR).rows

      assert_equal 1, rows.size, "#{flag} should list the person"
      assert_empty rows.first.mvr_teams
      assert_empty rows.first.mvr_signups
    end
  end

  test "an Event Info record with no flags set lists no one" do
    PersonEvent.create!(person_id: @ranger.id, year: YEAR)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "flags from another year are not read" do
    PersonEvent.create!(person_id: @ranger.id, year: YEAR - 1, org_vehicle_insurance: true)
    teams(:khaki_team).update!(mvr_eligible: true)

    row = only_row

    assert_not row.record_approved
  end

  test "rows are sorted by callsign regardless of case" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(mvr_eligible: true)
    @ranger.update_columns(callsign: "zebra")
    @prospective.update_columns(callsign: "Aardvark")

    assert_equal ["Aardvark", "zebra"], VehiclePaperworkReport.for_year(YEAR).rows.map(&:callsign)
  end

  # --------------------------------------------------------------- derived ----

  test "the checkbox alone makes someone eligible" do
    PersonEvent.create!(person_id: @ranger.id, year: YEAR, mvr_eligible: true,
                        may_request_stickers: true)

    row = only_row

    assert row.mvr_eligible?
    assert row.pvr_eligible?
  end

  test "the protocol and an approved record are not by themselves eligibility" do
    PersonEvent.create!(person_id: @ranger.id, year: YEAR,
                        signed_motorpool_agreement: true, org_vehicle_insurance: true)

    row = only_row

    assert row.signed_vup
    assert row.record_approved
    assert_not row.mvr_eligible?, "signing the protocol is not eligibility"
    assert_not row.pvr_eligible?
  end

  # ------------------------------------------------------- filters & counts ----

  test "the approval filters keep each side of the yes/no split" do
    teams(:khaki_team).update!(mvr_eligible: true)          # active_ranger
    teams(:green_dot_cadre).update!(mvr_eligible: true)     # prospective_ranger
    PersonEvent.create!(person_id: @ranger.id, year: YEAR, org_vehicle_insurance: true,
                        signed_personal_vehicle_agreement: true)

    approved = VehiclePaperworkReport.for_year(YEAR, mvr_approval: VehiclePaperworkReport::APPROVED)
    unapproved = VehiclePaperworkReport.for_year(YEAR, mvr_approval: VehiclePaperworkReport::NOT_APPROVED)
    signed = VehiclePaperworkReport.for_year(YEAR, pvr_approval: VehiclePaperworkReport::APPROVED)

    assert_equal [@ranger.id], approved.rows.map { |row| row.person.id }
    assert_equal [@prospective.id], unapproved.rows.map { |row| row.person.id }
    assert_equal [@ranger.id], signed.rows.map { |row| row.person.id }
  end

  test "the eligibility filters keep each side of the yes/no split" do
    teams(:khaki_team).update!(mvr_eligible: true)                 # active_ranger
    teams(:green_dot_cadre).update!(pvr_eligible: true)            # prospective_ranger

    mvr = VehiclePaperworkReport.for_year(YEAR, mvr_eligible: VehiclePaperworkReport::ELIGIBLE)
    not_mvr = VehiclePaperworkReport.for_year(YEAR, mvr_eligible: VehiclePaperworkReport::NOT_ELIGIBLE)
    pvr = VehiclePaperworkReport.for_year(YEAR, pvr_eligible: VehiclePaperworkReport::ELIGIBLE)

    assert_equal [@ranger.id], mvr.rows.map { |row| row.person.id }
    assert_equal [@prospective.id], not_mvr.rows.map { |row| row.person.id }
    assert_equal [@prospective.id], pvr.rows.map { |row| row.person.id }
  end

  test "the team and position filters narrow to one title" do
    teams(:khaki_team).update!(mvr_eligible: true)                 # active_ranger
    teams(:green_dot_cadre).update!(mvr_eligible: true)            # prospective_ranger
    position = positions(:ood_position)
    position.update!(mvr_eligible: true)
    PersonPosition.create!(person: @ranger, position:)

    by_team = VehiclePaperworkReport.for_year(YEAR, mvr_team: "Khaki Delegation")
    by_position = VehiclePaperworkReport.for_year(YEAR, mvr_position: position.title)

    assert_equal [@ranger.id], by_team.rows.map { |row| row.person.id }
    assert_equal [@ranger.id], by_position.rows.map { |row| row.person.id }
  end

  test "filters combine, each narrowing what the last one left" do
    teams(:khaki_team).update!(mvr_eligible: true)                 # active_ranger
    teams(:green_dot_cadre).update!(mvr_eligible: true)            # prospective_ranger
    PersonEvent.create!(person_id: @ranger.id, year: YEAR, org_vehicle_insurance: true)

    result = VehiclePaperworkReport.for_year(YEAR,
                                             mvr_team: "Khaki Delegation",
                                             mvr_approval: VehiclePaperworkReport::NOT_APPROVED)

    assert_empty result.rows, "the Khaki member is the one WITH an approved record"
    assert_equal 2, result.total_count
  end

  test "the all sentinel narrows nothing" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(mvr_eligible: true)

    result = VehiclePaperworkReport.for_year(YEAR,
                                             mvr_approval: VehiclePaperworkReport::ALL,
                                             mvr_team: VehiclePaperworkReport::ALL)

    assert_equal 2, result.rows.size
  end

  test "the picker options come from the whole roster, not the filtered rows" do
    teams(:khaki_team).update!(mvr_eligible: true)                 # active_ranger
    teams(:green_dot_cadre).update!(mvr_eligible: true, pvr_eligible: true)

    result = VehiclePaperworkReport.for_year(YEAR, mvr_team: "Khaki Delegation")

    assert_equal 1, result.rows.size
    # Otherwise picking a team would remove every other team from the picker
    # and the filter could not be widened again without clearing it.
    assert_equal ["Green Dot Cadre", "Khaki Delegation"], result.mvr_team_options
    assert_equal ["Green Dot Cadre"], result.pvr_team_options
  end

  test "callsign search matches on a fragment, ignoring case" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(mvr_eligible: true)

    rows = VehiclePaperworkReport.for_year(YEAR, callsign: @ranger.callsign[1, 3].upcase).rows

    assert_equal [@ranger.id], rows.map { |row| row.person.id }
  end

  test "the counts describe the whole year, not the filtered rows" do
    teams(:khaki_team).update!(mvr_eligible: true)
    teams(:green_dot_cadre).update!(pvr_eligible: true)
    PersonEvent.create!(person_id: @ranger.id, year: YEAR,
                        signed_motorpool_agreement: true, org_vehicle_insurance: true,
                        signed_personal_vehicle_agreement: true)

    result = VehiclePaperworkReport.for_year(YEAR, pvr_eligible: VehiclePaperworkReport::ELIGIBLE)

    assert_equal 1, result.rows.size
    assert_equal 2, result.total_count
    assert_equal 1, result.vup_count
    assert_equal 1, result.record_approved_count
    assert_equal 1, result.pvr_approved_count
    assert_equal 1, result.mvr_eligible_count
    assert_equal 1, result.pvr_eligible_count
  end

  test "signing the personal vehicle agreement is not by itself a reason to be listed" do
    PersonEvent.create!(person_id: @ranger.id, year: YEAR,
                        signed_personal_vehicle_agreement: true)

    assert_empty VehiclePaperworkReport.for_year(YEAR).rows
  end

  test "teams and grants are read for the current year only" do
    teams(:khaki_team).update!(mvr_eligible: true, pvr_eligible: true)
    position = positions(:ood_position)
    position.update!(mvr_eligible: true)
    PersonPosition.create!(person: @ranger, position:)
    PersonEvent.create!(person_id: @ranger.id, year: YEAR - 1, org_vehicle_insurance: true)

    current = VehiclePaperworkReport.for_year(YEAR)
    past = VehiclePaperworkReport.for_year(YEAR - 1)

    assert_predicate current, :memberships_checked?
    assert_equal ["Khaki Delegation"], current.rows.first.mvr_teams
    assert_equal [position.title], current.rows.first.mvr_positions

    # person_team and person_position have no year column, so a past year's
    # lists would just be today's. It reports "never looked" instead of guessing.
    assert_not past.memberships_checked?
    assert_equal 1, past.rows.size
    assert_empty past.rows.first.mvr_teams
    assert_empty past.rows.first.pvr_teams
    assert_empty past.rows.first.mvr_positions
    assert_empty past.mvr_position_options
    assert_not past.rows.first.mvr_eligible?
  end

  test "a past year lists no one whose only claim is a present-day team or grant" do
    teams(:khaki_team).update!(mvr_eligible: true)                 # active_ranger
    positions(:ood_position).update!(mvr_eligible: true)
    PersonPosition.create!(person: @prospective, position: positions(:ood_position))

    assert_empty VehiclePaperworkReport.for_year(YEAR - 1).rows
    assert_equal 2, VehiclePaperworkReport.for_year(YEAR).rows.size
  end

  test "an empty year reports itself as empty" do
    result = VehiclePaperworkReport.for_year(YEAR)

    assert_predicate result, :empty_year?
    assert_not result.any?
  end

  private

  def only_row
    rows = VehiclePaperworkReport.for_year(YEAR).rows
    assert_equal 1, rows.size
    rows.first
  end

  def sign_up(person, position, day:, year: YEAR, active: true)
    slot = Slot.create!(position:,
                        begins: Time.zone.local(year, 8, day, 18, 45, 0),
                        ends: Time.zone.local(year, 8, day, 22, 45, 0),
                        max: 10,
                        active:)
    PersonSlot.create!(person:, slot:)
  end
end
