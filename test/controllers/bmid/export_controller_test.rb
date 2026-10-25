# frozen_string_literal: true

require "test_helper"

# BMID > Export Badges: the Eventree review page, its buckets and pre-checked
# selection, and the export POST that materializes badges, marks them
# submitted, consumes provisions, and records the batch with its CSV.
#
# Same harness as the manage roster tests: the categories sweep whole tables
# and the shared fixtures belong to other suites, so every test starts from
# empty tables and builds exactly the badges it needs.
class Bmid::ExportControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include BulkSelectTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include PersonPhotoTestHelper # create_photo
  include DomIdTestHelper # assert_unique_dom_ids
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    Bmid.delete_all
    BmidExport.delete_all
    AccessDocument.delete_all
    Provision.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    PersonPhoto.delete_all
    Setting.where(name: [Setting::TAS_DEFAULT_SAP_DATE, Setting::TAS_SAP_DATE_RANGE]).delete_all
    Setting.create!(name: Setting::TAS_DEFAULT_SAP_DATE, value: "#{YEAR}-08-15")
    Setting.create!(name: Setting::TAS_SAP_DATE_RANGE, value: "10-25")

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ---------------------------------------------------------

  test "the review renders for an admin" do
    badge(@admin, title1: "Shift Lead")

    get bmid_export_path

    assert_response :success
    assert_includes selection_callsigns, @admin.callsign
    assert_match "Showing 1 of 1 selectable badge", response.body
  end

  test "the review renders with only the edit BMIDs role" do
    sign_in_as(@badger)
    badge(@badger, title1: "Shift Lead")

    get bmid_export_path

    assert_response :success
    assert_includes selection_callsigns, @badger.callsign
  end

  test "the review is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    get bmid_export_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  # --- the review -----------------------------------------------------------

  test "blocking statuses are set aside from the selection table" do
    badge(@admin, title1: "Shift Lead")
    parked = badge(person(:retired_ranger), status: Bmid::DO_NOT_PRINT, title1: "A")
    trouble = badge(person(:alpha_ranger), status: Bmid::ISSUES, title1: "B")
    sent = badge(person(:prospective_ranger), status: Bmid::SUBMITTED, title1: "C")

    get bmid_export_path

    assert_response :success
    assert_equal [@admin.callsign], selection_callsigns
    [parked, trouble, sent].each do |bucketed|
      assert_select "details a[href=?]", person_path(bucketed.person), text: bucketed.person.callsign
    end
  end

  test "an unusual person status is set aside from the selection table" do
    badge(@admin, title1: "Shift Lead")
    odd = badge(person(:bonked_ranger), title1: "D")

    get bmid_export_path

    assert_response :success
    assert_equal [@admin.callsign], selection_callsigns
    assert_select "details a[href=?]", person_path(odd.person), text: odd.person.callsign
  end

  test "printable rows start checked and problem rows are passed over by select-all" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    badge(@admin, title1: "Shift Lead")

    shy = person(:retired_ranger)
    ticket_for(shy)
    badge(shy, title1: "No Photo")

    get bmid_export_path

    assert_response :success
    assert_select "input#bmid-export-check-#{@admin.id}[checked]"
    assert_select "input#bmid-export-check-#{@admin.id}[data-skip-select-all]", false
    assert_select "input#bmid-export-check-#{shy.id}[checked]", false
    assert_select "input#bmid-export-check-#{shy.id}[data-skip-select-all]"
    assert_bulk_select_count_matches_ticked
  end

  test "the export form carries the year and filter without colliding with the filter bar" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    badge(@admin, title1: "Shift Lead")

    get bmid_export_path

    assert_response :success
    assert_select "select#filter", 1
    assert_select "input[type=hidden][name=filter]"
    assert_select "input[type=hidden][name=year]", 2
    assert_unique_dom_ids
  end

  test "the search narrows the table but not the buckets" do
    badge(@admin, title1: "Shift Lead")
    badge(person(:retired_ranger), title1: "Quartermaster")
    parked = badge(person(:alpha_ranger), status: Bmid::DO_NOT_PRINT, title1: "A")

    get bmid_export_path(q: "Quartermaster")

    assert_response :success
    assert_equal [person(:retired_ranger).callsign], selection_callsigns
    assert_select "details a[href=?]", person_path(parked.person), text: parked.person.callsign
  end

  # --- the export -----------------------------------------------------------

  test "exporting materializes the badge, consumes provisions, and records the batch" do
    approved_photo_for(@admin)
    ticket_for(@admin, access_any_time: true)
    meal = meal_for(@admin, pre_event_meals: true)
    shower = provision_for(@admin)

    assert_nil Bmid.find_for_person_year(@admin.id, YEAR)

    post bmid_export_create_path,
         params: { year: YEAR, filter: "special", ids: [@admin.id], batch_info: "Batch #1" }

    assert_response :unprocessable_entity
    # The results page scrolls itself to the top: a form-submission render
    # otherwise keeps the scroll position of the submit button, mid-list.
    assert_select "[data-controller=scroll-to-top]"

    saved = Bmid.find_for_person_year(@admin.id, YEAR)
    assert saved, "exporting must INSERT the synthesized badge"
    assert_equal Bmid::SUBMITTED, saved.status
    assert_equal "Batch #1", saved.batch
    assert_match "Exported [meals pre earned] [showers earned]", saved.notes

    assert_equal Provision::SUBMITTED, meal.reload.status
    assert_equal Provision::SUBMITTED, shower.reload.status
    assert_match "Consumed by BMID export", meal.comments

    export = BmidExport.last
    assert export
    assert_equal @admin.id, export.person_id
    assert_equal [@admin.id], export.person_ids
    assert_equal "Batch #1", export.batch_info
    assert export.csv_file.attached?

    csv = export.csv_file.download.split("\n")
    assert_equal "First name,Last name,Email,Playa Name,Position,Department,Supervisor," \
                 "Arrival Date,Shower Access For Entire Event,Pre-Event Meals," \
                 "During Event Meals,Post Event Meals,Title 2,Title 3", csv.first
    row = csv.second
    assert_match @admin.callsign, row
    assert_match "Rangers 660", row
    assert_match "07/15/#{YEAR}", row
    assert_match ",Yes,Yes,No,No,", row # showers, pre, event, post
  end

  test "a badge that moved on since the page loaded is skipped with a reason" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    already = badge(person(:retired_ranger), status: Bmid::SUBMITTED, title1: "A")

    post bmid_export_create_path,
         params: { year: YEAR, filter: "special", ids: [@admin.id, already.person_id] }

    assert_response :unprocessable_entity
    assert_match "badge status is Submitted", response.body
    assert_match already.person.callsign, response.body

    assert_equal Bmid::SUBMITTED, Bmid.find_for_person_year(@admin.id, YEAR).status
    assert_nil already.reload.batch, "a skipped badge must not be stamped"
    assert_equal [@admin.id], BmidExport.last.person_ids
  end

  test "nothing printable redirects with the upstream message" do
    already = badge(@admin, status: Bmid::SUBMITTED, title1: "A")

    post bmid_export_create_path,
         params: { year: YEAR, filter: "special", ids: [already.person_id] }

    assert_redirected_to bmid_export_path(year: YEAR, filter: "special")
    assert_equal Bmid::ExportController::NOTHING_PRINTABLE, flash[:alert]
    assert_nil BmidExport.last
  end

  # Integer() kept "0" and read " #{id}", space and all, as the id, which
  # exported that badge.
  test "ids that are not ids are an empty selection" do
    badge(@admin, title1: "Shift Lead")

    post bmid_export_create_path, params: { year: YEAR, filter: "special", ids: ["", "0", " #{@admin.id}"] }

    assert_redirected_to bmid_export_path(year: YEAR, filter: "special")
    assert_equal "Select at least one badge to export.", flash[:alert]
    assert_nil BmidExport.last
  end

  test "an empty selection redirects with an alert" do
    post bmid_export_create_path, params: { year: YEAR, filter: "special" }

    assert_redirected_to bmid_export_path(year: YEAR, filter: "special")
    assert_equal "Select at least one badge to export.", flash[:alert]
  end

  test "previous exports list the year's batches with a download link" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    badge(@admin, title1: "Shift Lead")
    export = EventreeBmidExport.export!([@admin.id], year: YEAR,
                                        batch_info: "Batch #1", exporter: @admin)[:export]

    get bmid_export_path

    assert_response :success
    assert_match export.filename, response.body
    assert_match "Batch #1", response.body
    assert_select "#previous-exports a", text: /#{Regexp.escape(export.filename)}/
    assert_select "#previous-exports a[href=?]", bmid_export_unsubmit_path(export)
  end

  test "a previous year's batch lists without an un-submit button" do
    badge(@admin, title1: "Shift Lead")
    export = EventreeBmidExport.export!([@admin.id], year: YEAR,
                                        batch_info: "", exporter: @admin)[:export]
    export.update_columns(created_at: Time.zone.local(YEAR - 1, 8, 1))

    get bmid_export_path(year: YEAR - 1)

    assert_response :success
    assert_match export.filename, response.body
    assert_select "a[href=?]", bmid_export_unsubmit_path(export), false
  end

  # --- the un-submit ---------------------------------------------------------

  test "un-submitting a batch returns its badges to in prep and removes the record" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    meal = meal_for(@admin, pre_event_meals: true)
    export = EventreeBmidExport.export!([@admin.id], year: YEAR,
                                        batch_info: "Batch #1", exporter: @admin)[:export]
    assert_equal Provision::SUBMITTED, meal.reload.status

    delete bmid_export_unsubmit_path(export)

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match @admin.callsign, response.body

    saved = Bmid.find_for_person_year(@admin.id, YEAR)
    assert_equal Bmid::IN_PREP, saved.status
    assert_nil saved.batch
    assert_match "Un-submitted from print export", saved.notes

    assert_equal Provision::AVAILABLE, meal.reload.status
    assert_match Provision::BMID_UNSUBMIT_COMMENT, meal.comments
    assert_nil BmidExport.last, "the batch record must be removed"
  end

  test "un-submitting leaves a badge that moved on and says why" do
    approved_photo_for(@admin)
    ticket_for(@admin)
    meal = meal_for(@admin, pre_event_meals: true)
    export = EventreeBmidExport.export!([@admin.id], year: YEAR,
                                        batch_info: "Batch #1", exporter: @admin)[:export]
    Bmid.find_for_person_year(@admin.id, YEAR).update_columns(status: Bmid::READY_TO_PRINT)

    delete bmid_export_unsubmit_path(export)

    assert_response :unprocessable_entity
    assert_match "badge status is now", response.body
    assert_match @admin.callsign, response.body
    assert_equal Bmid::READY_TO_PRINT, Bmid.find_for_person_year(@admin.id, YEAR).status
    assert_equal Provision::SUBMITTED, meal.reload.status,
                 "a skipped badge's provisions must stay as they are"
    assert_nil BmidExport.last, "the batch record is removed even when nothing changed"
  end

  test "un-submitting is refused for a previous year's batch" do
    badge(@admin, title1: "Shift Lead")
    export = EventreeBmidExport.export!([@admin.id], year: YEAR,
                                        batch_info: "", exporter: @admin)[:export]
    export.update_columns(created_at: Time.zone.local(YEAR - 1, 8, 1))

    delete bmid_export_unsubmit_path(export)

    assert_redirected_to bmid_export_path
    assert_match "not available to un-submit", flash[:alert]
    assert_equal Bmid::SUBMITTED, Bmid.find_for_person_year(@admin.id, YEAR).status
    assert BmidExport.exists?(export.id)
  end

  test "un-submitting a batch that is already gone redirects with an alert" do
    delete bmid_export_unsubmit_path(999_999)

    assert_redirected_to bmid_export_path
    assert_match "not available to un-submit", flash[:alert]
  end

  test "un-submitting is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    delete bmid_export_unsubmit_path(1)

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  private

  def badge(holder, year: YEAR, status: Bmid::IN_PREP, **attributes)
    Bmid.create!(person: holder, year:, status:, **attributes)
  end

  def approved_photo_for(holder)
    create_photo(person: holder, status: PersonPhoto::APPROVED)
  end

  def ticket_for(holder, type: AccessDocument::SAP, status: AccessDocument::CLAIMED, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE, **attributes)
  end

  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, **attributes)
    Provision.create!(person: holder, type:, status:, source_year: YEAR,
                      expires_on: Date.new(YEAR + 3, 9, 1), **attributes)
  end

  def meal_for(holder, **attributes)
    provision_for(holder, type: Provision::MEALS, **attributes)
  end

  # The callsigns heading the selection table's rows. Scoped away from the
  # Previous Exports table, whose row headers are filenames.
  def selection_callsigns
    css_select("tbody th a[href^='/person/']").map { |cell| cell.text.strip }
  end
end
