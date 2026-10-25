# frozen_string_literal: true

require "test_helper"

# BMID > Manage Badges > the single-badge editor.
#
# The roster's Edit column used to link at /person/:id/bmid, which belongs to a
# person rather than to an event year: it loads and saves Current.year whatever
# row was clicked. This editor is the roster's own, so it takes the year with
# it, and it puts the admin back on the exact row they clicked with every
# filter and the sort still in place.
class Bmid::BadgesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  # Everything that decides what the roster was showing when the Edit link was
  # clicked. All of it has to survive the round trip.
  VIEW_QUERY = { year: YEAR, filter: BmidManagement::NONPRINT, title: "Shift Lead",
                 team: "Gate", meals: "any_eat", showers: "yes", qualified: "unqualified",
                 q: "lead", sort: "status", dir: "desc", mode: "edit" }.freeze

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @holder = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    Bmid.delete_all
    AccessDocument.delete_all
    Provision.delete_all
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

  # --- who may edit ---------------------------------------------------------

  test "the editor renders for an admin" do
    badge(@holder, title1: "Shift Lead")

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    assert_match "#{YEAR} BMID", response.body
    assert_match @holder.callsign, response.body
  end

  test "the editor renders with only the edit BMIDs role" do
    sign_in_as(@badger)
    badge(@holder, title1: "Shift Lead")

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
  end

  test "the editor is refused without the admin or edit BMIDs role" do
    badge(@holder, title1: "Shift Lead")
    sign_in_as(@outsider)

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  test "a save is refused without the admin or edit BMIDs role" do
    badge(@holder, title1: "Shift Lead")
    sign_in_as(@outsider)

    patch bmid_badge_path(person_id: @holder.id), params: { bmid: { title1: "Sneaky" } }

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
    assert_equal "Shift Lead", saved_badge(@holder).title1
  end

  # --- rendering ------------------------------------------------------------

  test "the editor renders the badge already on file" do
    badge(@holder, title1: "Shift Lead", team: "Gate", notes: "Arrives early.")

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    assert_select "input[name=?][value=?]", "bmid[title1]", "Shift Lead"
    assert_select "input[name=?][value=?]", "bmid[team]", "Gate"
    assert_select "textarea[name=?]", "bmid[notes]", text: /Arrives early/
    assert_select "select[name=?]", "bmid[status]"
    assert_select "select[name=?]", "bmid[admission_date]"
    # The leave-page guard the person's own badge page uses.
    assert_select "form[data-controller=?]", "form unsaved-changes"
    # Not decoration: Turbo Drive reads the redirect target off Response#url,
    # which the Fetch standard defines as excluding the fragment, so a Turbo
    # save throws away the #bmid-row-N that puts the admin back on their row.
    # A native submit lets the browser follow the redirect itself.
    assert_select "form[data-turbo=false]"
  end

  # The roster synthesizes a badge for everyone who qualifies, so the editor has
  # to open on a person who has never had one.
  test "the editor renders for a person with no badge yet and creates nothing" do
    assert_nil Bmid.find_for_person_year(@holder.id, YEAR)

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    assert_match "Save Badge", response.body
    assert_equal 0, Bmid.count, "opening the editor must not create a row"
    # A badge is addressed by person and year, so there is one address whether
    # or not a row is on file: the form PATCHes either way.
    assert_select "form[action=?]", bmid_badge_path(person_id: @holder.id)
    assert_select "form input[type=hidden][name=_method][value=patch]"
  end

  test "a person who does not exist is not found rather than a server error" do
    get edit_bmid_badge_path(person_id: 0)

    assert_response :not_found
  end

  test "meals, showers, and the vehicle record are shown but never badge fields" do
    badge(@holder, title1: "Shift Lead")
    meal_for(@holder, event_week_meals: true)
    provision_for(@holder)

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    # The three-up grid: the meals value renders, the vehicle record is labeled
    # in full (house rule: no "MVR" jargon) and marked read-only, and the one
    # kept line of copy states the only surprising behavior.
    assert_match "Event", response.body
    assert_match "Motor Vehicle Record", response.body
    assert_match "Read-only", response.body
    assert_match "save immediately", response.body
    # They belong to the person's provisions and event record, not to the badge,
    # so they are never columns this form writes.
    assert_select "input[name=?]", "bmid[meals]", count: 0
    assert_select "input[name=?]", "bmid[showers]", count: 0
    assert_select "select[name=?]", "bmid[meals]", count: 0
  end

  # The badge and its provisions are one thing to the printer, so the editor
  # offers the roster's own provision cells rather than sending the admin away
  # to a page that would throw away the badge edits in progress.
  test "the meals and showers cells open the provision dialog" do
    badge(@holder, title1: "Shift Lead")
    meal_for(@holder, event_week_meals: true)

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    # Meals: a pass on file, so the button opens the list of them.
    assert_select "a[href=?][data-turbo-frame=modal]",
                  bmid_provisions_path(person_id: @holder.id, year: YEAR,
                                       filter: BmidManagement::DEFAULT_FILTER,
                                       from: Bmid::ManageHelper::BADGE_ORIGIN,
                                       type: Provision::MEALS)
    # Showers: none on file, so it goes straight to the form.
    assert_select "a[href=?][data-turbo-frame=modal]",
                  new_bmid_provision_path(person_id: @holder.id, year: YEAR,
                                          filter: BmidManagement::DEFAULT_FILTER,
                                          from: Bmid::ManageHelper::BADGE_ORIGIN,
                                          type: Provision::WET_SPOT)
  end

  # The cells sit outside the badge form and hold no fields. That is what keeps
  # a provision save -- which commits on its own, immediately -- from marking the
  # badge form as changed or riding along with it.
  test "the provision cells are outside the badge form and hold no fields" do
    badge(@holder, title1: "Shift Lead")
    meal_for(@holder, event_week_meals: true)

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    assert_select "form" do |forms|
      forms.each do |form|
        assert_empty form.css("a[data-turbo-frame=modal]"),
                     "a provision button inside the badge form could dirty it"
      end
    end
    cells = css_select("##{bmid_meals_cell_id_for(@holder)}, ##{bmid_showers_cell_id_for(@holder)}")
    assert_equal 2, cells.size
    assert_no_match(/<(input|select|textarea)\b/, cells.to_s)
  end

  # The dialog's turbo_stream replaces the cells by id, so the editor has to
  # spell them the same way the roster does or a save would redraw nothing.
  test "the provision cells carry the same dom ids the dialog replaces" do
    badge(@holder, title1: "Shift Lead")

    get edit_bmid_badge_path(person_id: @holder.id)

    assert_response :success
    assert_select "##{bmid_meals_cell_id_for(@holder)}"
    assert_select "##{bmid_showers_cell_id_for(@holder)}"
  end

  # --- saving ---------------------------------------------------------------

  test "a save updates the badge and returns to the roster" do
    badge(@holder, title1: "Shift Lead")

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { status: Bmid::READY_TO_PRINT, title1: "Operations Manager",
                            title2: "Mentor", team: "Gate", notes: "Arrives early." } }

    assert_redirected_to roster_path
    assert_equal "Badge updated for #{@holder.callsign}.", flash[:success]

    kept = saved_badge(@holder)
    assert_equal Bmid::READY_TO_PRINT, kept.status
    assert_equal "Operations Manager", kept.title1
    assert_equal "Mentor", kept.title2
    assert_equal "Gate", kept.team
    assert_equal "Arrives early.", kept.notes
  end

  test "a save creates the badge for a person who never had one" do
    assert_nil Bmid.find_for_person_year(@holder.id, YEAR)

    assert_difference "Bmid.count", 1 do
      patch bmid_badge_path(person_id: @holder.id),
            params: { bmid: { status: Bmid::READY_TO_PRINT, title1: "Shift Lead" } }
    end

    assert_redirected_to roster_path
    assert_equal "Badge created for #{@holder.callsign}.", flash[:success]

    created = saved_badge(@holder)
    assert_equal "Shift Lead", created.title1
    assert_equal YEAR, created.year
    assert_equal @holder.id, created.person_id
  end

  test "a save cannot move the badge to another person or another year" do
    badge(@holder, title1: "Shift Lead")
    stranger = person(:auditor_ranger)

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { title1: "Operations Manager",
                            person_id: stranger.id, year: YEAR - 1 } }

    assert_redirected_to roster_path

    kept = saved_badge(@holder)
    assert_equal "Operations Manager", kept.title1
    assert_equal @holder.id, kept.person_id
    assert_equal YEAR, kept.year
    assert_nil Bmid.find_for_person_year(stranger.id, YEAR)
    assert_equal 1, Bmid.count
  end

  # Turbo drops a 200 rendered from a PATCH, so the re-render has to say 422.
  test "an invalid status is refused and the form comes back holding what was typed" do
    badge(@holder, title1: "Shift Lead")

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { status: "nonsense", title1: "Operations Manager" } }

    assert_response :unprocessable_entity
    assert_select "input[name=?][value=?]", "bmid[title1]", "Operations Manager"
    assert_equal "Shift Lead", saved_badge(@holder).title1
    assert_equal Bmid::IN_PREP, saved_badge(@holder).status
  end

  test "a blank title or team is stored as nothing at all" do
    badge(@holder, title1: "Shift Lead", title2: "Mentor", team: "Gate")

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { title1: "Shift Lead", title2: "", title3: "  ", team: "  " } }

    assert_redirected_to roster_path

    kept = saved_badge(@holder)
    assert_equal "Shift Lead", kept.title1
    assert_nil kept.title2
    assert_nil kept.title3
    assert_nil kept.team
  end

  # --- the year -------------------------------------------------------------

  # The bug this editor exists to fix: the person's own badge page has no year
  # of its own, so a prior-year row opened -- and saved -- the current year's
  # badge instead.
  test "a prior year edits that year's badge and leaves the current year's alone" do
    badge(@holder, title1: "This year")
    badge(@holder, year: YEAR - 1, title1: "Last year")

    get edit_bmid_badge_path(person_id: @holder.id, year: YEAR - 1)

    assert_response :success
    assert_match "#{YEAR - 1} BMID", response.body
    assert_select "input[name=?][value=?]", "bmid[title1]", "Last year"

    patch bmid_badge_path(person_id: @holder.id, year: YEAR - 1),
          params: { bmid: { title1: "Last year, edited" } }

    assert_redirected_to bmid_manage_path(year: YEAR - 1,
                                          anchor: "bmid-row-#{@holder.id}")
    assert_equal "Last year, edited", saved_badge(@holder, year: YEAR - 1).title1
    assert_equal "This year", saved_badge(@holder).title1
  end

  test "a prior year creates the badge for that year, not the current one" do
    assert_difference "Bmid.count", 1 do
      patch bmid_badge_path(person_id: @holder.id, year: YEAR - 1),
            params: { bmid: { title1: "Last year" } }
    end

    assert_equal YEAR - 1, saved_badge(@holder, year: YEAR - 1).year
    assert_nil Bmid.find_for_person_year(@holder.id, YEAR)
  end

  # The pass hanging off a prior-year badge is whichever one the person holds
  # NOW: AccessDocument.find_sap_for_person_ids is not year-scoped and the date
  # choices come from this year's settings. So a 2025 badge must not be able to
  # move the arrival date for the event the person is about to attend.
  test "a prior year cannot touch the SAP date" do
    badge(@holder, year: YEAR - 1, title1: "Last year")
    arrival = Time.zone.local(YEAR, 8, 12, 12, 0, 0)
    pass = ticket_for(@holder, access_date: arrival)

    get edit_bmid_badge_path(person_id: @holder.id, year: YEAR - 1)

    assert_response :success
    assert_select "select[name=?][disabled=disabled]", "bmid[admission_date]"
    assert_match "previous year", response.body

    # Even hand-crafted, past the disabled control.
    patch bmid_badge_path(person_id: @holder.id, year: YEAR - 1),
          params: { bmid: { title1: "Edited", admission_date: Date.new(YEAR, 8, 20).iso8601 } }

    assert_equal "Edited", saved_badge(@holder, year: YEAR - 1).title1
    assert_equal arrival.to_date, pass.reload.access_date.to_date,
                 "a prior-year badge must not move this year's arrival date"
  end

  # --- the year itself ------------------------------------------------------

  # ApplicationController#setup_year would turn this into 0, and a badge is
  # identified by person and year: the row would be real, and invisible to every
  # year the page offers.
  test "an unparseable year saves nothing into year zero" do
    patch bmid_badge_path(person_id: @holder.id, year: "abc"),
          params: { bmid: { title1: "Junk" } }

    assert_equal 0, Bmid.where(year: 0).count
    assert_equal "Junk", saved_badge(@holder).title1, "it falls back to the current year"
  end

  test "a year outside the offered range falls back to the current one" do
    patch bmid_badge_path(person_id: @holder.id, year: 1999),
          params: { bmid: { title1: "Too early" } }

    assert_nil Bmid.find_for_person_year(@holder.id, 1999)
    assert_equal "Too early", saved_badge(@holder).title1
  end

  # --- the SAP write-through ------------------------------------------------

  # THE load-bearing invariant. Bmid#after_save pushes the badge's access date
  # out to the person's access documents, so a badge saved without its
  # relationships loaded would blank an arrival date no one touched.
  test "a title-only save leaves an existing SAP date exactly where it was" do
    badge(@holder, title1: "Shift Lead")
    arrival = Time.zone.local(YEAR, 8, 12, 12, 0, 0)
    pass = ticket_for(@holder, access_date: arrival)

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { title1: "Operations Manager" } }

    assert_redirected_to roster_path
    assert_equal "Operations Manager", saved_badge(@holder).title1
    assert_equal arrival.to_date, pass.reload.access_date.to_date
  end

  test "changing the SAP date writes through to the person's access documents" do
    badge(@holder, title1: "Shift Lead")
    pass = ticket_for(@holder, access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { admission_date: "#{YEAR}-08-12" } }

    assert_redirected_to roster_path
    assert_equal Date.new(YEAR, 8, 12), pass.reload.access_date.to_date
  end

  # The form renders the SAP control disabled on these rows, so a date arriving
  # anyway did not come from this page. It has to be dropped rather than
  # written: update_sap would stamp it onto the other passes the person holds,
  # including banked ones no page ever showed. Same rule as the bulk save.
  test "a SAP date is ignored for a badge whose pass cannot be edited" do
    badge(@holder, title1: "Shift Lead")
    ticket_for(@holder, status: AccessDocument::SUBMITTED,
                        access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    banked = ticket_for(@holder, type: AccessDocument::STAFF_CREDENTIAL,
                                 status: AccessDocument::BANKED)

    patch bmid_badge_path(person_id: @holder.id),
          params: { bmid: { title1: "Shift Lead", admission_date: "#{YEAR}-08-30" } }

    assert_redirected_to roster_path
    assert_nil banked.reload.access_date
  end

  # --- the round trip -------------------------------------------------------

  test "the editor carries the whole view back to the roster row it came from" do
    badge(@holder, title1: "Shift Lead")

    get edit_bmid_badge_path(person_id: @holder.id, **VIEW_QUERY)

    assert_response :success
    back = bmid_manage_path(**VIEW_QUERY, anchor: "bmid-row-#{@holder.id}")
    # The back link in the hero and the Cancel button both land on the row.
    assert_select "a[href=?]", back, minimum: 2
    # A failed save has to re-post to the same place, so the form action keeps
    # the view too.
    assert_select "form[action=?]", bmid_badge_path(person_id: @holder.id, **VIEW_QUERY)
  end

  test "a save redirects to the roster row carrying every view param" do
    badge(@holder, title1: "Shift Lead")

    patch bmid_badge_path(person_id: @holder.id, **VIEW_QUERY),
          params: { bmid: { title1: "Operations Manager" } }

    assert_redirected_to bmid_manage_path(**VIEW_QUERY, anchor: "bmid-row-#{@holder.id}")
  end

  test "a created badge redirects to its own roster row" do
    patch bmid_badge_path(person_id: @holder.id, **VIEW_QUERY),
          params: { bmid: { title1: "Shift Lead" } }

    assert_redirected_to bmid_manage_path(**VIEW_QUERY, anchor: "bmid-row-#{@holder.id}")
  end

  # A hand-edited URL cannot smuggle anything into the roster: the params are
  # passed straight back, and Bmid::ManageController sanitizes every one of them
  # on arrival.
  test "params the roster does not use are not carried back" do
    badge(@holder, title1: "Shift Lead")

    patch bmid_badge_path(person_id: @holder.id, year: YEAR, bogus: "nope"),
          params: { bmid: { title1: "Operations Manager" } }

    assert_redirected_to bmid_manage_path(year: YEAR, anchor: "bmid-row-#{@holder.id}")
  end

  private

  def badge(holder, year: YEAR, status: Bmid::IN_PREP, **attributes)
    Bmid.create!(person: holder, year:, status:, **attributes)
  end

  def saved_badge(holder, year: YEAR)
    Bmid.find_for_person_year(holder.id, year)
  end

  # Where a save with no view params lands: the roster's default view, scrolled
  # to the row that was edited.
  def roster_path(holder = @holder)
    bmid_manage_path(anchor: "bmid-row-#{holder.id}")
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

  # Spelled from the person, the way the helper does: a badge has no id until
  # its first save, so the cells cannot be keyed on one.
  def bmid_meals_cell_id_for(holder) = "bmid-meals-cell-#{holder.id}"

  def bmid_showers_cell_id_for(holder) = "bmid-showers-cell-#{holder.id}"
end
