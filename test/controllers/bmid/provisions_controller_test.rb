# frozen_string_literal: true

require "test_helper"

# BMID > Manage Badges: the provision dialogs the Edit Mode grid opens from its
# meals and showers cells.
#
# Everything here is about one person's provisions and the two cells that
# describe them, so the fixtures' provisions are cleared and each test builds
# exactly the ones it needs.
class Bmid::ProvisionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    @other = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    Bmid.delete_all
    Provision.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may open one ----------------------------------------------------

  test "the dialog opens for an admin" do
    get new_bmid_provision_path(person_id: @other.id, type: Provision::WET_SPOT, year: YEAR),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal dialog#bmid-provision-modal"
  end

  test "the dialog opens with only the edit BMIDs role" do
    sign_in_as(@badger)

    get new_bmid_provision_path(person_id: @other.id, type: Provision::MEALS, year: YEAR)

    assert_response :success
    assert_select "dialog#bmid-provision-modal"
  end

  test "the dialog is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    get new_bmid_provision_path(person_id: @other.id, type: Provision::MEALS, year: YEAR)

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  test "a save is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    assert_no_difference "Provision.count" do
      post bmid_provisions_path(person_id: @other.id, year: YEAR),
           params: { provision: new_provision_params }
    end

    assert_redirected_to me_root_path
  end

  # --- the list step -------------------------------------------------------

  test "the cell action lists every usable provision of its type" do
    # The shape a single-record dialog got wrong: an earned pass that was
    # banked, pulled back into play because the person also holds an allocated
    # one. build_package unions both into the cell's label, so an admin
    # correcting that label has to be able to reach either record.
    banked = provision_for(@other, type: Provision::MEALS, status: Provision::BANKED, pre_event_meals: true)
    allocated = provision_for(@other, type: Provision::MEALS, is_allocated: true, event_week_meals: true)

    get bmid_provisions_path(cell_context(type: Provision::MEALS))

    assert_response :success
    assert_select "dialog#bmid-provision-modal"
    [banked, allocated].each do |provision|
      assert_select "a[href=?]", edit_bmid_provision_path(provision, cell_context), 1
     end
    # Enough of each row to tell the two apart before picking one.
    assert_match "banked", response.body
    assert_match "Allocated", response.body
  end

  test "the list leaves out the other cell's provisions" do
    meal = provision_for(@other, type: Provision::MEALS, event_week_meals: true)
    shower = provision_for(@other)

    get bmid_provisions_path(cell_context(type: Provision::MEALS))

    assert_response :success
    assert_select "a[href=?]", edit_bmid_provision_path(meal, cell_context), 1
    assert_select "a[href=?]", edit_bmid_provision_path(shower, cell_context), 0
  end

  test "the list offers to add another provision of the same type" do
    provision_for(@other, type: Provision::MEALS, event_week_meals: true)

    get bmid_provisions_path(cell_context(type: Provision::MEALS))

    assert_response :success
    # Holding one is exactly when a second becomes unreachable without this.
    assert_select "a[href=?]", new_bmid_provision_path(cell_context(type: Provision::MEALS)), 1
  end

  test "the list of a person holding none says so and still offers Add" do
    get bmid_provisions_path(cell_context(type: Provision::WET_SPOT))

    assert_response :success
    assert_select ".empty-state"
    assert_select "a[href=?]", new_bmid_provision_path(cell_context(type: Provision::WET_SPOT)), 1
  end

  test "the list leaves out provisions no one can use" do
    spent = provision_for(@other, status: Provision::EXPIRED)

    get bmid_provisions_path(cell_context(type: Provision::WET_SPOT))

    assert_response :success
    assert_select "a[href=?]", edit_bmid_provision_path(spent, cell_context), 0
  end

  test "the list shows only the row's own person's provisions" do
    theirs = provision_for(@admin)

    get bmid_provisions_path(cell_context(type: Provision::WET_SPOT))

    assert_response :success
    assert_select "a[href=?]", edit_bmid_provision_path(theirs, cell_context), 0
    assert_no_match theirs.display_ref, response.body
  end

  test "the list cannot be opened without a person" do
    assert_raises_or_not_found do
      get bmid_provisions_path(type: Provision::MEALS, year: YEAR)
    end
  end

  test "the list is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    get bmid_provisions_path(cell_context(type: Provision::MEALS))

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
  end

  # --- opening the form ----------------------------------------------------

  test "the new dialog is titled for the person and starts on the type it was opened for" do
    get new_bmid_provision_path(person_id: @other.id, type: Provision::WET_SPOT, year: YEAR)

    assert_response :success
    assert_match "Add a Provision", response.body
    assert_match @other.callsign, response.body
    assert_select "select[name=?] option[value=?][selected=selected]",
                  "provision[type]", Provision::WET_SPOT
    assert_select "form[action=?]",
                  bmid_provisions_path(person_id: @other.id, year: YEAR,
                                       filter: BmidManagement::DEFAULT_FILTER)
  end

  test "the edit dialog opens on the person's own provision" do
    shower = provision_for(@other)

    get edit_bmid_provision_path(shower, person_id: @other.id, year: YEAR)

    assert_response :success
    assert_select "dialog#bmid-provision-modal"
    assert_match shower.display_ref, response.body
    assert_select "form[action=?]",
                  bmid_provision_path(shower, person_id: @other.id, year: YEAR,
                                      filter: BmidManagement::DEFAULT_FILTER)
  end

  test "the dialog comes back as one frame, without the page around it" do
    get new_bmid_provision_path(person_id: @other.id, type: Provision::MEALS, year: YEAR),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    # Exactly one: a second frame with the same id is how a dialog ends up
    # appended instead of replaced.
    assert_select "turbo-frame#modal", 1
    assert_select "nav", count: 0
  end

  test "a dialog fetched outside the frame still carries only one frame" do
    # Right-click > Open in new tab, or a middle-click, on a cell action sends a
    # plain GET: these are real links. The page layout already holds the one
    # "modal" frame, so a dialog that brought its own would leave two elements
    # with the same id -- invalid, and getElementById would answer the wrong one.
    shower = provision_for(@other)

    [new_bmid_provision_path(cell_context(type: Provision::MEALS)),
     edit_bmid_provision_path(shower, cell_context),
     bmid_provisions_path(cell_context(type: Provision::WET_SPOT))].each do |url|
      get url

      assert_response :success
      assert_select "turbo-frame#modal", 1, "expected exactly one modal frame from #{url}"
      # The dialog is still there, and the modal controller opens it on connect.
      assert_select "dialog#bmid-provision-modal", 1
    end
  end

  test "the dialog cancels itself rather than leaving the page" do
    get new_bmid_provision_path(person_id: @other.id, type: Provision::MEALS, year: YEAR)

    assert_response :success
    # The modal closes in place; the page behind it is holding unsaved badge
    # edits that a navigation would throw away.
    assert_select "button[data-action=?]", "modal#hide"
    # Scoped to the dialog: the sidebar behind it legitimately links back to
    # the manage page (and carries ?year=, see year_scoped: in Menus::BMID).
    assert_select "dialog#bmid-provision-modal a[href=?]", bmid_manage_path(year: YEAR), count: 0
  end

  # --- a provision that belongs to somebody else ---------------------------

  test "a provision belonging to another person cannot be opened from a row" do
    theirs = provision_for(@admin)

    assert_raises_or_not_found do
      get edit_bmid_provision_path(theirs, person_id: @other.id, year: YEAR)
    end
  end

  test "a provision belonging to another person cannot be saved from a row" do
    theirs = provision_for(@admin, is_allocated: false)

    assert_raises_or_not_found do
      patch bmid_provision_path(theirs, person_id: @other.id, year: YEAR),
            params: { provision: { type: Provision::WET_SPOT, status: Provision::CLAIMED,
                                   source_year: YEAR, expires_on: YEAR + 3 } }
    end

    assert_equal Provision::AVAILABLE, theirs.reload.status
  end

  test "a provision belonging to another person cannot be deleted from a row" do
    theirs = provision_for(@admin)

    assert_raises_or_not_found do
      delete bmid_provision_path(theirs, person_id: @other.id, year: YEAR)
    end

    assert Provision.exists?(theirs.id)
  end

  test "a request with no person cannot reach a provision" do
    theirs = provision_for(@other)

    assert_raises_or_not_found do
      get edit_bmid_provision_path(theirs, year: YEAR)
    end
  end

  # --- creating ------------------------------------------------------------

  test "creating adds the provision to the row's own person" do
    assert_difference "Provision.count", 1 do
      post bmid_provisions_path(person_id: @other.id, year: YEAR),
           params: { provision: new_provision_params }, as: :turbo_stream
    end

    assert_response :success
    provision = Provision.sole
    assert_equal @other.id, provision.person_id
    assert_equal Provision::WET_SPOT, provision.type
  end

  test "creating closes the dialog and redraws both of the row's cells" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR),
         params: { provision: new_provision_params }, as: :turbo_stream

    assert_response :success
    assert_turbo_stream_targets "bmid-showers-cell-#{@other.id}", "bmid-meals-cell-#{@other.id}"
    assert_match %(<turbo-stream action="update" target="modal">), response.body
    # The redrawn showers cell says the person now has one.
    assert_match "Yes", showers_cell
    assert_match "Added Wet Spot Access for #{@other.callsign}.", response.body
  end

  test "creating meals redraws the meals cell with the periods it granted" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR),
         params: { provision: new_provision_params(type: Provision::MEALS,
                                                   event_week_meals: "1") },
         as: :turbo_stream

    assert_response :success
    assert_match "Event", meals_cell
  end

  test "an invalid provision keeps the dialog open and saves nothing" do
    assert_no_difference "Provision.count" do
      post bmid_provisions_path(person_id: @other.id, year: YEAR),
           params: { provision: new_provision_params(type: Provision::MEALS) },
           as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "dialog#bmid-provision-modal"
    assert_match "meal period", response.body
  end

  # --- updating ------------------------------------------------------------

  test "updating the row's provision redraws its cells" do
    shower = provision_for(@other)

    patch bmid_provision_path(shower, person_id: @other.id, year: YEAR),
          params: { provision: { type: Provision::WET_SPOT, status: Provision::CLAIMED,
                                 source_year: YEAR, expires_on: YEAR + 3 } },
          as: :turbo_stream

    assert_response :success
    assert_equal Provision::CLAIMED, shower.reload.status
    assert_turbo_stream_targets "bmid-showers-cell-#{@other.id}", "bmid-meals-cell-#{@other.id}"
    assert_match "Updated Wet Spot Access for #{@other.callsign}.", response.body
  end

  test "an invalid update keeps the dialog open and leaves the provision alone" do
    meals = provision_for(@other, type: Provision::MEALS, event_week_meals: true)

    patch bmid_provision_path(meals, person_id: @other.id, year: YEAR),
          params: { provision: { type: Provision::MEALS, status: Provision::AVAILABLE,
                                 source_year: YEAR, expires_on: YEAR + 3,
                                 pre_event_meals: "0", event_week_meals: "0",
                                 post_event_meals: "0" } },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "dialog#bmid-provision-modal"
    assert meals.reload.event_week_meals
  end

  # --- deleting ------------------------------------------------------------

  test "deleting the row's provision redraws its cells as empty" do
    shower = provision_for(@other)

    assert_difference "Provision.count", -1 do
      delete bmid_provision_path(shower, person_id: @other.id, year: YEAR), as: :turbo_stream
    end

    assert_response :success
    assert_turbo_stream_targets "bmid-showers-cell-#{@other.id}", "bmid-meals-cell-#{@other.id}"
    assert_match "—", showers_cell
    assert_match "Deleted Wet Spot Access for #{@other.callsign}.", response.body
  end

  # --- what a provision save must NOT do -----------------------------------

  test "a provision save leaves the badge's own columns alone" do
    badge = nil
    # Written an hour before the request, so any write during it moves
    # updated_at. Under a frozen clock a badge created and touched in the same
    # test would carry the same timestamp either way.
    travel_to(Time.current - 1.hour) do
      badge = Bmid.create!(person: @other, year: YEAR, status: Bmid::IN_PREP,
                           title1: "Shift Lead", meals: nil, showers: false)
    end
    written_at = badge.reload.updated_at

    post bmid_provisions_path(person_id: @other.id, year: YEAR),
         params: { provision: new_provision_params }, as: :turbo_stream
    assert_response :success

    badge.reload
    # The dead meals/showers columns are a printing vestige; the manage page
    # reads the provisions themselves, so nothing here may write them.
    assert_nil badge.meals
    assert_not badge.showers
    assert_equal "Shift Lead", badge.title1
    # Captured before the request: two reads of the same post-request row can
    # never disagree, so comparing them would guard nothing.
    assert_equal written_at.to_i, badge.updated_at.to_i
  end

  test "a provision save creates no badge for a person who has none" do
    assert_no_difference "Bmid.count" do
      post bmid_provisions_path(person_id: @other.id, year: YEAR),
           params: { provision: new_provision_params }, as: :turbo_stream
    end

    assert_response :success
    # The cells still redraw, from a stand-in row that is never saved.
    assert_turbo_stream_targets "bmid-showers-cell-#{@other.id}"
  end

  test "a redrawn cell opens the list rather than one of the provisions" do
    # Two usable meals provisions, the lower id banked. A cell button that
    # pointed at "the first" would send an admin correcting the union label
    # into the banked record, and would offer no way to add a second at all.
    banked = provision_for(@other, type: Provision::MEALS, status: Provision::BANKED,
                           pre_event_meals: true)
    allocated = provision_for(@other, type: Provision::MEALS, is_allocated: true,
                              event_week_meals: true)

    patch bmid_provision_path(allocated, person_id: @other.id, year: YEAR),
          params: { provision: { type: Provision::MEALS, status: Provision::AVAILABLE,
                                 source_year: YEAR, expires_on: YEAR + 3,
                                 event_week_meals: "1", is_allocated: "1" } },
          as: :turbo_stream

    assert_response :success
    cell = %(turbo-stream[target="bmid-meals-cell-#{@other.id}"] template)
    assert_select "#{cell} a[href=?]", bmid_provisions_path(cell_context(type: Provision::MEALS)), 1
    assert_select "#{cell} a[href=?]", edit_bmid_provision_path(banked, cell_context), 0
    assert_select "#{cell} a[href=?]", edit_bmid_provision_path(allocated, cell_context), 0
  end

  test "a redrawn cell carries no form field, so the badge row stays unchanged" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR),
         params: { provision: new_provision_params }, as: :turbo_stream

    assert_response :success
    cells = "#{showers_cell}#{meals_cell}"
    # An input inside the bulk-edit form is exactly what would mark the row as
    # edited -- the upstream defect this page deliberately does not repeat.
    assert_no_match(/<(input|select|textarea)\b/, cells)
    assert_match "turbo-frame=\"modal\"", cells
  end

  # --- without Turbo -------------------------------------------------------

  test "a plain save returns to the roster it was opened from" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR, filter: "alpha"),
         params: { provision: new_provision_params }

    assert_redirected_to bmid_manage_path(year: YEAR, filter: "alpha", mode: "edit")
    assert_equal "Added Wet Spot Access for #{@other.callsign}.", flash[:success]
  end

  test "an unknown category falls back to the default roster" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR, filter: "nonsense"),
         params: { provision: new_provision_params }

    assert_redirected_to bmid_manage_path(year: YEAR,
                                          filter: BmidManagement::DEFAULT_FILTER, mode: "edit")
  end

  # The same two cells appear on the single-badge editor, and a dialog opened
  # from there has to go back there rather than to the roster behind it. The
  # cell's buttons are ordinary links, so this path is reachable by a
  # middle-click even with Turbo working.
  test "a plain save from the badge editor returns to the badge" do
    origin = { person_id: @other.id, year: YEAR, filter: "alpha",
               from: Bmid::ManageHelper::BADGE_ORIGIN }

    post bmid_provisions_path(origin), params: { provision: new_provision_params }

    assert_redirected_to edit_bmid_badge_path(person_id: @other.id, year: YEAR, filter: "alpha")
  end

  # The origin has to survive every step of the dialog: by the time the form is
  # rendered the request belongs to this controller, which only knows where it
  # came from because the param rode along.
  test "the dialog carries the badge origin through its own links" do
    provision = provision_for(@other, type: Provision::MEALS, event_week_meals: true)
    origin = cell_context(from: Bmid::ManageHelper::BADGE_ORIGIN)

    get bmid_provisions_path(origin.merge(type: Provision::MEALS))

    assert_response :success
    assert_select "a[href=?]", edit_bmid_provision_path(provision, origin), 1
    assert_select "a[href=?]", new_bmid_provision_path(origin.merge(type: Provision::MEALS)), 1
  end

  # The cells the dialog redraws are the ones on the badge editor, so their
  # buttons have to keep the origin too -- otherwise the second dialog opened
  # from a redrawn cell would fall back to the roster.
  test "a redrawn cell keeps the badge origin" do
    post bmid_provisions_path(person_id: @other.id, year: YEAR,
                              from: Bmid::ManageHelper::BADGE_ORIGIN),
         params: { provision: new_provision_params },
         headers: { "Accept" => Mime[:turbo_stream].to_s }

    assert_response :success
    assert_match "from=#{Bmid::ManageHelper::BADGE_ORIGIN}", showers_cell
  end

  private

  def new_provision_params(type: Provision::WET_SPOT, **attributes)
    { type:, status: Provision::AVAILABLE, source_year: YEAR, expires_on: YEAR + 3,
      **attributes }
  end

  # What every link out of a cell carries: the row's person, and the roster the
  # dialog belongs to.
  def cell_context(person: @other, **extra)
    { person_id: person.id, year: YEAR, filter: BmidManagement::DEFAULT_FILTER, **extra }
  end

  def provision_for(holder, type: Provision::WET_SPOT, status: Provision::AVAILABLE, **attributes)
    Provision.create!(person: holder, type:, status:, source_year: YEAR,
                      expires_on: Date.new(YEAR + 3, 9, 1), **attributes)
  end

  # The rendered contents of one replaced cell, pulled out of the stream.
  def stream_target(dom_id)
    css_select(%(turbo-stream[target="#{dom_id}"] template)).first&.to_s.to_s
  end

  def showers_cell = stream_target("bmid-showers-cell-#{@other.id}")

  def meals_cell = stream_target("bmid-meals-cell-#{@other.id}")

  def assert_turbo_stream_targets(*dom_ids)
    dom_ids.each do |dom_id|
      assert_select %(turbo-stream[action="replace"][target="#{dom_id}"]), 1,
                    "expected the response to redraw ##{dom_id}"
    end
  end

  # RecordNotFound either becomes a 404 or propagates, depending on how the
  # environment is asked to handle it.
  def assert_raises_or_not_found
    yield
    assert_response :not_found
  rescue ActiveRecord::RecordNotFound
    # Expected when the exception propagates instead of being rescued.
  end
end
