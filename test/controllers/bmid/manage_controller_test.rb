# frozen_string_literal: true

require "test_helper"

# BMID > Manage Badges: the year's whole badge roster, its category picker, its
# five secondary filters, its sortable columns, and the CSV export.
#
# The categories sweep whole tables and the shared fixtures belong to other
# suites, so every test starts from empty tables and builds exactly the badges
# it needs.
class Bmid::ManageControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  NOTHING_SUBMITTED = Bmid::ManageController::NOTHING_SUBMITTED

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
    AccessDocument.delete_all
    Provision.delete_all
    PersonSlot.delete_all
    Slot.delete_all
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

  test "the roster renders for an admin" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
    assert_match "Showing 1 of 1 badge", response.body
  end

  test "the roster renders with only the edit BMIDs role" do
    sign_in_as(@badger)
    badge(@badger, title1: "Shift Lead")

    get bmid_manage_path

    assert_response :success
    assert_equal [@badger.callsign], rendered_callsigns
  end

  test "the roster is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    get bmid_manage_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  # PRD section 2 records a deliberate deviation: upstream let Role::VC read this
  # listing and this port does not. A denial test that only signs in as somebody
  # with no roles at all proves "no one gets in", not "a VC does not" -- adding
  # Role::VC to the gate would keep it green and silently reverse the decision.
  test "the roster is refused for a VC" do
    ensure_role(Role::VC, "VC")
    grant_role(@outsider, Role::VC)
    sign_in_as(@outsider)

    get bmid_manage_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  # --- categories -----------------------------------------------------------

  test "every category renders" do
    badge(@admin, title1: "Shift Lead", status: Bmid::ISSUES)
    badge(@badger, status: Bmid::SUBMITTED)
    badge(person(:retired_ranger), status: Bmid::READY_TO_PRINT)

    BmidManagement::FILTERS.each do |filter|
      get bmid_manage_path(filter:)

      assert_response :success, "#{filter} should render"
      assert_select "select[name=?] option[value=?][selected]", "filter", filter
    end
  end

  test "the category picks who is listed" do
    lead = @admin
    badge(lead, title1: "Shift Lead")
    blocked = person(:retired_ranger)
    badge(blocked, status: Bmid::DO_NOT_PRINT)

    get bmid_manage_path(filter: BmidManagement::SPECIAL)
    assert_equal [lead.callsign], rendered_callsigns

    get bmid_manage_path(filter: BmidManagement::NONPRINT)
    assert_equal [blocked.callsign], rendered_callsigns
  end

  test "an unknown category falls back to the default" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(filter: "nonsense")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "select[name=?] option[value=?][selected]", "filter", BmidManagement::DEFAULT_FILTER
  end

  # A person who qualifies for a category but has no badge row yet still has to
  # appear -- that is the whole point of the page.
  test "a person with no badge row is listed as a synthesized badge" do
    alpha = person(:alpha_ranger)

    get bmid_manage_path(filter: BmidManagement::ALPHA)

    assert_response :success
    assert_includes rendered_callsigns, alpha.callsign
    assert_equal 0, Bmid.count, "listing must not create rows"
  end

  test "the year param reaches the loader" do
    this_year = @admin
    badge(this_year, title1: "Shift Lead")
    last_year = person(:retired_ranger)
    badge(last_year, year: YEAR - 1, title1: "Shift Lead")

    get bmid_manage_path(year: YEAR - 1)

    assert_response :success
    assert_equal [last_year.callsign], rendered_callsigns
    assert_match "#{YEAR - 1} BMID Management", response.body
    # Looking at a year that has already been printed is worth saying out loud.
    assert_match "a previous year", response.body
  end

  # --- secondary filters ----------------------------------------------------

  test "the title filter matches any of the three title slots" do
    first = @admin
    badge(first, title1: "Shift Lead")
    third = person(:retired_ranger)
    badge(third, title3: "Shift Lead")
    other = person(:auditor_ranger)
    badge(other, title1: "Green Dot")

    get bmid_manage_path(title: "Shift Lead")

    assert_response :success
    assert_equal [first, third].map(&:callsign).sort, rendered_callsigns.sort
    assert_not_includes rendered_callsigns, other.callsign
    assert_match "Showing 2 of 3 badges", response.body
  end

  test "the team filter matches part of the team" do
    gate = @admin
    badge(gate, title1: "Lead", team: "Gate/Perimeter")
    other = person(:retired_ranger)
    badge(other, title1: "Lead", team: "Mentors")

    get bmid_manage_path(team: "Gate")

    assert_response :success
    assert_equal [gate.callsign], rendered_callsigns
    assert_not_includes rendered_callsigns, other.callsign
  end

  test "the meals filter narrows by what the badge holder is fed" do
    all_eats = @admin
    badge(all_eats, title1: "Lead")
    meal_for(all_eats, pre_event_meals: true, event_week_meals: true, post_event_meals: true)

    event_only = person(:retired_ranger)
    badge(event_only, title1: "Lead")
    meal_for(event_only, event_week_meals: true)

    get bmid_manage_path(meals: "all_eat")
    assert_equal [all_eats.callsign], rendered_callsigns

    get bmid_manage_path(meals: "event_week")
    assert_equal [event_only.callsign], rendered_callsigns

    # Upstream's "Any Eats" means all-eats OR event-week-only, not "any meal".
    get bmid_manage_path(meals: "any_eat")
    assert_equal [all_eats, event_only].map(&:callsign).sort, rendered_callsigns.sort
  end

  # Upstream offered meals and showers as one "Wants" select, so the two could
  # never be asked together. Split, they can.
  test "the showers filter answers both ways and combines with meals" do
    washed = @admin
    badge(washed, title1: "Lead")
    provision_for(washed)
    meal_for(washed, pre_event_meals: true, event_week_meals: true, post_event_meals: true)

    dry = person(:retired_ranger)
    badge(dry, title1: "Lead")
    meal_for(dry, pre_event_meals: true, event_week_meals: true, post_event_meals: true)

    get bmid_manage_path(showers: "yes")
    assert_equal [washed.callsign], rendered_callsigns

    get bmid_manage_path(showers: "no")
    assert_equal [dry.callsign], rendered_callsigns

    get bmid_manage_path(meals: "all_eat", showers: "yes")
    assert_equal [washed.callsign], rendered_callsigns
    assert_match "Meals: All Eat", response.body
    assert_match "Showers: Yes", response.body
  end

  # A select whose only choice is "All" cannot narrow anything, so it goes out
  # disabled with a sentence saying why -- and the matching filter is dropped,
  # which is what keeps a chip from outliving the control that would remove it.
  test "a category carrying none of a thing disables that select" do
    badge(@admin, title1: "Lead")

    get bmid_manage_path(team: "Gate", meals: "all_eat", showers: "yes")

    assert_response :success
    assert_select "select[name=team][disabled]"
    assert_select "select[name=meals][disabled]"
    assert_select "select[name=showers][disabled]"
    assert_select "select[name=title][disabled]", false
    assert_match "No one in this category is being fed.", response.body
    assert_match "No one in this category has shower access.", response.body
    assert_no_match(/Meals: All Eat/, response.body)
    assert_no_match(/Showers: Yes/, response.body)
  end

  test "the print qualification filter splits the roster in two" do
    qualified = @admin
    badge(qualified, title1: "Lead")
    ticket_for(qualified)

    unqualified = person(:retired_ranger)
    badge(unqualified, title1: "Lead")

    get bmid_manage_path(qualified: "qualified")
    assert_equal [qualified.callsign], rendered_callsigns

    get bmid_manage_path(qualified: "unqualified")
    assert_equal [unqualified.callsign], rendered_callsigns
  end

  test "the text search matches callsign, titles, team, and notes, case-insensitively" do
    by_title = @admin
    badge(by_title, title1: "Shift Lead")
    by_team = person(:retired_ranger)
    badge(by_team, title1: "Green Dot", team: "Shiftless")
    by_notes = person(:auditor_ranger)
    badge(by_notes, title1: "Green Dot", notes: "Covering the shift.")
    missing = person(:alpha_ranger)
    badge(missing, title1: "Green Dot")

    get bmid_manage_path(q: "SHIFT")

    assert_response :success
    assert_equal [by_title, by_team, by_notes].map(&:callsign).sort, rendered_callsigns.sort
    assert_not_includes rendered_callsigns, missing.callsign
  end

  # The search text comes straight from a URL, so it is a plain substring: a
  # user-supplied regular expression would be a denial-of-service surface.
  test "the text search treats its input as literal text, not a pattern" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(q: ".*")

    assert_response :success
    assert_empty rendered_callsigns
  end

  test "the filters narrow together and each draws a chip" do
    wanted = @admin
    badge(wanted, title1: "Shift Lead", team: "Gate")
    badge(person(:retired_ranger), title1: "Shift Lead", team: "Mentors")
    badge(person(:auditor_ranger), title1: "Green Dot", team: "Gate")

    get bmid_manage_path(title: "Shift Lead", team: "Gate")

    assert_response :success
    assert_equal [wanted.callsign], rendered_callsigns
    assert_match "Title: Shift Lead", response.body
    assert_match "Team: Gate", response.body
    assert_match "Showing 1 of 3 badges", response.body
  end

  # The category is the panel's first and widest control. Drawing no chip for it
  # read as a filter bar that had stopped working.
  test "the category draws a chip once it is not the default" do
    badge(@admin, title1: "Shift Lead", status: Bmid::ISSUES)

    get bmid_manage_path(filter: BmidManagement::NONPRINT)

    assert_response :success
    assert_match "Category: BMIDs marked as Issues or Do Not Print", response.body
    # Its × has somewhere to go: back to the default category.
    assert_select "a[href=?]", bmid_manage_path(year: YEAR)
  end

  test "the default category draws no chip" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(filter: BmidManagement::DEFAULT_FILTER)

    assert_response :success
    assert_no_match(/Category:/, response.body)
  end

  # Removing one filter has to leave the others -- including the category, which
  # is dropped from the base params precisely so its own chip can drop it.
  test "removing one chip keeps the rest of the view" do
    badge(@admin, title1: "Shift Lead", status: Bmid::ISSUES)

    get bmid_manage_path(filter: BmidManagement::NONPRINT, title: "Shift Lead", sort: "status")

    assert_response :success
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, sort: "status", filter: BmidManagement::NONPRINT)
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, sort: "status", title: "Shift Lead")
  end

  # A hand-edited URL must not be able to empty the page or park a label in the
  # filter bar that the panel below it does not offer.
  test "an unknown filter value falls back to no filter" do
    badge(@admin, title1: "Shift Lead")
    badge(person(:retired_ranger), title1: "Green Dot")

    get bmid_manage_path(title: "Nonexistent", team: "Nowhere",
                         meals: "bogus", showers: "bogus", qualified: "bogus")

    assert_response :success
    assert_equal 2, rendered_callsigns.size
    assert_match "Showing 2 of 2 badges", response.body
  end

  # --- sorting --------------------------------------------------------------

  test "the roster sorts by callsign ascending by default" do
    zed = badge_for_callsign("Zebra", title1: "Lead")
    abe = badge_for_callsign("Abacus", title1: "Lead")

    get bmid_manage_path

    assert_response :success
    assert_equal [abe, zed], rendered_callsigns
  end

  test "a column sorts both ways and empties stay last" do
    third = badge_for_callsign("Carol", title1: "Charlie")
    first = badge_for_callsign("Alice", title1: "Alpha")
    blank = badge_for_callsign("Bob", title2: "Bravo")

    get bmid_manage_path(sort: "title1")
    assert_equal [first, third, blank], rendered_callsigns

    get bmid_manage_path(sort: "title1", dir: "desc")
    assert_equal [third, first, blank], rendered_callsigns
  end

  test "an unknown sort column or direction falls back to callsign ascending" do
    zed = badge_for_callsign("Zebra", title1: "Lead")
    abe = badge_for_callsign("Abacus", title1: "Lead")

    get bmid_manage_path(sort: "nonsense", dir: "sideways")

    assert_response :success
    assert_equal [abe, zed], rendered_callsigns
  end

  test "the SAP column sorts undated passes first, then no pass, then any-time, then dates" do
    dated = badge_for_callsign("Dated", title1: "Lead")
    ticket_for(person_named("Dated"), access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    any_time = badge_for_callsign("Anytime", title1: "Lead")
    ticket_for(person_named("Anytime"), access_any_time: true)

    undated = badge_for_callsign("Undated", title1: "Lead")
    ticket_for(person_named("Undated"))

    none = badge_for_callsign("None", title1: "Lead")

    get bmid_manage_path(sort: "sap")

    assert_response :success
    assert_equal [undated, none, any_time, dated], rendered_callsigns
  end

  test "a boolean column sorts the flagged rows first" do
    washed = badge_for_callsign("Washed", title1: "Lead")
    provision_for(person_named("Washed"))
    dusty = badge_for_callsign("Dusty", title1: "Lead")

    get bmid_manage_path(sort: "showers")
    assert_equal [washed, dusty], rendered_callsigns

    get bmid_manage_path(sort: "showers", dir: "desc")
    assert_equal [dusty, washed], rendered_callsigns
  end

  test "the heading links carry the category, the year, and the active filters" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(filter: BmidManagement::SPECIAL, title: "Shift Lead")

    assert_response :success
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, filter: BmidManagement::SPECIAL,
                                   title: "Shift Lead", sort: "status", dir: "asc")
  end

  # --- page furniture -------------------------------------------------------

  test "an unqualified badge still in prep raises the page warning" do
    badge(@admin, title1: "Shift Lead", status: Bmid::IN_PREP)

    get bmid_manage_path

    assert_response :success
    assert_match "do not meet the printing qualifications", response.body
  end

  test "a qualified roster does not raise the page warning" do
    badge(@admin, title1: "Shift Lead")
    ticket_for(@admin)

    get bmid_manage_path

    assert_response :success
    assert_no_match(/do not meet the printing qualifications/, response.body)
  end

  test "the empty roster and the filtered-empty roster say different things" do
    get bmid_manage_path

    assert_response :success
    assert_match "No BMIDs were found for #{YEAR}", response.body

    badge(@admin, title1: "Shift Lead")
    get bmid_manage_path(q: "nothing matches this")

    assert_response :success
    assert_match "No BMIDs match the filter criteria.", response.body
  end

  # The editor stays inside this namespace: it takes the year with it, and it
  # carries the whole view so a save comes back to the row that was clicked.
  test "each row offers a link to the in-namespace badge editor" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path

    assert_response :success
    assert_select "a[href=?]", edit_bmid_badge_path(person_id: @admin.id, year: YEAR,
                                                    filter: BmidManagement::DEFAULT_FILTER),
                  text: "Edit"
  end

  test "the per-row edit link carries the active filters and the sort" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(filter: BmidManagement::SPECIAL, title: "Shift Lead",
                         sort: "status", dir: "desc")

    assert_response :success
    assert_select "a[href=?]",
                  edit_bmid_badge_path(person_id: @admin.id, year: YEAR,
                                       filter: BmidManagement::SPECIAL, title: "Shift Lead",
                                       sort: "status", dir: "desc")
  end

  # The editor round-trips the view by permitting a fixed list of params
  # (Bmid::ManageHelper::VIEW_PARAMS); the roster builds its links from
  # @index_params. Two spellings of "the current view" that could disagree, so
  # this pins them: with every one of them active, the Edit link carries the lot.
  #
  # All but mode, which cannot be exercised here: Table View is the only layout
  # with an Edit column, so the link is only ever drawn with mode absent. The
  # editor still carries it back when it arrives -- see the badges suite.
  test "the per-row edit link carries every param the view is made of" do
    badge(@admin, title1: "Shift Lead", team: "Gate")
    meal_for(@admin, pre_event_meals: true, event_week_meals: true, post_event_meals: true)
    provision_for(@admin)

    view = { year: YEAR, filter: BmidManagement::SPECIAL, title: "Shift Lead", team: "Gate",
             meals: "all_eat", showers: "yes", qualified: "unqualified", q: "lead",
             sort: "status", dir: "desc" }
    assert_equal (Bmid::ManageHelper::VIEW_PARAMS - [:mode]).sort, view.keys.sort,
                 "this test has to exercise every view param the roster can draw"

    get bmid_manage_path(view)

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "a[href=?]", edit_bmid_badge_path(view.merge(person_id: @admin.id))
  end

  # The old link went to the person's own badge page, which has no year of its
  # own -- it always loads and saves Current.year -- so it had to be withheld on
  # a prior year. The editor takes the year, so the link is offered for every
  # year and edits the badge the row is actually showing.
  test "the per-row edit link is offered on a prior year and points at that year" do
    badge(@admin, title1: "Shift Lead")
    earlier = person(:retired_ranger)
    badge(earlier, year: YEAR - 1, title1: "Shift Lead")

    get bmid_manage_path(year: YEAR - 1)

    assert_response :success
    assert_equal [earlier.callsign], rendered_callsigns
    assert_select "a[href=?]",
                  edit_bmid_badge_path(person_id: earlier.id, year: YEAR - 1,
                                       filter: BmidManagement::DEFAULT_FILTER),
                  text: "Edit"
    # Nothing points at the person's own badge page any more: it would open --
    # and save -- the current year's badge instead of this one.
    assert_select "a[href=?]", person_bmid_path(earlier), count: 0
    # The person's own callsign link is unaffected -- reading the record is fine.
    assert_select "a[href=?]", person_path(earlier), text: earlier.callsign
  end

  test "the edit mode button points at the same view" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(title: "Shift Lead")

    assert_response :success
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                   title: "Shift Lead", mode: "edit")
  end

  # --- edit mode ------------------------------------------------------------

  test "edit mode turns the cells into fields on the same URL" do
    badge(@admin, title1: "Shift Lead", team: "Gate", notes: "Arrives early.")

    get bmid_manage_path(mode: "edit")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    assert_select "tr#bmid-row-#{@admin.id}"
    assert_select "select[name=?]", "bmids[#{@admin.id}][status]"
    assert_select "input[name=?][value=?]", "bmids[#{@admin.id}][title1]", "Shift Lead"
    assert_select "input[name=?][value=?]", "bmids[#{@admin.id}][team]", "Gate"
    assert_select "textarea[name=?]", "bmids[#{@admin.id}][notes]"
    # The row stays identifiable even if every visible value is cleared.
    assert_select "input[type=hidden][name=?]", "bmids[#{@admin.id}][person_id]"
    assert_select "form[action=?]",
                  bmid_manage_update_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER, mode: "edit")
    # ui_form always adds its own "form" controller, so the two this page
    # needs have to compose with it rather than replace it.
    assert_select "form[data-controller=?]", "form bulk-edit unsaved-changes"
    assert_select "form[data-bulk-edit-dirty-class=?]", Bmid::ManageHelper::DIRTY_ROW_CLASS
  end

  test "the mode toggle flips between the two layouts and keeps every other param" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(title: "Shift Lead", mode: "edit")

    assert_response :success
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                   title: "Shift Lead")
    # Every link the edit page draws keeps the mode, or a filter change would
    # silently throw the edits away.
    assert_select "a[href=?]",
                  bmid_manage_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                   title: "Shift Lead", mode: "edit", sort: "status", dir: "asc")
    assert_select "input[type=hidden][name=mode][value=edit]"
  end

  # Only five of the seven statuses are offered, but a badge already carrying a
  # reprint status must still be able to show it -- otherwise saving an
  # untouched row would silently demote it to Prep.
  test "the status select offers five statuses, plus the row's own when it is a reprint" do
    badge(@admin, title1: "Shift Lead")
    reprint = person(:retired_ranger)
    badge(reprint, title1: "Green Dot", status: Bmid::READY_TO_REPRINT_LOST)

    get bmid_manage_path(mode: "edit")

    assert_response :success
    assert_select "select[name=?] option", "bmids[#{@admin.id}][status]", count: 5
    assert_select "select[name=?] option[value=?][selected]",
                  "bmids[#{reprint.id}][status]", Bmid::READY_TO_REPRINT_LOST
  end

  # Disabled, not absent. The date on a submitted pass is the date the badge
  # will print with, and it has to stay readable in the mode the admin is
  # actually editing in -- Table View shows it, but switching there would throw
  # away every edit in progress.
  test "the SAP date is shown but disabled when there is nothing to change" do
    badge(@admin, title1: "Shift Lead")
    submitted = person(:retired_ranger)
    badge(submitted, title1: "Green Dot")
    ticket_for(submitted, status: AccessDocument::SUBMITTED,
                          access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    editable = person(:auditor_ranger)
    badge(editable, title1: "Green Dot")
    ticket_for(editable)

    get bmid_manage_path(mode: "edit")

    assert_response :success
    assert_select "select[name=?][disabled]", "bmids[#{@admin.id}][admission_date]"
    assert_select "select[name=?][disabled]", "bmids[#{submitted.id}][admission_date]"
    assert_select "select[name=?] option[value=?][selected]",
                  "bmids[#{submitted.id}][admission_date]", "#{YEAR}-08-20"
    # The row that can still be changed keeps a live control.
    assert_select "select[name=?]:not([disabled])", "bmids[#{editable.id}][admission_date]"
    assert_match "SAP missing", response.body
    assert_match "SAP submitted", response.body
  end

  # --- provision cells ------------------------------------------------------

  test "edit mode offers to add a provision the person does not have yet" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(mode: "edit")

    assert_response :success
    assert_select "a[href=?][data-turbo-frame=modal]",
                  new_bmid_provision_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                          person_id: @admin.id, type: Provision::WET_SPOT)
    assert_select "a[href=?][data-turbo-frame=modal]",
                  new_bmid_provision_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                          person_id: @admin.id, type: Provision::MEALS)
  end

  # A person who already holds a provision of the type gets the list, not a
  # deep link into one record: holding two of a type is legal, and jumping
  # straight into the lowest-id one hid the others and left a second pass
  # impossible to add from here.
  test "edit mode offers to manage the provisions the cell is describing" do
    badge(@admin, title1: "Shift Lead")
    provision_for(@admin)
    meal_for(@admin, event_week_meals: true)

    get bmid_manage_path(mode: "edit")

    assert_response :success
    assert_select "a[href=?][data-turbo-frame=modal]",
                  bmid_provisions_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                       person_id: @admin.id, type: Provision::WET_SPOT)
    assert_select "a[href=?][data-turbo-frame=modal]",
                  bmid_provisions_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                       person_id: @admin.id, type: Provision::MEALS)
  end

  test "the read-only table offers no provision buttons" do
    badge(@admin, title1: "Shift Lead")
    provision_for(@admin)

    get bmid_manage_path

    assert_response :success
    assert_select "span#bmid-showers-cell-#{@admin.id}"
    assert_select "span#bmid-showers-cell-#{@admin.id} a", count: 0
    # Within the page itself: the account menu's Bug Report link opens a dialog
    # too, on every page.
    assert_select "main a[data-turbo-frame=modal]", count: 0
  end

  # --- bulk save ------------------------------------------------------------

  test "a bulk save updates every submitted row" do
    first = @admin
    badge(first, title1: "Shift Lead")
    second = person(:retired_ranger)
    badge(second, title1: "Green Dot")

    patch_rows(first.id => { title1: "Operations Manager", team: "Gate" },
               second.id => { title1: "Green Dot", title2: "Mentor", status: Bmid::READY_TO_PRINT })

    assert_redirected_to edit_return_path
    assert_equal "2 badges updated.", flash[:success]

    assert_equal "Operations Manager", saved_badge(first).title1
    assert_equal "Gate", saved_badge(first).team
    assert_equal "Mentor", saved_badge(second).title2
    assert_equal Bmid::READY_TO_PRINT, saved_badge(second).status
  end

  test "a bulk save creates the badge for a person who never had one" do
    alpha = person(:alpha_ranger)
    assert_nil Bmid.find_for_person_year(alpha.id, YEAR)
    ActionLog.delete_all

    assert_difference "Bmid.count", 1 do
      patch_rows({ alpha.id => { title1: "Alpha", status: Bmid::READY_TO_PRINT } },
                 filter: BmidManagement::ALPHA)
    end

    created = saved_badge(alpha)
    assert_equal "Alpha", created.title1
    assert_equal Bmid::READY_TO_PRINT, created.status
    assert_equal YEAR, created.year
    # Creating a badge is the defining act of this page, so it is audited just
    # as an edit is -- "who made this?" is the same question as "who changed it?".
    assert_equal [alpha.id], ActionLog.where(event: "bmid-create").pluck(:target_person_id)
  end

  test "a bulk save cannot move a badge to another person or another year" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    other = person(:retired_ranger)

    patch_rows(holder.id => { title1: "Operations Manager",
                              person_id: other.id, year: YEAR - 1 })

    assert_redirected_to edit_return_path

    kept = saved_badge(holder)
    assert_equal "Operations Manager", kept.title1
    assert_equal holder.id, kept.person_id
    assert_equal YEAR, kept.year
    assert_nil Bmid.find_for_person_year(other.id, YEAR)
    assert_equal 1, Bmid.count
  end

  # One bad value must not hold back the rest of the batch.
  test "an invalid row is reported while the rest of the batch still saves" do
    good = @admin
    badge(good, title1: "Shift Lead")
    bad = person(:retired_ranger)
    badge(bad, title1: "Green Dot")

    patch_rows(good.id => { title1: "Operations Manager" },
               bad.id => { title1: "Trainer", status: "nonsense" })

    # Turbo drops a 200 rendered from a PATCH, so the re-render has to say 422.
    assert_response :unprocessable_entity
    assert_equal "Operations Manager", saved_badge(good).title1
    assert_equal "Green Dot", saved_badge(bad).title1
    assert_equal Bmid::IN_PREP, saved_badge(bad).status
    assert_match "1 badge could not be saved", response.body
    assert_match bad.callsign, response.body
  end

  # The failed row comes back holding what was submitted, marked dirty, so the
  # fix is one edit away rather than a retype.
  test "a failed row is re-rendered dirty with the submitted values" do
    bad = @admin
    badge(bad, title1: "Shift Lead")

    patch_rows(bad.id => { title1: "Trainer", status: "nonsense" })

    assert_response :unprocessable_entity
    assert_select "tr#bmid-row-#{bad.id}[data-dirty=true]"
    assert_select "input[name=?][value=?]", "bmids[#{bad.id}][title1]", "Trainer"
    # The submitted status has to stay on screen even though the grid does not
    # normally offer it.
    assert_select "select[name=?] option[value=nonsense][selected]", "bmids[#{bad.id}][status]"
    # The counter starts where the server left it, rather than claiming nothing
    # has changed until the browser catches up.
    assert_match "1 row changed", response.body
    # errors.format is "%{message}" app-wide, so the summary has to name the
    # attribute itself or it reads as a sentence with no subject.
    assert_match "Status is not included in the list", response.body
  end

  # The failed row is holding the values that were submitted, so re-running the
  # secondary filters over it can push it out of its own error report: the
  # callout names a callsign and the row it points at is gone, taking the
  # admin's typing with it.
  test "a failed row survives a title filter its submitted title no longer matches" do
    bad = @admin
    badge(bad, title1: "Shift Lead")
    # A second badge keeps "Shift Lead" among the offered titles, so the filter
    # stays active instead of falling back to no filter.
    badge(person(:retired_ranger), title1: "Shift Lead")

    patch_rows({ bad.id => { title1: "Operations Manager", status: "nonsense" } },
               title: "Shift Lead")

    assert_response :unprocessable_entity
    assert_select "tr#bmid-row-#{bad.id}[data-dirty=true]"
    assert_select "input[name=?][value=?]", "bmids[#{bad.id}][title1]", "Operations Manager"
    assert_match "1 row changed", response.body
  end

  test "a failed row survives a text search its submitted values no longer match" do
    bad = @admin
    badge(bad, title1: "Shift Lead")

    patch_rows({ bad.id => { title1: "Operations Manager", status: "nonsense" } },
               q: "Shift")

    assert_response :unprocessable_entity
    assert_select "tr#bmid-row-#{bad.id}[data-dirty=true]"
    assert_select "input[name=?][value=?]", "bmids[#{bad.id}][title1]", "Operations Manager"
    assert_match "1 row changed", response.body
  end

  test "a blank title or team is stored as nothing at all" do
    holder = @admin
    badge(holder, title1: "Shift Lead", title2: "Mentor", team: "Gate")

    patch_rows(holder.id => { title1: "Shift Lead", title2: "", team: "  " })

    assert_redirected_to edit_return_path

    kept = saved_badge(holder)
    assert_equal "Shift Lead", kept.title1
    assert_nil kept.title2
    assert_nil kept.team
  end

  test "rows that were not submitted are left alone" do
    edited = @admin
    badge(edited, title1: "Shift Lead")
    untouched = person(:retired_ranger)
    badge(untouched, title1: "Green Dot", team: "Mentors", notes: "Leave me be.")

    patch_rows(edited.id => { title1: "Operations Manager" })

    assert_redirected_to edit_return_path
    assert_equal "1 badge updated.", flash[:success]

    kept = saved_badge(untouched)
    assert_equal "Green Dot", kept.title1
    assert_equal "Mentors", kept.team
    assert_equal "Leave me be.", kept.notes
  end

  # Only the dirty rows are supposed to travel, but that is the browser's doing:
  # if the bulk-edit controller never connects, one click submits every row on
  # screen. Saving them all would create a badge for every synthesized person,
  # write an audit row each, and push the SAP date back out over documents
  # no one edited -- so the server checks for itself.
  test "a row carrying the values it already holds is not saved" do
    holder = @admin
    badge(holder, title1: "Shift Lead", team: "Gate", notes: "Arrives early.")
    ActionLog.delete_all

    patch_rows(holder.id => { status: Bmid::IN_PREP, title1: "Shift Lead", title2: "",
                              title3: "", team: "Gate", notes: "Arrives early." })

    assert_redirected_to edit_return_path
    assert_equal "No changes were submitted, so nothing was saved.", flash[:info]
    assert_empty ActionLog.where(event: "bmid-update")
  end

  test "an unchanged synthesized row does not create a badge" do
    alpha = person(:alpha_ranger)
    ActionLog.delete_all

    assert_no_difference "Bmid.count" do
      patch_rows({ alpha.id => { status: Bmid::IN_PREP, title1: "", title2: "",
                                 title3: "", team: "", notes: "" } },
                 filter: BmidManagement::ALPHA)
    end

    assert_equal "No changes were submitted, so nothing was saved.", flash[:info]
    assert_empty ActionLog.where(event: "bmid-create")
  end

  test "only the row that actually changed is saved" do
    changed = @admin
    badge(changed, title1: "Shift Lead")
    unchanged = person(:retired_ranger)
    badge(unchanged, title1: "Green Dot")
    ActionLog.delete_all

    patch_rows(changed.id => { status: Bmid::IN_PREP, title1: "Operations Manager" },
               unchanged.id => { status: Bmid::IN_PREP, title1: "Green Dot" })

    assert_redirected_to edit_return_path
    assert_equal "1 badge updated.", flash[:success]
    assert_equal [changed.id], ActionLog.where(event: "bmid-update").pluck(:target_person_id)
  end

  test "a person id outside the category is ignored rather than fatal" do
    listed = @admin
    badge(listed, title1: "Shift Lead")
    stranger = person(:retired_ranger)

    patch_rows(listed.id => { title1: "Operations Manager" },
               stranger.id => { title1: "Sneaky" },
               0 => { title1: "No one" })

    assert_redirected_to edit_return_path
    assert_equal "1 badge updated.", flash[:success]
    assert_nil Bmid.find_for_person_year(stranger.id, YEAR)
  end

  test "a save with no rows writes nothing and says so" do
    badge(@admin, title1: "Shift Lead")

    assert_no_difference "Bmid.count" do
      patch bmid_manage_update_path(year: YEAR, mode: "edit")
    end

    assert_redirected_to bmid_manage_path(year: YEAR, filter: BmidManagement::DEFAULT_FILTER,
                                          mode: "edit")
    assert_equal "No changes were submitted, so nothing was saved.", flash[:info]
    assert_equal "Shift Lead", saved_badge(@admin).title1
  end

  test "a bulk save is refused without the admin or edit BMIDs role" do
    badge(@admin, title1: "Shift Lead")
    sign_in_as(@outsider)

    patch_rows(@admin.id => { title1: "Operations Manager" })

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
    assert_equal "Shift Lead", saved_badge(@admin).title1
  end

  # The write half of the recorded Role::VC deviation (PRD section 2): a VC may
  # not read this listing, and must certainly not save it.
  test "a bulk save is refused for a VC" do
    badge(@admin, title1: "Shift Lead")
    ensure_role(Role::VC, "VC")
    grant_role(@outsider, Role::VC)
    sign_in_as(@outsider)

    patch_rows(@admin.id => { title1: "Operations Manager" })

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
    assert_equal "Shift Lead", saved_badge(@admin).title1
  end

  # "Who changed my title?" is a real question, and upstream answers it.
  test "a bulk save is written to the action log" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    ActionLog.delete_all

    patch_rows(holder.id => { title1: "Operations Manager" })

    logged = ActionLog.where(event: "bmid-update", target_person_id: holder.id)
    assert_equal 1, logged.count
    assert_equal ["Shift Lead", "Operations Manager"], logged.first.data["title1"]
  end

  # --- the SAP write-through ------------------------------------------------

  test "changing the SAP date writes through to the person's access documents" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    pass = ticket_for(holder, access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    patch_rows(holder.id => { title1: "Shift Lead", admission_date: "#{YEAR}-08-12" })

    assert_redirected_to edit_return_path
    assert_equal Date.new(YEAR, 8, 12), pass.reload.access_date.to_date
    assert_not pass.access_any_time
  end

  test "an any-time SAP choice writes through to the person's access documents" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    pass = ticket_for(holder, access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    patch_rows(holder.id => { admission_date: AccessDocument::ADMISSION_ANY })

    assert pass.reload.access_any_time
    assert_nil pass.access_date
  end

  # THE load-bearing test of this page. Bmid#after_save pushes access_date out
  # to the person's access documents, so a badge saved without its SAP loaded
  # would wipe an arrival date no one touched.
  test "a title-only save leaves an existing SAP date exactly where it was" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    arrival = Time.zone.local(YEAR, 8, 12, 12, 0, 0)
    pass = ticket_for(holder, access_date: arrival)

    patch_rows(holder.id => { title1: "Operations Manager" })

    assert_redirected_to edit_return_path
    assert_equal "Operations Manager", saved_badge(holder).title1
    assert_equal arrival.to_date, pass.reload.access_date.to_date
  end

  # A hand-made value would otherwise be written straight through: the badge
  # stores it, the write-back hands it to a save that skips validation, and the
  # database casts it to NULL -- erasing an arrival date while the page reports
  # a successful save.
  test "an unparseable SAP date is refused and the access document is left alone" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    arrival = Time.zone.local(YEAR, 8, 20, 12, 0, 0)
    pass = ticket_for(holder, access_date: arrival)

    patch_rows(holder.id => { admission_date: "not-a-date" })

    assert_response :unprocessable_entity
    assert_equal arrival.to_date, pass.reload.access_date.to_date
    assert_match "The SAP date must be a date", response.body
  end

  # The grid disables the SAP control on these rows, so a value arriving anyway
  # did not come from the page.
  test "a SAP date is ignored for a badge whose pass cannot be edited" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    ticket_for(holder, status: AccessDocument::SUBMITTED,
                       access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    banked = ticket_for(holder, type: AccessDocument::STAFF_CREDENTIAL,
                                status: AccessDocument::BANKED)

    patch_rows(holder.id => { admission_date: "#{YEAR}-08-30" })

    assert_redirected_to edit_return_path
    assert_equal NOTHING_SUBMITTED, flash[:info]
    assert_nil banked.reload.access_date
  end

  # update_sap fires on every save, so a title-only edit would push the date the
  # grid happens to be displaying out over every other changeable pass the
  # person holds -- including the banked ones the page never showed.
  test "a title-only save leaves every other access document exactly where it was" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    arrival = Time.zone.local(YEAR, 8, 20, 12, 0, 0)
    claimed = ticket_for(holder, access_date: arrival)
    banked = ticket_for(holder, type: AccessDocument::STAFF_CREDENTIAL,
                                status: AccessDocument::BANKED)

    patch_rows(holder.id => { title1: "Operations Manager" })

    assert_redirected_to edit_return_path
    assert_nil banked.reload.access_date,
               "a badge edit that never touched the SAP date must not write one"
    assert_equal arrival.to_date, claimed.reload.access_date.to_date
  end

  test "changing the SAP date still reaches every changeable access document" do
    holder = @admin
    badge(holder, title1: "Shift Lead")
    claimed = ticket_for(holder, access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))
    banked = ticket_for(holder, type: AccessDocument::STAFF_CREDENTIAL,
                                status: AccessDocument::BANKED)

    patch_rows(holder.id => { admission_date: "#{YEAR}-08-12" })

    assert_redirected_to edit_return_path
    assert_equal Date.new(YEAR, 8, 12), claimed.reload.access_date.to_date
    assert_equal Date.new(YEAR, 8, 12), banked.reload.access_date.to_date
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the filtered rows under the expected filename" do
    wanted = @admin
    badge(wanted, title1: "Shift Lead", team: "Gate", notes: "Two lines\nof notes")
    meal_for(wanted, event_week_meals: true)
    provision_for(wanted)
    ticket_for(wanted, access_date: Time.zone.local(YEAR, 8, 20, 12, 0, 0))

    badge(person(:retired_ranger), title1: "Green Dot")

    get bmid_manage_path(format: :csv, title: "Shift Lead")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="bmids-#{YEAR}-special.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    # The UI calls it a SAP, but the export keys are upstream's and downstream
    # sheets are built on them: the column stays wap_status.
    assert_equal "callsign,title1,title2,title3,meals,showers,mvr,team,notes,wap_status,access_date",
                 lines.first
    assert_match wanted.callsign, response.body
    assert_not_includes response.body, person(:retired_ranger).callsign
    assert_match "Event", response.body
    assert_match "#{YEAR}-08-20", response.body
  end

  test "the csv export says so when there is no SAP and no access date" do
    badge(@admin, title1: "Shift Lead")

    get bmid_manage_path(format: :csv)

    assert_response :success
    row = response.body.split("\n").second
    assert_match "missing", row
    assert_match "unspecified", row
    assert_match "none", row
  end

  private

  def badge(holder, year: YEAR, status: Bmid::IN_PREP, **attributes)
    Bmid.create!(person: holder, year:, status:, **attributes)
  end

  # A badge on a person renamed for the test, so a sort assertion can read as
  # the order it expects.
  def badge_for_callsign(callsign, **attributes)
    holder = unused_person
    holder.update_columns(callsign:, callsign_normalized: callsign.downcase)
    @people_by_callsign ||= {}
    @people_by_callsign[callsign] = holder
    badge(holder, **attributes)
    callsign
  end

  def person_named(callsign)
    @people_by_callsign.fetch(callsign)
  end

  SORT_FIXTURES = %i[active_ranger retired_ranger auditor_ranger alpha_ranger
                     prospective_ranger bonked_ranger].freeze

  def unused_person
    @used_people ||= []
    name = SORT_FIXTURES[@used_people.size] or raise "out of sort fixtures"
    @used_people << name
    person(name)
  end

  # A bulk save of one or more rows, keyed by person id exactly as the edit grid
  # names its fields.
  def patch_rows(rows, query = {})
    patch bmid_manage_update_path({ year: YEAR, mode: "edit" }.merge(query)), params: { bmids: rows }
  end

  # Where a bulk save lands: back on the same Edit Mode view it came from.
  def edit_return_path(query = {})
    bmid_manage_path({ year: YEAR, filter: BmidManagement::DEFAULT_FILTER, mode: "edit" }.merge(query))
  end

  def saved_badge(holder, year: YEAR)
    Bmid.find_for_person_year(holder.id, year)
  end

  def ticket_for(holder, type: AccessDocument::SAP, status: AccessDocument::CLAIMED, **attributes)
    AccessDocument.create!(person: holder, type:, status:, source_year: YEAR,
                           delivery_method: AccessDocument::DELIVERY_NONE, **attributes)
  end

  # A wet spot pass: the least noisy stand-in when the test is about showers.
  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, **attributes)
    Provision.create!(person: holder, type:, status:, source_year: YEAR,
                      expires_on: Date.new(YEAR + 3, 9, 1), **attributes)
  end

  def meal_for(holder, **attributes)
    provision_for(holder, type: Provision::MEALS, **attributes)
  end

  # The callsign heading each rendered row of the table.
  def rendered_callsigns
    css_select("tbody th").map { |cell| cell.text.strip }
  end
end
