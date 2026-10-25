# frozen_string_literal: true

require "test_helper"

# Ticketing > Bulk Grant Provisions: the two provision groups of upstream's
# admin/bulk-upload.
#
# Every test is pinned to April 2026 unless it says otherwise. The earned
# default years turn over in September, so a suite reading the real clock would
# start failing on its own one autumn morning.
class Ticketing::BulkProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @ticketing = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)
    grant_role(@ticketing, Role::EDIT_ACCESS_DOCS)

    # The fixtures hand provisions to two people for other suites. Every verdict
    # on this page is about what a person already holds, so the table starts
    # empty and each test builds exactly what it is about.
    Provision.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def upload_params(records, action: "event_eat_pass", reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  def existing_meal_pass(person, source_year: YEAR - 1, **periods)
    Provision.create!(person_id: person.id, type: Provision::MEALS, status: Provision::AVAILABLE,
                      is_allocated: false, source_year:, expires_on: source_year + 4,
                      **{ pre_event_meals: false, event_week_meals: true, post_event_meals: false }.merge(periods))
  end

  def granted_to(person) = Provision.where(person_id: person.id).order(:id).last

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get ticketing_bulk_provisions_path

    assert_response :success
    assert_select "h1", /Bulk Grant Provisions/
    assert_unique_dom_ids
  end

  test "the edit access documents role reaches the form" do
    sign_in_as(@ticketing)

    get ticketing_bulk_provisions_path

    assert_response :success
    assert_select "h1", /Bulk Grant Provisions/
  end

  test "someone with neither role is turned away" do
    sign_in_as(@outsider)

    get ticketing_bulk_provisions_path

    assert_redirected_to me_root_path
    assert_match(/edit access documents role required/i, flash[:error])
  end

  # ----------------------------------------------------------- the select

  test "the select offers all thirteen provisions under their two groups" do
    get ticketing_bulk_provisions_path

    assert_select "select[name=bulk_action] optgroup[label=?]", "Earned Provisions"
    assert_select "select[name=bulk_action] optgroup[label=?]", "Allocated Provisions"

    offered = css_select("select[name=bulk_action] optgroup option").map { |option| option["value"] }
    assert_equal %w[all_eat_pass event_eat_pass wet_spot event_radio
                    alloc_all_eat_pass alloc_event_eat_pass alloc_pre_event_eat_pass
                    alloc_pre_event_event_eat_pass alloc_pre_post_eat_pass
                    alloc_event_post_event_eat_pass alloc_post_event_eat_pass
                    alloc_wet_spot alloc_event_radio],
                 offered
  end

  test "the form lists a line format for every provision and spells out the default years" do
    get ticketing_bulk_provisions_path

    assert_select "td", text: "callsign[,source year,expiry year]"
    assert_select "td", text: "callsign,count[,source year,expiry year]"
    assert_select "td", text: "callsign,radio count"
    # April, so the earned window still belongs to last season.
    assert_select "body", /earned in 2025, expiring 2029/
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "Provision.count" do
      post ticketing_preview_bulk_provisions_path, params: upload_params(@target.callsign)
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Earned Event Eat Pass/
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview marks an unknown callsign as a problem" do
    post ticketing_preview_bulk_provisions_path, params: upload_params("NotARealCallsign")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    # No confirm button: nothing on the list can be granted.
    assert_select "input[type=submit]", 1
  end

  test "preview refuses a year that is not a number" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},soon")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Source Year is not a number/
  end

  test "preview refuses a source year in the future" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},#{YEAR + 1}")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Source Year is in the future \[#{YEAR + 1}\]/
  end

  test "preview refuses a year long out of range" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},#{YEAR - 9}")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Source Year is more than 5 years in the past/
  end

  test "preview refuses a source year after the expiry year" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},#{YEAR},#{YEAR - 2}")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Source year \[#{YEAR}\] is after expiry year \[#{YEAR - 2}\]/
  end

  test "preview refuses a radio count that is not a number" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},lots", action: "event_radio")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Item count is not a number/
  end

  test "preview refuses an allocated line carrying anything but a callsign" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},#{YEAR}", action: "alloc_all_eat_pass")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /only take a callsign and no other parameters/
  end

  test "preview warns that a provision already held will be replaced" do
    existing_meal_pass(@target, source_year: YEAR - 2)

    post ticketing_preview_bulk_provisions_path, params: upload_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Event Week Eat Pass earned in #{YEAR - 2}/
    assert_select "tbody tr td", /cancelled and replaced/
    # A replacement still writes, so the confirm button is offered.
    assert_select "input[type=submit]", 2
  end

  test "a pass with different meal periods is not the pass being granted" do
    # An all-eats pass and an event-week pass are both MEALS rows; only the
    # period flags tell them apart, and the duplicate check has to compare them.
    existing_meal_pass(@target, pre_event_meals: true, event_week_meals: true, post_event_meals: true)

    post ticketing_preview_bulk_provisions_path, params: upload_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will be applied/
  end

  test "preview re-posts everything the apply needs" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2,#{YEAR - 1}", action: "event_radio",
                               reason: "earned at the burn")

    assert_select "input[name=bulk_action][value=event_radio]"
    assert_select "input[name=records][value=?]", "#{@target.callsign},2,#{YEAR - 1}"
    assert_select "input[name=reason][value=?]", "earned at the burn"
  end

  test "preview refuses an action this page does not offer" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "sandman_affidavit")

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply grants an earned meal pass with the season's years and periods" do
    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "all_eat_pass", reason: "earned at the burn")

    assert_response :unprocessable_entity
    provision = granted_to(@target)
    assert_equal Provision::MEALS, provision.type
    assert_equal Provision::AVAILABLE, provision.status
    assert provision.pre_event_meals
    assert provision.event_week_meals
    assert provision.post_event_meals
    assert_not provision.is_allocated
    # April 2026: earned last season, expiring four years on.
    assert_equal YEAR - 1, provision.source_year
    assert_equal Date.new(YEAR + 3, 9, 15), provision.expires_on
    assert_match(/created via bulk uploader/, provision.comments)

    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: @target.callsign
  end

  test "apply grants only the periods the chosen pass names" do
    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "alloc_pre_post_eat_pass")

    provision = granted_to(@target)
    assert provision.pre_event_meals
    assert_not provision.event_week_meals
    assert provision.post_event_meals
  end

  test "an allocated grant is for this year whatever the season" do
    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "alloc_all_eat_pass")

    provision = granted_to(@target)
    assert provision.is_allocated
    assert_equal YEAR, provision.source_year
    # The model expires an allocated provision with the year it was granted in.
    assert_equal Date.new(YEAR, 9, 15), provision.expires_on
  end

  test "apply honours the years typed on an earned line" do
    post ticketing_bulk_provisions_path,
         params: upload_params("#{@target.callsign},#{YEAR - 2},#{YEAR + 2}", action: "wet_spot")

    provision = granted_to(@target)
    assert_equal Provision::WET_SPOT, provision.type
    assert_equal YEAR - 2, provision.source_year
    assert_equal Date.new(YEAR + 2, 9, 15), provision.expires_on
  end

  test "apply stores the radio count from the line" do
    post ticketing_bulk_provisions_path,
         params: upload_params("#{@target.callsign},3", action: "event_radio")

    provision = granted_to(@target)
    assert_equal Provision::EVENT_RADIO, provision.type
    assert_equal 3, provision.item_count
    assert_equal YEAR - 1, provision.source_year
  end

  test "a radio line with no count grants one radio" do
    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "event_radio")

    assert_equal 1, granted_to(@target).item_count
  end

  test "an allocated radio line still takes its count" do
    # The count column is read before the allocated "callsign only" check, which
    # is the only way an allocated radio grant can say how many radios it is for.
    post ticketing_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2", action: "alloc_event_radio")

    provision = granted_to(@target)
    assert provision.is_allocated
    assert_equal 2, provision.item_count
    assert_equal YEAR, provision.source_year
  end

  test "apply cancels the provision it replaces and names its replacement" do
    existing = existing_meal_pass(@target)

    assert_difference "Provision.count", 1 do
      post ticketing_bulk_provisions_path, params: upload_params(@target.callsign)
    end

    replacement = granted_to(@target)
    assert_equal Provision::AVAILABLE, replacement.status

    existing.reload
    assert_equal Provision::CANCELLED, existing.status
    assert_match(/Replaced by item ##{replacement.id} via bulk uploader/, existing.comments)
  end

  test "apply leaves a locked account alone" do
    locked = person(:deceased_ranger)

    assert_no_difference "Provision.count" do
      post ticketing_bulk_provisions_path, params: upload_params(locked.callsign)
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply writes nothing for a line it refused" do
    assert_no_difference "Provision.count" do
      post ticketing_bulk_provisions_path,
           params: upload_params("#{@target.callsign},soon")
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply records the reason and the chosen provision in the commit log" do
    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "alloc_wet_spot", reason: "handed out at HQ")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "handed out at HQ", log.data["reason"]
    assert_equal "alloc_wet_spot", log.data["action"]
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  test "after the season turns over the earned years move on" do
    travel_to Time.zone.local(YEAR, 9, 15, 12, 0, 0)

    post ticketing_bulk_provisions_path,
         params: upload_params(@target.callsign, action: "all_eat_pass")

    provision = granted_to(@target)
    assert_equal YEAR, provision.source_year
    assert_equal Date.new(YEAR + 4, 9, 15), provision.expires_on
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen provision" do
    post ticketing_edit_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2", action: "alloc_event_radio", reason: "handed out at HQ")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: "#{@target.callsign},2"
    assert_select "select[name=bulk_action] option[selected][value=alloc_event_radio]"
    assert_select "input[name=reason][value=?]", "handed out at HQ"
  end

  # ------------------------------------------------- what the preview states

  # The page opts out of the shared year callout on the grounds that "the years
  # are named on every row of the preview instead". They have to actually be
  # there for that to be true.
  test "preview names the years an earned line lands on" do
    post ticketing_preview_bulk_provisions_path, params: upload_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Source year #{YEAR - 1}, expires #{YEAR + 3}/
  end

  # The radio count is the column taken first, so a reader who types the source
  # year in the shape the other twelve actions use lands it in item_count. The
  # write matches upstream; the preview is what makes it visible.
  test "preview names the radio count, so a year typed into it is visible" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2024", action: "event_radio")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /2024 radios/
  end

  test "preview names the count and years of an ordinary radio line" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2,2024,2028", action: "event_radio")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /2 radios, source year 2024, expires 2028/
  end

  # -------------------------------------------------------- refusing extras

  test "an earned line carrying a column past the expiry year is refused" do
    post ticketing_preview_bulk_provisions_path,
         params: upload_params("#{@target.callsign},2024,2028,2030")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Unexpected additional data/
    assert_no_difference "Provision.count" do
      post ticketing_bulk_provisions_path, params: upload_params("#{@target.callsign},2024,2028,2030")
    end
  end

  # ------------------------------------------------- replacing more than one

  # Two matching current provisions is a state that exists in the data --
  # preload orders by id for exactly that reason. Cancelling only the first left
  # the person holding MORE provisions after the run than before it.
  test "apply cancels every current provision, not just the first" do
    first = existing_meal_pass(@target)
    second = existing_meal_pass(@target)

    post ticketing_bulk_provisions_path, params: upload_params(@target.callsign)

    assert_equal Provision::CANCELLED, first.reload.status
    assert_equal Provision::CANCELLED, second.reload.status
    assert_equal 1, Provision.where(person_id: @target.id, status: Provision::AVAILABLE).count
  end

  test "preview says how many existing provisions will be replaced" do
    existing_meal_pass(@target)
    existing_meal_pass(@target)

    post ticketing_preview_bulk_provisions_path, params: upload_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /All 2 will be cancelled and replaced/
  end
end
