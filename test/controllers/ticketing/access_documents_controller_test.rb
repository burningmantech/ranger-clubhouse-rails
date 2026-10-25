# frozen_string_literal: true

require "test_helper"

# Ticketing > Access Documents: the per-person summary with its filters, and the
# flat current-record list with its type/status filters and CSV export.
#
# Both actions read the whole access_document table and the shared fixtures belong
# to other suites, so every test starts from an empty table and builds exactly the
# documents it needs.
class Ticketing::AccessDocumentsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ReportCardTestHelper     # assert_report_card / card_answer / assert_no_card_question
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026

  # Noon keeps the arrival date on the same calendar day whichever way a zone
  # conversion leans. 2026-08-10 is a Monday.
  ARRIVAL = "Mon Aug 10"

  # Spelled once: the test that expects the legend gone would keep passing
  # against a question that had merely been reworded.
  LEGEND_QUESTION = "What do the colors and icons mean?"

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @ticketing = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_ACCESS_DOCS, "Edit Access Documents")
    grant_role(@admin, Role::ADMIN)
    grant_role(@ticketing, Role::EDIT_ACCESS_DOCS)

    AccessDocument.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look --------------------------------------------------------

  test "the summary renders for an admin" do
    document(@admin, AccessDocument::SPT)

    get ticketing_access_documents_path

    assert_response :success
    assert_match "Showing 1 of 1 person", response.body
    assert_select "a[href=?]", person_tickets_provisions_path(@admin), text: @admin.callsign
  end

  test "the records page renders for an admin" do
    spt = document(@admin, AccessDocument::SPT)

    get ticketing_access_documents_records_path

    assert_response :success
    assert_equal [spt.display_ref], rendered_refs
    assert_select "a[href=?]", person_path(@admin), text: @admin.callsign
  end

  test "the summary renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    document(@ticketing, AccessDocument::SPT)

    get ticketing_access_documents_path

    assert_response :success
    assert_match "Showing 1 of 1 person", response.body
  end

  test "the records page renders with only the edit access documents role" do
    sign_in_as(@ticketing)
    spt = document(@ticketing, AccessDocument::SPT)

    get ticketing_access_documents_records_path

    assert_response :success
    assert_equal [spt.display_ref], rendered_refs
  end

  test "the summary is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_access_documents_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing records.", flash[:error]
  end

  test "the records page is refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_access_documents_records_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to view ticketing records.", flash[:error]
  end

  # --- records filters ------------------------------------------------------

  test "the type filter narrows the records to that type" do
    spt = document(@admin, AccessDocument::SPT)
    gift = document(@admin, AccessDocument::GIFT, name: "Gift Recipient")
    document(@admin, AccessDocument::VEHICLE_PASS_SP)

    get ticketing_access_documents_records_path(type: AccessDocument::GIFT)

    assert_response :success
    assert_equal [gift.display_ref], rendered_refs
    assert_not_includes rendered_refs, spt.display_ref
    # Y stays the whole current set so the filters visibly narrow X against it.
    assert_match "Showing 1 of 3 access documents", response.body
  end

  test "the status filter narrows the records to that status" do
    qualified = document(@admin, AccessDocument::SPT)
    banked = document(@admin, AccessDocument::SPT, status: AccessDocument::BANKED)
    claimed = document(@admin, AccessDocument::SPT, status: AccessDocument::CLAIMED)

    get ticketing_access_documents_records_path(status: AccessDocument::BANKED)

    assert_response :success
    assert_equal [banked.display_ref], rendered_refs
    assert_not_includes rendered_refs, qualified.display_ref
    assert_not_includes rendered_refs, claimed.display_ref
    assert_match "Showing 1 of 3 access documents", response.body
  end

  test "the type and status filters narrow together" do
    document(@admin, AccessDocument::SPT, status: AccessDocument::BANKED)
    document(@admin, AccessDocument::GIFT, status: AccessDocument::CLAIMED, name: "Gift Recipient")
    wanted = document(@admin, AccessDocument::GIFT, status: AccessDocument::BANKED, name: "Gift Recipient")

    get ticketing_access_documents_records_path(type: AccessDocument::GIFT, status: AccessDocument::BANKED)

    assert_response :success
    assert_equal [wanted.display_ref], rendered_refs
  end

  # The legend samples are rendered through the same partials as the rows, so
  # this also guards against them drifting apart. The legend is the last answer
  # in the page's About This Report card.
  test "the summary explains every tint and icon it uses" do
    document(@admin, AccessDocument::SPT, status: AccessDocument::CLAIMED)

    get ticketing_access_documents_path

    assert_response :success
    assert_report_card
    legend = card_answer(LEGEND_QUESTION)
    %w[Claimed Banked Submitted Qualified Missing].each do |encoding|
      assert_includes legend, encoding, "legend does not explain #{encoding}"
    end
    # The legend is folded away, so the row's badge names its status to a
    # pointer as well as to a screen reader.
    assert_select "tbody span[title='#{AccessDocument::CLAIMED}'] span.sr-only",
                  text: "(#{AccessDocument::CLAIMED})"
  end

  # A legend with no rows to read it against is noise; the rest of the card is
  # reference and stays.
  test "the summary card drops the legend when no one is listed" do
    get ticketing_access_documents_path

    assert_response :success
    assert_not_empty card_answer("Who is listed?")
    assert_no_card_question LEGEND_QUESTION
  end

  # A hand-edited URL must not be able to empty the page or park a bogus label
  # in the filter bar, so an unknown value falls back to showing everything.
  test "an unknown type or status falls back to no filter" do
    spt = document(@admin, AccessDocument::SPT)
    gift = document(@admin, AccessDocument::GIFT, name: "Gift Recipient")

    get ticketing_access_documents_records_path(type: "bogus", status: "bogus")

    assert_response :success
    assert_equal [spt.display_ref, gift.display_ref].sort, rendered_refs.sort
    assert_match "Showing 2 of 2 access documents", response.body
  end

  # Upstream's blank-status default keeps turned_down; this page drops it along
  # with the three spent statuses.
  test "the default records view keeps every current status and drops the spent ones" do
    current = AccessDocument::CURRENT_STATUSES.to_h do |status|
      [status, document(@admin, AccessDocument::SPT, status:)]
    end
    spent = [AccessDocument::TURNED_DOWN, AccessDocument::USED,
             AccessDocument::CANCELLED, AccessDocument::EXPIRED].to_h do |status|
      [status, document(@admin, AccessDocument::SPT, status:)]
    end

    get ticketing_access_documents_records_path

    assert_response :success

    refs = rendered_refs
    current.each do |status, doc|
      assert_includes refs, doc.display_ref, "#{status} should be listed by default"
    end
    spent.each do |status, doc|
      assert_not_includes refs, doc.display_ref, "#{status} should not be listed by default"
    end

    assert_equal 4, refs.size
    assert_match "Showing 4 of 4 access documents", response.body
  end

  # --- CSV export -----------------------------------------------------------

  test "the csv export returns the filtered rows under the expected filename" do
    sapso = document(@admin, AccessDocument::SAPSO, status: AccessDocument::CLAIMED,
                     name: "Significant Other", access_date: Time.zone.local(YEAR, 8, 10, 12, 0, 0))
    spt = document(@admin, AccessDocument::SPT)

    get ticketing_access_documents_records_path(format: :csv, type: AccessDocument::SAPSO)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match %(filename="#{YEAR}-access-documents.csv"), response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_equal "RAD,Person,Type,Arrival,S.O. Name,Source Year,Expires,Comments", lines.first
    assert_equal 2, lines.size, "only the filtered row belongs in the export"
    assert_equal "#{sapso.display_ref},#{@admin.callsign},SO SAP,#{ARRIVAL},Significant Other,#{YEAR},#{YEAR},",
                 lines.second
    assert_not_includes response.body, spt.display_ref
  end

  test "the csv export drops the spent statuses the table drops" do
    banked = document(@admin, AccessDocument::SPT, status: AccessDocument::BANKED)
    used = document(@admin, AccessDocument::SPT, status: AccessDocument::USED)

    get ticketing_access_documents_records_path(format: :csv)

    assert_response :success

    refs = response.body.split("\n").drop(1).map { |line| line.split(",").first }
    assert_equal [banked.display_ref], refs
    assert_not_includes refs, used.display_ref
  end

  # The table and the CSV share one arrival rule, so the on-screen rendering of
  # each of its four cases is pinned here alongside the export's.
  test "the records table renders every arrival case" do
    document(@admin, AccessDocument::STAFF_CREDENTIAL, access_date: Time.zone.local(YEAR, 8, 10, 12))
    document(@admin, AccessDocument::SAP, access_any_time: true)
    document(@admin, AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::BANKED)
    document(@admin, AccessDocument::VEHICLE_PASS_SP)

    get ticketing_access_documents_records_path

    assert_response :success

    # RAD heads each row as a th, so the tds are Person, Type, Status, Arrival.
    arrivals = css_select("tbody tr").map { |row| row.css("td")[3].text.squish }

    assert_includes arrivals, ARRIVAL
    assert_includes arrivals, "Anytime"
    assert_includes arrivals, "Missing"
    assert_includes arrivals, "—"
    # Missing is never conveyed by color alone.
    assert_select "tbody strong.text-error", text: "Missing"
  end

  # The arrival column stays blank for the types that never carry an access
  # date, so the spreadsheet never mixes dates with on-screen placeholders.
  test "the csv export leaves arrival and s.o. name blank for a vehicle pass" do
    pass = document(@admin, AccessDocument::VEHICLE_PASS_SP)

    get ticketing_access_documents_records_path(format: :csv)

    assert_response :success
    assert_equal "#{pass.display_ref},#{@admin.callsign},Vehicle Pass (Special Price),,,#{YEAR},#{YEAR},",
                 response.body.split("\n").second
  end

  # --- summary filters ------------------------------------------------------

  test "the status filter keeps people holding a document in that status" do
    document(@admin, AccessDocument::SPT)
    document(@ticketing, AccessDocument::SPT, status: AccessDocument::BANKED)

    get ticketing_access_documents_path(status: AccessDocument::BANKED)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
    assert_match "Showing 1 of 2 people", response.body
    # Only the statuses the page holds are offered, alphabetical like the
    # records page, each counting the people who hold one.
    assert_equal %w[all banked qualified],
                 css_select("select[name=status] option").map { |option| option["value"] }
    assert_select "select[name=status] option[value=banked]", text: "Banked (1)"
  end

  test "the ticket type filter keeps people holding that ticket" do
    document(@admin, AccessDocument::SPT)
    document(@admin, AccessDocument::SPT)
    document(@ticketing, AccessDocument::GIFT, name: "Gift Recipient")

    get ticketing_access_documents_path(type: AccessDocument::GIFT)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
    # Only the tickets the page holds, in the page's order, counting people:
    # two Special Price Tickets in one hand are one person.
    assert_equal ["all", AccessDocument::SPT, AccessDocument::GIFT],
                 css_select("select[name=type] option").map { |option| option["value"] }
    assert_select "select[name=type] option[value=?]", AccessDocument::SPT, text: "Special Price Ticket (1)"
  end

  # "Banked Gift Ticket" means one document that is both, not a banked
  # something beside a Gift Ticket.
  test "the status and ticket type filters must match the same document" do
    document(@admin, AccessDocument::SPT, status: AccessDocument::BANKED)
    document(@admin, AccessDocument::GIFT, name: "Gift Recipient")
    document(@ticketing, AccessDocument::GIFT, status: AccessDocument::BANKED, name: "Gift Recipient")

    get ticketing_access_documents_path(status: AccessDocument::BANKED, type: AccessDocument::GIFT)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  # A count promises the roster its choice delivers under the other active
  # filters, so the numbers shrink as filters stack, while a choice the page
  # holds stays offered at (0) rather than vanishing. Status and Ticket Type
  # count through the same-document rule: under "banked", a Gift Ticket
  # counts only for someone whose banked document is the Gift Ticket.
  test "the select counts shrink with the other filters" do
    document(@admin, AccessDocument::SPT, status: AccessDocument::BANKED)
    document(@admin, AccessDocument::GIFT, name: "Gift Recipient")
    document(@ticketing, AccessDocument::GIFT, status: AccessDocument::BANKED, name: "Gift Recipient")

    get ticketing_access_documents_path(status: AccessDocument::BANKED)

    assert_response :success
    # Two people hold a Gift Ticket; one holds a banked one.
    assert_select "select[name=type] option[value=?]", AccessDocument::GIFT, text: "Gift Ticket (1)"
    # A select never narrows itself: Qualified is counted with no status applied.
    assert_select "select[name=status] option[value=qualified]", text: "Qualified (1)"
    assert_select "select[name=person_status] option[value=?]", @admin.status, text: "#{@admin.status} (1)"

    get ticketing_access_documents_path(status: AccessDocument::BANKED, person_status: @admin.status)

    assert_response :success
    assert_select "select[name=type] option[value=?]", AccessDocument::GIFT, text: "Gift Ticket (0)"
    assert_select "select[name=type] option[value=?]", AccessDocument::SPT, text: "Special Price Ticket (1)"
  end

  test "the person status filter keeps people in that status" do
    document(@admin, AccessDocument::SPT)
    document(@ticketing, AccessDocument::SPT)

    get ticketing_access_documents_path(person_status: @ticketing.status)

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
    # The select offers only the statuses on the page, each with its count,
    # and prints them as stored.
    assert_select "select[name=person_status] option[value=?]", @admin.status, text: "#{@admin.status} (1)"
    assert_select "select[name=person_status] option[value=?]", Person::RETIRED, count: 0
  end

  test "the arrival filter keeps the missing or the anytime arrivals" do
    document(@admin, AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::CLAIMED)
    document(@ticketing, AccessDocument::SAP, access_any_time: true)

    get ticketing_access_documents_path(arrival: "missing")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns

    get ticketing_access_documents_path(arrival: "anytime")

    assert_response :success
    assert_equal [@ticketing.callsign], rendered_callsigns
  end

  # 2026-08-10 is a Monday, so the 12th is a Wednesday.
  test "the arrival filter offers each found day with its count and keeps that day" do
    document(@admin, AccessDocument::STAFF_CREDENTIAL, access_date: Time.zone.local(YEAR, 8, 12, 12))
    document(@ticketing, AccessDocument::SAP, access_date: Time.zone.local(YEAR, 8, 10, 12))
    document(@outsider, AccessDocument::STAFF_CREDENTIAL)

    get ticketing_access_documents_path(arrival: "#{YEAR}-08-12")

    assert_response :success
    assert_equal [@admin.callsign], rendered_callsigns
    # Only the choices the page holds are offered -- nobody arrives Anytime
    # here -- Missing first, then the found days in date order, keyed by ISO
    # day, each with its count and spelled the way the column spells them.
    assert_equal ["all", "missing", "#{YEAR}-08-10", "#{YEAR}-08-12"],
                 css_select("select[name=arrival] option").map { |option| option["value"] }
    assert_select "select[name=arrival] option[value=missing]", text: "Missing (1)"
    assert_select "select[name=arrival] option[value=?]", "#{YEAR}-08-12", text: "Wed Aug 12 (1)"
    # The chip names the day without the count.
    assert_select "a[aria-label=?]", "Remove filter: Arrival: Wed Aug 12"
  end

  # Both kinds of Weird Stuff count: the row's own note ("2 tickets") and a
  # per-document problem from the lib (a SAPSO with no access date).
  test "the issues filter keeps people with something in Weird Stuff" do
    document(@admin, AccessDocument::SPT)
    document(@admin, AccessDocument::SPT)
    document(@ticketing, AccessDocument::SAPSO, name: "Significant Other")
    document(@outsider, AccessDocument::SPT)

    get ticketing_access_documents_path(issues: "1")

    assert_response :success
    assert_equal [@admin.callsign, @ticketing.callsign].sort, rendered_callsigns.sort
    assert_match "Showing 2 of 3 people", response.body
  end

  test "an unknown summary filter value falls back to no filter" do
    document(@admin, AccessDocument::SPT)
    document(@ticketing, AccessDocument::SPT)

    get ticketing_access_documents_path(status: "bogus", type: "bogus", person_status: "bogus",
                                        arrival: "bogus", issues: "bogus")

    assert_response :success
    assert_equal 2, rendered_callsigns.size
    assert_match "Showing 2 of 2 people", response.body
    assert_select "#access-document-summary-filters a[aria-label^='Remove filter']", count: 0
  end

  test "summary filters that match no one say so" do
    document(@admin, AccessDocument::SPT)

    get ticketing_access_documents_path(status: AccessDocument::BANKED)

    assert_response :success
    assert_match "No one matched those filters", response.body
    assert_select "tbody", count: 0
    # The card describes the page, not the filtered view, so its legend stays.
    assert_not_empty card_answer(LEGEND_QUESTION)
  end

  private

  def document(holder, type, status: AccessDocument::QUALIFIED, **attributes)
    AccessDocument.create!(
      person: holder,
      type:,
      status:,
      source_year: YEAR,
      delivery_method: AccessDocument::DELIVERY_NONE,
      **attributes
    )
  end

  # The RAD reference heading each rendered row of the records table.
  def rendered_refs
    css_select("tbody th").map { |cell| cell.text.strip }
  end

  # The callsign heading each rendered row of the summary table.
  def rendered_callsigns
    css_select("tbody th a").map { |link| link.text.strip }
  end
end
