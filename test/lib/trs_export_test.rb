# frozen_string_literal: true

require "test_helper"

# Exercises TrsExport, the logic behind Ticketing > TRS Export: the filter
# registry, the vendor CSV formats (which must stay byte-identical to the TRS
# import template), the TRS column/delivery/note rules, row building for the
# simple and combined filters, and the two commit operations.
#
# The shared access_document fixtures belong to other suites and this module
# reads the whole table, so every test starts from an empty one and builds
# exactly the documents it needs.
class TrsExportTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 7, 1, 12, 0, 0)
    Current.reset
    Current.person = person(:active_ranger)
    AccessDocument.delete_all

    @ranger = person(:ranger_with_custom_gender)
    @alpha = person(:alpha_ranger)
    @prospective = person(:prospective_ranger)
  end

  teardown do
    Current.reset
    travel_back
  end

  # --- helpers -------------------------------------------------------------

  # This suite is about live allocations: documents are claimed unless a test
  # says otherwise.
  def default_document_status = AccessDocument::CLAIMED

  def filter(slug)
    TrsExport.find_filter(slug)
  end

  def rows(slug)
    TrsExport.build_rows(filter(slug))[:rows]
  end

  def new_document(type, delivery_method)
    AccessDocument.new(type:, delivery_method:)
  end

  # --- filter registry -----------------------------------------------------

  test "the registry carries the sixteen upstream filters in their groups" do
    assert_equal 16, TrsExport::FILTERS.size
    assert_equal [nil, "Staff Credentials", "Special Price", "Setup Access Passes", "Other Tickets"],
                 TrsExport::FILTER_GROUPS.map(&:first)

    slugs = TrsExport::FILTER_GROUPS.flat_map { |_group, filters| filters.map(&:slug) }
    assert_equal %w[all
                    staff_credential staff_credential_vp vehicle_pass_gift
                    spt_vp special_price_ticket vehicle_pass_sp
                    work_access_pass_ranger work_access_pass_ranger_plus_so work_access_pass_so
                    work_access_pass_pnv work_access_pass_all
                    gift_ticket lsd_ticket lsd_vp vehicle_pass_lsd], slugs

    assert_equal %w[staff_credential_vp spt_vp lsd_vp],
                 TrsExport::FILTERS.values.select(&:combined?).map(&:slug)
    assert_not filter("all").exportable?
    assert filter("staff_credential").exportable?
  end

  # --- CSV formats ---------------------------------------------------------
  # The header rows are pinned byte-for-byte: the literal &amp;, the
  # out-of-order dates, the double space in "Setup Access Pass  8/15", and the
  # "Method of"/"Method Of" case difference all mirror the vendor template.

  test "the paid and gift ticket format header is byte-exact" do
    expected = "First Name,Last Name,Email,Question: Method Of Delivery:,Question: Nickname/Project:," \
               "Question: Notes:,Request: $250 Ticket,Request: $165 Vehicle Pass,Request: Gift Ticket," \
               "Request: Gift Vehicle Pass,Request: Transferrable $250 Ticket," \
               "Request: Transferrable $165 Vehicle Pass,Request: Transferrable Gift Ticket," \
               "Request: Transferrable Gift Vehicle Pass,Request: Transferrable $75 Vehicle Pass," \
               "Request: $75 Vehicle Pass"

    assert_equal expected, CsvExportConcern.build([TrsExport::PAID_AND_GIFT_TICKET_EXPORT_FORMAT.map(&:first)])
  end

  test "the unpaid format header is byte-exact" do
    sap_days = %w[8/26 8/27 8/28 8/29 8/8 8/9 8/10 8/11 8/12 8/13 8/14]
                 .map { |day| "Request: Setup Access Pass #{day} &amp; Later" }
    sap_days << "Request: Setup Access Pass  8/15 &amp; Later"
    sap_days += %w[8/16 8/17 8/18 8/19 8/20 8/21 8/22 8/23 8/24 8/25]
                  .map { |day| "Request: Setup Access Pass #{day} &amp; Later" }
    sc_days = %w[8/14 8/13 8/26 8/27 8/28 8/29 8/8 8/9 8/10 8/11 8/12 8/15 8/16 8/17 8/18 8/19 8/20 8/21 8/22 8/23 8/24]
                .map { |day| "Request: Staff Credential Pickup #{day} &amp; After" }

    expected = ["First Name", "Last Name", "Email", "Question: Method of Delivery:",
                "Question: Nickname/Project:", "Question: Notes:", "Request: Gift Vehicle Pass",
                *sap_days, "Request: Setup Access Pass - Anytime",
                *sc_days, "Request: Staff Credential Pickup Anytime",
                "Request: Staff Credential Pickup 8/25 &amp; After"].join(",")

    assert_equal expected, CsvExportConcern.build([TrsExport::UNPAID_EXPORT_FORMAT.map(&:first)])
  end

  test "the lsd format header is byte-exact" do
    expected = "First Name,Last Name,Email,Question: Method Of Delivery:,Question: Nickname/Project:," \
               "Question: Notes:,Shipping Address:: Country,Shipping Address:: Full Name," \
               "Shipping Address:: Address,Shipping Address:: Address Line 2,Shipping Address:: City," \
               "Shipping Address:: State,Shipping Address:: Zip,Shipping Address:: Phone," \
               "Request: $165 Vehicle Pass - Directed,Request: $550 Ticket - Directed," \
               "Request: $675 Ticket - Directed,Request: $775 Ticket - Directed," \
               "Request: $975 Ticket - Directed,Request: $1500 Ticket - Directed," \
               "Request: $3000 Ticket - Directed,Request: Non-Transferrable $550 Ticket"

    assert_equal expected, CsvExportConcern.build([TrsExport::LSD_EXPORT_FORMAT.map(&:first)])
  end

  test "each filter picks the upstream format" do
    %w[special_price_ticket spt_vp vehicle_pass_sp gift_ticket].each do |slug|
      assert_equal TrsExport::PAID_AND_GIFT_TICKET_EXPORT_FORMAT, TrsExport.export_format(filter(slug)), slug
    end
    %w[lsd_ticket lsd_vp vehicle_pass_lsd].each do |slug|
      assert_equal TrsExport::LSD_EXPORT_FORMAT, TrsExport.export_format(filter(slug)), slug
    end
    %w[staff_credential staff_credential_vp vehicle_pass_gift work_access_pass_ranger work_access_pass_so].each do |slug|
      assert_equal TrsExport::UNPAID_EXPORT_FORMAT, TrsExport.export_format(filter(slug)), slug
    end
  end

  # --- TRS column and date -------------------------------------------------

  test "dated types carry an access-date column suffix and note fragment" do
    dated = new_document(AccessDocument::STAFF_CREDENTIAL, AccessDocument::DELIVERY_NONE)
    dated.access_date = august(14)
    assert_equal ["sc_0814", " Fri 08/14"], TrsExport.trs_column_and_date(dated)

    single_digit = new_document(AccessDocument::SAP, AccessDocument::DELIVERY_NONE)
    single_digit.access_date = august(8)
    assert_equal ["sap_0808", " Sat 08/8"], TrsExport.trs_column_and_date(single_digit)

    anytime = new_document(AccessDocument::SAPSO, AccessDocument::DELIVERY_NONE)
    anytime.access_any_time = true
    # The missing leading space on "Anytime" is an upstream quirk, kept.
    assert_equal ["sap_anytime", "Anytime"], TrsExport.trs_column_and_date(anytime)

    unspecified = new_document(AccessDocument::STAFF_CREDENTIAL, AccessDocument::DELIVERY_NONE)
    assert_equal ["sc_unspecified", " UNSPECIFIED ACCESS DATE"], TrsExport.trs_column_and_date(unspecified)

    plain = new_document(AccessDocument::GIFT, AccessDocument::DELIVERY_NONE)
    assert_equal ["gift_ticket", ""], TrsExport.trs_column_and_date(plain)
  end

  # --- delivery ------------------------------------------------------------

  test "delivery strings follow the vendor CSV rules for every type" do
    {
      [AccessDocument::STAFF_CREDENTIAL, AccessDocument::DELIVERY_NONE] => TrsExport::CREDENTIAL_PICKUP,
      [AccessDocument::SAP, AccessDocument::DELIVERY_EMAIL] => TrsExport::PRINT_AT_HOME,
      [AccessDocument::SAPSO, AccessDocument::DELIVERY_NONE] => TrsExport::PRINT_AT_HOME,
      [AccessDocument::SPT, AccessDocument::DELIVERY_POSTAL] => TrsExport::USPS_STANDARD,
      [AccessDocument::SPT, AccessDocument::DELIVERY_PRIORITY] => TrsExport::USPS_PRIORITY,
      [AccessDocument::SPT, AccessDocument::DELIVERY_WILL_CALL] => TrsExport::WILL_CALL,
      [AccessDocument::SPT, AccessDocument::DELIVERY_NONE] => TrsExport::WILL_CALL,
      [AccessDocument::LSD, AccessDocument::DELIVERY_POSTAL] => TrsExport::USPS_STANDARD,
      [AccessDocument::VEHICLE_PASS_LSD, AccessDocument::DELIVERY_PRIORITY] => TrsExport::USPS_PRIORITY,
      [AccessDocument::VEHICLE_PASS_SP, AccessDocument::DELIVERY_WILL_CALL] => TrsExport::WILL_CALL,
      # Gift VPs never see the dead upstream Credential Pick Up branch: the
      # vendor CSV has always received USPS/UPS, and that behavior is kept.
      [AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::DELIVERY_POSTAL] => TrsExport::USPS_STANDARD_FOR_GIFT,
      [AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::DELIVERY_PRIORITY] => TrsExport::USPS_STANDARD_FOR_GIFT,
      [AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::DELIVERY_WILL_CALL] => TrsExport::UPS,
      [AccessDocument::VEHICLE_PASS_GIFT, AccessDocument::DELIVERY_NONE] => TrsExport::UPS,
      [AccessDocument::GIFT, AccessDocument::DELIVERY_POSTAL] => TrsExport::USPS_STANDARD_FOR_GIFT,
      [AccessDocument::GIFT, AccessDocument::DELIVERY_PRIORITY] => TrsExport::UPS,
      [AccessDocument::GIFT, AccessDocument::DELIVERY_WILL_CALL] => TrsExport::WILL_CALL
    }.each do |(type, delivery_method), expected|
      assert_equal expected, TrsExport.delivery_for(new_document(type, delivery_method)),
                   "#{type} via #{delivery_method}"
    end

    # A gift ticket with no usable method has no delivery string at all.
    assert_nil TrsExport.delivery_for(new_document(AccessDocument::GIFT, AccessDocument::DELIVERY_NONE))
  end

  # --- row building --------------------------------------------------------

  test "only claimed documents of living holders appear" do
    claimed = document(@ranger, type: AccessDocument::GIFT)
    document(@ranger, type: AccessDocument::GIFT, status: AccessDocument::QUALIFIED)
    document(person(:deceased_ranger), type: AccessDocument::GIFT)

    all_rows = rows("all")
    assert_equal [claimed.id], all_rows.flat_map { |row| row.documents.map(&:id) }
  end

  test "sap filters split holders by prospective and alpha status" do
    ranger_sap = document(@ranger, type: AccessDocument::SAP, access_any_time: true)
    ranger_so = document(@ranger, type: AccessDocument::SAPSO, access_any_time: true, name: "Plus One")
    alpha_sap = document(@alpha, type: AccessDocument::SAP, access_any_time: true)
    prospective_sap = document(@prospective, type: AccessDocument::SAP, access_any_time: true)

    ids = ->(slug) { rows(slug).flat_map { |row| row.documents.map(&:id) }.sort }

    assert_equal [ranger_sap.id], ids.call("work_access_pass_ranger")
    assert_equal [ranger_sap.id, ranger_so.id].sort, ids.call("work_access_pass_ranger_plus_so")
    assert_equal [ranger_so.id], ids.call("work_access_pass_so")
    assert_equal [alpha_sap.id, prospective_sap.id].sort, ids.call("work_access_pass_pnv")
    assert_equal [ranger_sap.id, ranger_so.id, alpha_sap.id, prospective_sap.id].sort,
                 ids.call("work_access_pass_all")
  end

  test "notes carry the TRS vocabulary, the reference, and the SO name" do
    document(@ranger, type: AccessDocument::SAPSO, access_date: august(14), name: "Plus One")

    row = rows("work_access_pass_so").sole
    assert_equal "SOWAP Fri 08/14 - #{row.documents.sole.display_ref} - for Plus One", row.note
    assert_equal({ "sap_0814" => 1 }, row.column_counts)
  end

  test "a combined filter bundles tickets and passes and skips incomplete pairs" do
    sc = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(14))
    vp = document(@ranger, type: AccessDocument::VEHICLE_PASS_GIFT)
    second_vp = document(@ranger, type: AccessDocument::VEHICLE_PASS_GIFT)
    document(@alpha, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(14)) # no VP: excluded

    row = rows("staff_credential_vp").sole
    assert_equal [sc.id, vp.id, second_vp.id], row.documents.map(&:id)
    assert_equal({ "sc_0814" => 1, "gift_vp" => 2 }, row.column_counts)
    assert_equal TrsExport::CREDENTIAL_PICKUP, row.delivery
    assert_equal "#{sc.id},#{vp.id},#{second_vp.id}", row.id_param
    assert_equal ["CRED Fri 08/14 - RAD-#{sc.id}", "GIFTVP - RAD-#{vp.id}", "GIFTVP - RAD-#{second_vp.id}"].join("+"),
                 row.note

    # Untouched request columns export as empty cells, never "0" -- the
    # combined-row counts hash defaults to 0 and must not leak into the CSV.
    cells = TrsExport.csv_rows(filter("staff_credential_vp"), [row]).last
    keys = TrsExport::UNPAID_EXPORT_FORMAT.map(&:last)
    assert_equal 1, cells[keys.index("sc_0814")]
    assert_equal 2, cells[keys.index("gift_vp")]
    assert_equal "", cells[keys.index("sap_0814")]
    assert_not_includes cells, 0
  end

  test "a non-credential combined row takes its delivery from the ticket" do
    document(@ranger, type: AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_POSTAL)
    document(@ranger, type: AccessDocument::VEHICLE_PASS_SP, delivery_method: AccessDocument::DELIVERY_WILL_CALL)

    assert_equal TrsExport::USPS_STANDARD, rows("spt_vp").sole.delivery
  end

  test "rows are ordered by holder callsign" do
    document(@ranger, type: AccessDocument::GIFT)   # CustomGender
    document(@alpha, type: AccessDocument::GIFT)    # AlphaTest...

    callsigns = rows("gift_ticket").map { |row| row.person.callsign }
    assert_equal callsigns.sort_by(&:downcase), callsigns
  end

  # --- errors --------------------------------------------------------------

  test "access date problems and missing delivery methods flag documents" do
    missing_date = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL)
    out_of_range = document(@ranger, type: AccessDocument::SAP, access_date: august(30))
    bare_spt = document(@ranger, type: AccessDocument::SPT)
    fine = document(@ranger, type: AccessDocument::GIFT)

    result = TrsExport.build_rows(filter("all"))
    errors = result[:bad_documents].to_h { |bad| [bad.document.id, bad.errors] }

    assert_equal ["missing access date"], errors[missing_date.id]
    assert_match(/outside day \[30\] range low \[5\], high \[26\]/, errors[out_of_range.id].sole)
    assert_equal ["missing delivery method"], errors[bare_spt.id]
    assert_nil errors[fine.id]

    flagged = result[:rows].reject(&:selectable?).flat_map { |row| row.documents.map(&:id) }
    assert_equal [missing_date.id, out_of_range.id, bare_spt.id].sort, flagged.sort
  end

  test "the TAS_SAPDateRange setting drives the allowed day window" do
    sap_date_range("10-12")
    document(@ranger, type: AccessDocument::SAP, access_date: august(14))

    bad = TrsExport.build_rows(filter("all"))[:bad_documents].sole
    assert_match(/range low \[10\], high \[12\]/, bad.errors.sole)
  end

  test "a vehicle pass with no delivery method is fine when the holder has a staff credential" do
    document(@ranger, type: AccessDocument::VEHICLE_PASS_GIFT)
    document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, status: AccessDocument::SUBMITTED, access_any_time: true)
    document(@alpha, type: AccessDocument::VEHICLE_PASS_SP)

    bad = TrsExport.build_rows(filter("all"))[:bad_documents]
    assert_equal [[@alpha.id, ["missing delivery method"]]],
                 bad.map { |entry| [entry.document.person_id, entry.errors] }
  end

  # --- export! -------------------------------------------------------------

  test "export stamps the audit comment and builds the vendor CSV" do
    sc = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(14))
    operator = person(:active_ranger)

    result = TrsExport.export!(filter("staff_credential"), [sc.id], operator)

    assert_match "#{operator.callsign}: exported with filter staff_credential", sc.reload.comments
    assert_equal AccessDocument::CLAIMED, sc.status

    assert_match(/\Atrs-staff-credential-#{YEAR}-07-01-\d{2}-\d{2}\.csv\z/, result[:filename])
    header, line = result[:csv].split("\n")
    assert_equal TrsExport::UNPAID_EXPORT_FORMAT.map(&:first).join(","), header

    cells = line.split(",")
    format_keys = TrsExport::UNPAID_EXPORT_FORMAT.map(&:last)
    assert_equal @ranger.first_name, cells[format_keys.index("first_name")]
    assert_equal "Ranger #{@ranger.callsign}", cells[format_keys.index("project_name")]
    assert_equal TrsExport::CREDENTIAL_PICKUP, cells[format_keys.index("delivery_type")]
    assert_equal "1", cells[format_keys.index("sc_0814")]
    assert_equal "CRED Fri 08/14 - RAD-#{sc.id} exported by CHID ##{operator.id}",
                 cells[format_keys.index("note")]
    assert_empty result[:skipped]
  end

  test "export skips documents that are no longer claimed and half-posted pairs" do
    sc = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, access_any_time: true)
    vp = document(@ranger, type: AccessDocument::VEHICLE_PASS_GIFT)
    banked = document(@alpha, type: AccessDocument::GIFT, status: AccessDocument::BANKED)

    result = TrsExport.export!(filter("staff_credential_vp"), [sc.id, banked.id], person(:active_ranger))

    assert_empty result[:rows]
    assert_equal [["RAD-#{sc.id}", "not in this filter's current rows"],
                  ["RAD-#{banked.id}", "status is now banked"]].sort,
                 result[:skipped].map { |skip| [skip.ref, skip.reason] }.sort
    assert_no_match(/exported with filter/, sc.reload.comments.to_s)
    assert_no_match(/exported with filter/, vp.reload.comments.to_s)
  end

  # --- mark_submitted! -----------------------------------------------------

  test "mark submitted flips claimed documents with the upstream comment" do
    spt = document(@ranger, type: AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_WILL_CALL)
    banked = document(@ranger, type: AccessDocument::GIFT, status: AccessDocument::BANKED)

    result = TrsExport.mark_submitted!([spt.id, banked.id])

    assert_equal AccessDocument::SUBMITTED, spt.reload.status
    assert_match "bulk marked submitted\ndelivery will_call", spt.comments
    assert_equal AccessDocument::BANKED, banked.reload.status

    row = result[:rows].sole
    assert_equal ["RAD-#{spt.id}", "claimed → submitted", "delivery will_call", nil],
                 [row.ref, row.change, row.detail, row.error]
    assert_equal [["RAD-#{banked.id}", "status is now banked"]],
                 result[:skipped].map { |skip| [skip.ref, skip.reason] }
  end

  test "a gift vehicle pass rides with a staff credential only inside the batch" do
    vp = document(@ranger, type: AccessDocument::VEHICLE_PASS_GIFT, delivery_method: AccessDocument::DELIVERY_POSTAL)
    sc = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, access_any_time: true)
    lone_vp = document(@alpha, type: AccessDocument::VEHICLE_PASS_GIFT, delivery_method: AccessDocument::DELIVERY_POSTAL)
    document(@alpha, type: AccessDocument::STAFF_CREDENTIAL, access_any_time: true) # not posted

    TrsExport.mark_submitted!([vp.id, sc.id, lone_vp.id])

    assert_match "delivery w/Staff Credential", vp.reload.comments
    assert_match "delivery postal", lone_vp.reload.comments
  end
end
