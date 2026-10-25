# frozen_string_literal: true

require "test_helper"

# Status Change Recommendations: who reaches the page, what the index counts,
# how a group narrows and exports, and the conversions themselves -- the status
# flip, the audit trail, the re-derived eligibility, and the 422 render that
# holds the just-changed people on the list.
class People::StatusChangeRecommendationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include PersonTestFactory
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  INACTIVE_CUTOFF = 2024 # the first of the last three events
  RETIRED_CUTOFF = 2022  # the first of the last five
  DENY_MESSAGE = "Admin role required to review proposed status changes."

  setup do
    travel_to Time.zone.local(YEAR, 10, 1, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # The report reads every Person, so the fixtures are parked in a status no
    # group proposes and their shifts cleared.
    Timesheet.delete_all
    Person.update_all(status: Person::AUDITOR, vintage: false, years_as_ranger: nil)

    @dirt = Position.create!(id: Position::DIRT, title: "Dirt",
                             type: Position::TYPE_FRONTLINE, active: true)

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)
    sign_in_as(@admin)

    # One person in each of three groups, so a page can be shown to be listing
    # its own group and no other.
    @away = create_person("Bandsaw")
    ranger(@away, RETIRED_CUTOFF)

    @gone = create_person("Aloe")
    ranger(@gone, RETIRED_CUTOFF - 1)

    @applicant = create_person("SmithJane26", status: Person::PROSPECTIVE)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "an admin reaches the index" do
    get people_status_change_recommendations_path

    assert_response :success
    assert_select "h1", /Status Change Recommendations/
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away from the index" do
    sign_in_as(@outsider)

    get people_status_change_recommendations_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error] || flash[:alert]
  end

  test "someone without the admin role is turned away from a group" do
    sign_in_as(@outsider)

    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)

    assert_redirected_to me_root_path
  end

  test "someone without the admin role cannot convert" do
    sign_in_as(@outsider)

    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [@away.id] }

    assert_redirected_to me_root_path
    assert_equal Person::ACTIVE, @away.reload.status
  end

  # ---------------------------------------------------------------- index

  test "the index counts every group and links to each one" do
    get people_status_change_recommendations_path

    assert_response :success
    assert_select "a[href=?]", people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)
    assert_select "body", /1 person/
    assert_select "body", /#{INACTIVE_CUTOFF}/
    assert_select "body", /#{RETIRED_CUTOFF}/
  end

  test "the next event period moves both cutoff years on" do
    get people_status_change_recommendations_path(period: RecommendStatusChangeReport::PERIOD_NEXT)

    assert_response :success
    assert_select "body", /#{INACTIVE_CUTOFF + 1}/
    assert_select "body", /#{RETIRED_CUTOFF + 1}/
    # The period rides on every link, or a drill would land on a different list.
    assert_select "a[href=?]",
                  people_status_change_recommendations_group_path(RecommendStatusChangeReport::PAST_PROSPECTIVE,
                                                                  period: RecommendStatusChangeReport::PERIOD_NEXT)
  end

  # The period buttons name no year and the card that does is closed, so the
  # count line says which event the counts are judged against.
  test "the count line names the event being judged" do
    get people_status_change_recommendations_path

    assert_select "body", /proposed changes for #{YEAR}/

    get people_status_change_recommendations_path(period: RecommendStatusChangeReport::PERIOD_NEXT)

    assert_select "body", /proposed changes for #{YEAR + 1}/
  end

  test "a group with no one in it is not a link" do
    get people_status_change_recommendations_path

    assert_response :success
    assert_select "a[href=?]", people_status_change_recommendations_group_path(RecommendStatusChangeReport::VINTAGE),
                  count: 0
    assert_select "[aria-disabled=true]", /Mark Callsign as Vintage/
  end

  test "an unknown group is sent back to the index" do
    get people_status_change_recommendations_group_path("shiny-pennies")

    assert_redirected_to people_status_change_recommendations_path
    assert_equal "That is not one of the proposed status changes.", flash[:alert]
  end

  # ---------------------------------------------------------------- a group

  test "a group lists its own people and no one else's" do
    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)

    assert_response :success
    assert_select "h1", /Convert to Inactive/
    assert_select "a", text: @away.callsign
    assert_select "a", text: @gone.callsign, count: 0
    assert_bulk_select_count_matches_ticked
    assert_unique_dom_ids
  end

  test "the applicant group drops the columns it has no history for" do
    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::PAST_PROSPECTIVE)

    assert_response :success
    assert_select "th", text: "Alpha Year", count: 0
    assert_select "th", text: "Vintage", count: 0
    assert_select "th", text: "Proposed Status"
  end

  test "a group with no one in it says so" do
    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::VINTAGE)

    assert_response :success
    assert_select "body", /No one is proposed for this change/
  end

  test "a filter narrows the list" do
    other = create_person("Halyard", status: Person::INACTIVE)
    ranger(other, RETIRED_CUTOFF - 1)

    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::RETIRED,
                                                        status: Person::INACTIVE)

    assert_response :success
    assert_select "a", text: other.callsign
    assert_select "a", text: @gone.callsign, count: 0
  end

  test "a filter value the group cannot offer narrows nothing" do
    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::RETIRED,
                                                        status: "banana")

    assert_response :success
    assert_select "a", text: @gone.callsign
  end

  # ---------------------------------------------------------------- export

  test "the export carries the rows on screen" do
    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/#{YEAR}-inactive-convert\.csv/, response.headers["Content-Disposition"])
    assert_match "Callsign,Current Status,Proposed Status", response.body
    assert_match @away.callsign, response.body
    assert_no_match(/#{@gone.callsign}/, response.body)
  end

  test "the export honours the filters" do
    other = create_person("Halyard", status: Person::INACTIVE)
    ranger(other, RETIRED_CUTOFF - 1)

    get people_status_change_recommendations_group_path(RecommendStatusChangeReport::RETIRED,
                                                        status: Person::INACTIVE, format: :csv)

    assert_match other.callsign, response.body
    assert_no_match(/#{@gone.callsign}/, response.body)
  end

  # ---------------------------------------------------------------- convert

  test "converting changes the status and records the history" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [@away.id] }

    assert_response :unprocessable_entity
    assert_equal Person::INACTIVE, @away.reload.status

    history = PersonStatus.where(person_id: @away.id).last

    assert_equal Person::ACTIVE, history.old_status
    assert_equal Person::INACTIVE, history.new_status
    assert_match RecommendStatusChangeReport::REASON, history.reason
  end

  test "the just-changed people are held on the list and named" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [@away.id] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /Changed 1 person/
    assert_select "a", text: @away.callsign
    # Held on the list, but no longer counted as waiting.
    assert_select ".table-row-base", 1
    assert_select "div.font-bold", text: "0"
    assert_unique_dom_ids
  end

  test "a filter cannot hide someone the result banner has just named" do
    # The change is what stops them matching: a moment ago they were active.
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE,
                                                           status: Person::ACTIVE),
         params: { person_ids: [@away.id] }

    assert_response :unprocessable_entity
    assert_select "a", text: @away.callsign
  end

  test "a checked person outside the group is never written" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [@gone.id] }

    assert_redirected_to people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)
    assert_equal Person::ACTIVE, @gone.reload.status
  end

  test "a person outside the group is dropped while the rest are converted" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [@away.id, @gone.id] }

    assert_response :unprocessable_entity
    assert_equal Person::INACTIVE, @away.reload.status
    assert_equal Person::ACTIVE, @gone.reload.status
  end

  test "converting nothing asks for a person instead" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE)

    assert_redirected_to people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)
    assert_equal "Check at least one person first.", flash[:alert]
  end

  # to_i read "#{id}x" as the id and converted that person.
  test "person ids that are not ids check no one" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: ["", "abc", "#{@away.id}x"] }

    assert_redirected_to people_status_change_recommendations_group_path(RecommendStatusChangeReport::INACTIVE)
    assert_equal "Check at least one person first.", flash[:alert]
    assert_equal Person::ACTIVE, @away.reload.status
  end

  test "the vintage group sets the flag and leaves the status alone" do
    veteran = create_person("Lodestar", years: (2010..2019).to_a)

    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::VINTAGE),
         params: { person_ids: [veteran.id] }

    assert_response :unprocessable_entity
    veteran.reload

    assert_predicate veteran, :vintage?
    assert_equal Person::ACTIVE, veteran.status
  end

  test "converting an applicant releases the callsign" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::PAST_PROSPECTIVE),
         params: { person_ids: [@applicant.id] }

    assert_response :unprocessable_entity
    @applicant.reload

    assert_equal Person::PAST_PROSPECTIVE, @applicant.status
    assert_not_equal "SmithJane26", @applicant.callsign
    assert_not @applicant.callsign_approved?
  end

  test "the period rides through a conversion" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::PAST_PROSPECTIVE,
                                                           period: RecommendStatusChangeReport::PERIOD_NEXT),
         params: { person_ids: [@applicant.id] }

    assert_response :unprocessable_entity
    assert_select "a[href=?]",
                  people_status_change_recommendations_path(period: RecommendStatusChangeReport::PERIOD_NEXT)
  end

  test "a filter in force is not dropped when the change stops its rows matching" do
    # Retired group: two active, one inactive. Filtered to the inactive one,
    # who is then converted -- so no inactive row is left to rebuild the choice
    # list from. The filter must survive, or the next "select all" would cover
    # the two people the admin deliberately filtered out.
    stayer = create_person("Kettle", status: Person::INACTIVE)
    ranger(stayer, RETIRED_CUTOFF - 1)
    ranger(create_person("Deepwater"), RETIRED_CUTOFF - 1)

    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::RETIRED,
                                                           status: Person::INACTIVE),
         params: { person_ids: [stayer.id] }

    assert_response :unprocessable_entity
    assert_select ".table-row-base", 1
    assert_select "a", text: "Deepwater", count: 0
  end

  test "a write cannot be addressed to a format that has no results page" do
    # The POST route takes no format, so this never reaches the action -- which
    # is the point: it used to make every change and then fail to render the
    # one record of what it had done.
    post "/people/status-change-recommendations/inactive.csv", params: { person_ids: [@away.id] }

    assert_response :not_found
    assert_equal Person::ACTIVE, @away.reload.status
  end

  test "a callsign the batch cannot carry is named rather than silently skipped" do
    odd = rename(create_person("Placeholder"), "Smith, Jr")
    ranger(odd, RETIRED_CUTOFF)

    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::INACTIVE),
         params: { person_ids: [odd.id, @away.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ACTIVE, odd.reload.status
    assert_equal Person::INACTIVE, @away.reload.status
    assert_select "body", /Smith, Jr/
    assert_select "body", /comma or a line break/
  end

  test "the banner names both the old callsign and the one that replaced it" do
    post people_status_change_recommendations_convert_path(RecommendStatusChangeReport::PAST_PROSPECTIVE),
         params: { person_ids: [@applicant.id] }

    assert_response :unprocessable_entity
    assert_select "body", /SmithJane26 \(now #{@applicant.reload.callsign}\)/
  end

  private

  # create_person builds the email address out of the callsign, so a callsign
  # that is not the shape an address takes is set after the fact.
  def rename(person, callsign)
    person.update_columns(callsign:, callsign_normalized: WordUtils.normalize_word(callsign))
    person
  end

  def ranger(person, year, position: @dirt)
    on_duty = Time.zone.local(year, 8, 28, 18, 0, 0)
    Timesheet.create!(person:, position:, on_duty:, off_duty: on_duty + 6.hours,
                      additional_notes: "test shift")
  end
end
