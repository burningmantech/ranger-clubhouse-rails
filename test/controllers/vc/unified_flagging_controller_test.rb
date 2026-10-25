# frozen_string_literal: true

require "test_helper"

class Vc::UnifiedFlaggingControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include IntakeTestHelper
  include ReportCardTestHelper # assert_report_card
  include ActiveSupport::Testing::TimeHelpers

  DENY_MESSAGE = "Admin, Volunteer Coordinator, or Intake role required to view unified flagging."

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # Carries the full multi-year intake history in the fixtures, including a
    # 2026 personnel_rank of 4 -- the flag that quarantines a row.
    @flagged = person(:prospective_ranger)

    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @intake = person(:ranger_with_custom_gender)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::INTAKE, "Intake")
    ensure_role(Role::MENTOR, "Mentor")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@intake, Role::INTAKE)
    grant_role(@outsider, Role::MENTOR)

    Current.person = @admin

    # The roster is read from status history (upstream's rule), and
    # person_status has no fixture file -- so a subject has to be put into the
    # year's pipeline explicitly to appear on the page at all.
    place_in_pipeline(@flagged, 2026)
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- authorization -------------------------------------------------------

  test "admin can view the pipeline" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_response :success
    assert_match "2026 Unified Flagging", response.body
  end

  test "volunteer coordinator can view the pipeline" do
    sign_in_as(@vc)

    get vc_unified_flagging_path

    assert_response :success
  end

  test "intake can view the pipeline" do
    sign_in_as(@intake)

    get vc_unified_flagging_path

    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get vc_unified_flagging_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "detail frame requires the same roles" do
    sign_in_as(@outsider)

    get vc_unified_flagging_detail_path(@flagged)

    assert_redirected_to me_root_path
  end

  # --- the list ------------------------------------------------------------

  # The card holds the legend for the entries and nothing else, so a year with
  # people in the pipeline has it and a year with none does not.
  test "the card explains the ranks where there is a pipeline" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_report_card
    assert_match(/above average/, card_answer("What do the ranks mean?"))
    assert_match(/Select a name/, card_answer("How do I read someone’s history?"))
    assert_match(/most serious mark/, card_answer("What is the colored chip on an entry?"))
    # The lines carry no ranks or notes: both answers send the reader to the
    # pane, where the gray line that lists them is.
    assert_match(/Select a name: the gray line under it in the history/, card_answer("What do the ranks mean?"))
    assert_match(/Select a name for every other rank and note/,
                 card_answer("What is the colored chip on an entry?"))

    get vc_unified_flagging_path(year: 2012)

    assert_match "No Prospectives or Alphas were found for 2012", response.body
    assert_report_card count: 0
  end

  test "a personnel-flagged person is quarantined into their own group" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_response :success
    assert_match "Personnel Flag Raised", response.body
    assert_match @flagged.callsign, response.body
    assert_equal :personnel, group_for(@flagged)
  end

  test "the year selector re-scopes the list" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(year: 2025)

    assert_response :success
    assert_match "2025 Unified Flagging", response.body
    # 2025 predates the personnel flag, so the same person is no longer quarantined.
    assert_not_equal :personnel, Intake.retrieve_all_for_year(2025)
                                       .find { |row| row[:person].id == @flagged.id }&.dig(:group)
  end

  # The selector starts at 2010. A year before it is not one this page offers,
  # so it reads as the current year rather than a heading the selector cannot
  # show.
  test "a year before the selector's first reads as this year" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(year: 2005)

    assert_response :success
    assert_match "2026 Unified Flagging", response.body
  end

  test "detail frame renders one person's history" do
    sign_in_as(@admin)

    get vc_unified_flagging_detail_path(@flagged, year: 2026)

    assert_response :success
    assert_match "uf-frame-#{@flagged.id}", response.body
    # The person page's chrome must not come along for the ride.
    assert_no_match "<html", response.body
  end

  # Turbo drives links descending from a frame. Without target="_top" the note
  # form -- a full person-layout page with no matching frame id -- resolves to
  # nothing, and the writer gets turbo:frame-missing instead of the form.
  test "the pane's frame lets its links navigate the whole page" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(person: @flagged.id)

    assert_match(/<turbo-frame[^>]*id="uf-pane"[^>]*target="_top"/, response.body)
  end

  test "add-note links carry the viewed year so the note lands in it" do
    sign_in_as(@admin)

    get vc_unified_flagging_detail_path(@flagged, year: 2024)

    assert_response :success
    assert_match "year=2024", response.body
    assert_match "origin_year=2024", response.body
  end

  test "teams with nothing recorded fold into one line instead of empty sections" do
    sign_in_as(@admin)

    # alpha_ranger has no intake rows at all, so every team folds into the
    # single summary line rather than each rendering an empty block.
    get vc_unified_flagging_detail_path(person(:alpha_ranger), year: 2026)

    assert_response :success
    assert_match "No notes yet:", response.body
    assert_no_match(/No Personnel notes/, response.body)
  end

  # --- filtering ------------------------------------------------------------

  test "search matches a callsign and drops everyone else" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(q: @flagged.callsign)

    assert_response :success
    assert_match @flagged.callsign, response.body
    assert_no_match(/#{person(:alpha_ranger).callsign}/, response.body)
  end

  # Looking someone up by the handle you last knew them under is the reason
  # FKAs are kept at all.
  test "search also matches a former handle" do
    sign_in_as(@admin)
    PersonFka.create!(person: @flagged, fka: "Barnacle")

    get vc_unified_flagging_path(q: "barnacle")

    assert_response :success
    assert_match @flagged.callsign, response.body
  end

  test "the training filter keeps only that cohort" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(training: "none")

    assert_response :success
    # @flagged has no 2026 training sign-up, so it survives a "none" filter...
    assert_match @flagged.callsign, response.body

    get vc_unified_flagging_path(training: "trained")

    assert_response :success
    # ...and is dropped by "trained".
    assert_no_match(/#{@flagged.callsign}/, response.body)
  end

  test "filters that match no one say so instead of rendering an empty list" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(q: "nobodyisnamedthis")

    assert_response :success
    assert_match "matched those filters", response.body
  end

  test "a filter keeps the year it was applied on" do
    sign_in_as(@admin)
    place_in_pipeline(@flagged, 2025)

    get vc_unified_flagging_path(year: 2025, training: "none")

    assert_response :success
    assert_match "2025 Unified Flagging", response.body
    # The chip that drops the filter must not drop the year with it.
    assert_match "year=2025", response.body
  end


  # --- the row -------------------------------------------------------------

  # One colored chip names why the person is listed; every rank and note moves
  # to a gray line under the name, and the status loses its brackets.
  test "a row leads with the reason it is listed" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_select "#person-#{@flagged.id}" do
      assert_select ".badge", text: "Personnel flag"
      assert_select ".badge", text: /note ·/, count: 0
      assert_select ".badge", text: /trained/, count: 0
    end
    assert_no_match "&lt;#{@flagged.status}&gt;", response.body
    assert_select "details dt", text: "What is the colored chip on an entry?"
    # One warning for the page names them; the row no longer repeats it.
    assert_match "A Personnel flag is raised on #{@flagged.callsign}", response.body
    assert_select "#person-#{@flagged.id}", text: /Take no actions/, count: 0
  end

  # The line says what stands out -- a training exception, and when the last
  # note was written -- and nothing else: "Trained" is the expected state, and
  # the status and former handles wait in the pane.
  test "a line says what stands out and when the last note was written" do
    sign_in_as(@admin)
    latest = PersonIntakeNote.where(person: @flagged, is_log: false).maximum(:created_at)

    get vc_unified_flagging_path

    assert_select "li#person-#{@flagged.id}" do
      assert_select "a", text: /No training sign-up/
      assert_select "a", text: /Personnel #{latest.strftime("%b %-d, %Y")}/
      assert_select "a", text: /Trained/, count: 0
      assert_select "a", text: /#{@flagged.status}/, count: 0
    end
  end

  # --- the stat tiles ------------------------------------------------------

  # A tile counts the whole pipeline and is the control that narrows to its
  # group; the ring says which one is showing, and the chip undoes it.
  test "the stat tiles narrow the list to one section" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_select "a[href=?]", vc_unified_flagging_path(year: 2026, section: "personnel")
    assert_select "a.ring-primary", count: 0

    get vc_unified_flagging_path(section: "flagged")

    assert_response :success
    assert_no_match(/#{@flagged.callsign}/, response.body)
    assert_match "Section: Rank 3/4 or Bonk", response.body
    assert_select "a.ring-primary[href=?]", vc_unified_flagging_path(year: 2026, section: "flagged")
    assert_select "select[name=section] option[selected][value=flagged]"

    get vc_unified_flagging_path(section: "personnel")

    assert_match @flagged.callsign, response.body
  end

  # A stale bookmark or a typo reads as "every section", never as "no section".
  test "an unknown section value is ignored" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(section: "typo")

    assert_response :success
    assert_match @flagged.callsign, response.body
    assert_no_match "Section:", response.body
  end

  # --- the review pane -----------------------------------------------------

  # ?person= names the row whose history the pane shows. The row is marked,
  # brought into view, and its link carries the page's filters so selecting
  # someone does not drop them.
  test "selecting a name fills the review pane" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_select "aside .empty-state", text: /Select a name/
    assert_select "li#person-#{@flagged.id} a[href=?]", vc_unified_flagging_path(year: 2026, person: @flagged.id)
    assert_select "li[id^=person-] a[aria-current=true]", count: 0

    get vc_unified_flagging_path(person: @flagged.id, training: "none")

    assert_response :success
    assert_select "li#person-#{@flagged.id} a[aria-current=true][href=?]",
                  vc_unified_flagging_path(year: 2026, person: @flagged.id, training: "none")
    assert_select "aside turbo-frame#uf-pane [data-review-id=?]", @flagged.id.to_s do
      assert_select "a", text: @flagged.callsign
      assert_match(/Add Personnel Note/, response.body)
    end
  end

  # Only a person on the page can be selected: a stale link shows the empty
  # pane rather than a history the list disowns, a person the filters hide is
  # not selected either, and an array-shaped param does not crash the page.
  test "only a person on the page can be selected" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(person: 999_999)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_select "aside .empty-state", text: /Select a name/

    get vc_unified_flagging_path(section: "flagged", person: @flagged.id)

    assert_response :success
    assert_select "li[id^=person-] a[aria-current=true]", count: 0
    assert_match "matched those filters", response.body

    get vc_unified_flagging_path(person: ["1"])

    assert_response :success

    # A year with no pipeline has no workspace to select in.
    get vc_unified_flagging_path(year: 2012, person: @flagged.id)

    assert_response :success
    assert_select "aside.review-pane", count: 0
  end

  # Selecting a line loads only the pane's frame, which advances the URL; the
  # list stays put and review_pane_controller moves the selection. So the
  # frame's response is the pane alone -- no list, no layout -- rather than the
  # whole page for Turbo to throw away.
  test "a line loads only the pane" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(person: @flagged.id)

    assert_select "[data-controller=review-pane]" do
      assert_select "li#person-#{@flagged.id} a[data-turbo-frame=uf-pane][data-review-pane-target=line]" \
                    "[aria-controls=uf-pane][aria-current=true][data-review-id=?]", @flagged.id.to_s
      assert_select "aside.review-pane[data-review-pane-target=pane] " \
                    "turbo-frame#uf-pane[target=_top][data-turbo-action=advance] [data-review-id=?]", @flagged.id.to_s
    end

    get vc_unified_flagging_path(person: @flagged.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_response :success
    assert_select "turbo-frame#uf-pane [data-review-id=?]", @flagged.id.to_s
    assert_select "li[id^=person-]", count: 0
    assert_no_match "<html", response.body
  end

  # A frame load is not a visit to the page: the mega menu's Recent list reads
  # these rows, and every name the reader opened would bump it.
  test "opening a pane is not logged as a visit to the page" do
    sign_in_as(@admin)
    visits = PersonPageVisit.where(person_id: @admin.id, path: vc_unified_flagging_path)

    get vc_unified_flagging_path(person: @flagged.id), headers: { "Turbo-Frame" => "uf-pane" }

    assert_not visits.exists?, "the pane's frame load was logged as a page visit"

    get vc_unified_flagging_path

    assert visits.exists?, "the page itself is tracked, or the check above proves nothing"
  end

  # --- regressions from the 2026-10-14 review ---------------------------------

  # The pane's frame targets _top, so its Delete (a Turbo method link) and
  # every other link in it navigate the page; only the lines, outside it, load
  # into it. No frame may wrap it: Turbo hands a method link to the nearest
  # enclosing frame without a target, which captured the Delete as a frame
  # submission and threw the redirect's flash away.
  test "only the lines navigate inside the pane's frame" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(person: @flagged.id)

    assert_select "turbo-frame#uf-pane[target=_top] [data-turbo-method=delete]"
    assert_select "turbo-frame turbo-frame#uf-pane", count: 0
    assert_select "li#person-#{@flagged.id} a[data-turbo-frame=uf-pane]"
  end

  # Ruling R4 kept a tint on a flagged person's line when the per-row callout
  # went, and Layout C put the warning in the pane beside the note controls.
  test "a Personnel flag tints the line and warns in the pane" do
    sign_in_as(@admin)

    get vc_unified_flagging_path

    assert_select "li#person-#{@flagged.id} a.review-line-flagged"

    get vc_unified_flagging_path(person: @flagged.id)

    assert_select "aside.review-pane [role=alert]", text: /Take no actions on #{@flagged.callsign}/

    # 2025 predates the flag: the same person, selected, gets no warning.
    place_in_pipeline(@flagged, 2025)
    get vc_unified_flagging_path(year: 2025, person: @flagged.id)

    assert_select "aside.review-pane [data-review-id=?]", @flagged.id.to_s
    assert_select "aside.review-pane", text: /Take no actions/, count: 0
  end

  # The gray line lists the teams in Intake::TEAM_ORDER, Training before
  # Mentors; the history's sections under it name them in the same order.
  test "the pane's sections follow the gray line's team order" do
    sign_in_as(@admin)

    get vc_unified_flagging_path(person: @flagged.id)

    labels = Intake::TEAM_ORDER.map { |team| IntakeHelper::TEAM_META.dig(team, :label) }
    headings = css_select("aside.review-pane h4").map { |node| node.text.squish } & labels

    assert_includes headings, "Mentors", "the fixture person needs a Mentors section for the order to show"
    assert_equal labels & headings, headings
  end

  # created_at is nullable on person_intake_note. A team whose only note has no
  # timestamp has no latest date, and the line must pass it over rather than
  # compare it with the others' and take the page down.
  test "a note with no timestamp does not break the list" do
    sign_in_as(@admin)
    PersonIntakeNote.where(person_id: @flagged.id, type: "vc").update_all(created_at: nil)

    get vc_unified_flagging_path

    assert_response :success
    assert_select "li#person-#{@flagged.id}"
  end

  private

  def group_for(target)
    Intake.retrieve_all_for_year(2026).find { |row| row[:person].id == target.id }&.dig(:group)
  end
end
