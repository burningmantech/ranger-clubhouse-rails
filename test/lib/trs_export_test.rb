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
  # The formats are TrsFormat rows; test/migrations/create_trs_format_test.rb
  # pins their seeded header rows byte for byte.

  test "each filter picks the upstream format" do
    %w[special_price_ticket spt_vp vehicle_pass_sp gift_ticket].each do |slug|
      assert_equal trs_format(:paid), TrsExport.export_format(filter(slug)), slug
    end
    %w[lsd_ticket lsd_vp vehicle_pass_lsd].each do |slug|
      assert_equal trs_format(:lsd), TrsExport.export_format(filter(slug)), slug
    end
    %w[staff_credential staff_credential_vp vehicle_pass_gift work_access_pass_ranger work_access_pass_so].each do |slug|
      assert_equal trs_format(:unpaid), TrsExport.export_format(filter(slug)), slug
    end
  end

  test "a source is a row field or a request column, dated ones by date or anytime" do
    %w[first_name note spt sp_vp gift_ticket gift_vp lsd lsd_vp sc_0814 sap_0808 sc_anytime sap_anytime].each do |key|
      assert TrsExport.source?(key), key
    end
    [nil, "", "ignore", "sap", "sc", "sap_814", "sap_unspecified", "spt_0814", "gift_vp_anytime", " spt", "SPT",
     "sap_0862", "sap_1301", "sc_0800", "sap_9999"].each do |key|
      assert_not TrsExport.source?(key), key.inspect
    end
  end

  test "a source is named the way a person reads it" do
    { nil => "Not Used", "" => "Not Used", "email" => "Email", "project_name" => "Nickname / Project",
      "gift_vp" => "Gift Vehicle Passes", "spt" => "Special Price Tickets",
      "sap_0826" => "Setup Access Pass · Aug 26", "sc_0801" => "Staff Credential · Aug 1",
      "sap_anytime" => "Setup Access Pass · Any time", "sc_0907" => "Staff Credential · Sep 7",
      "sap_826" => "sap_826", "ignore" => "ignore" }.each do |key, label|
      assert_equal label, TrsExport.source_label(key), key.inspect
    end
  end

  # A request column with no label would be offered, and reported, by its key.
  test "every row field and request column has a label" do
    labelled = TrsExport::ROW_FIELD_LABELS.keys + TrsExport::REQUEST_LABELS.keys + TrsExport::DATED_LABELS.keys

    assert_equal (TrsExport::ROW_FIELDS + TrsExport::TRS_COLUMN.values).uniq.sort, labelled.sort
    assert_equal TrsExport::DATED_COLUMNS.sort, TrsExport::DATED_LABELS.keys.sort
  end

  test "every row field is answered by the row itself, never by a count" do
    document(@ranger, type: AccessDocument::SPT, delivery_method: AccessDocument::DELIVERY_POSTAL)
    row = rows("special_price_ticket").sole

    TrsExport::ROW_FIELDS.each { |field| assert_predicate row.cell(field), :present?, field }
    assert_equal "", row.cell(nil), "a column with no source exports empty"
  end

  test "the export follows the format as it is edited" do
    sc = document(@ranger, type: AccessDocument::STAFF_CREDENTIAL, access_date: august(14))
    trs_format(:unpaid).update!(columns: [["Who", "project_name"], ["Unused", nil], ["Aug 14 &amp; After", "sc_0814"]])

    result = TrsExport.export!(filter("staff_credential"), [sc.id], person(:active_ranger))

    assert_equal ["Who,Unused,Aug 14 &amp; After", "Ranger #{@ranger.callsign},,1"], result[:csv].split("\n")
  end

  test "a filter whose format has no row says which one, and the All view still builds" do
    trs_format(:lsd).delete

    error = assert_raises(TrsExport::MissingFormat) { rows("lsd_ticket") }
    assert_equal "The LSD TRS format is missing from the database.", error.message
    assert_nothing_raised { rows("all") }
    assert_nothing_raised { rows("gift_ticket") }
  end

  test "a request with no column in the format is flagged on its filter only" do
    fine = document(@ranger, type: AccessDocument::SAP, access_date: august(14))
    early = document(@alpha, type: AccessDocument::SAP, access_date: august(7))
    dateless = document(@prospective, type: AccessDocument::SAP)

    by_id = rows("work_access_pass_all").index_by { |row| row.documents.sole.id }
    assert_empty by_id[fine.id].errors
    assert_equal ["no column for Setup Access Pass · Aug 7 in the Unpaid format"], by_id[early.id].errors
    assert_not by_id[early.id].selectable?
    assert_equal ["missing access date"], by_id[dateless.id].errors, "an unspecified date is no source"

    assert_empty rows("all").flat_map(&:errors) - ["missing access date"]
    assert_nil TrsExport.build_rows(filter("all"))[:format]
    assert_equal trs_format(:unpaid), TrsExport.build_rows(filter("work_access_pass_all"))[:format]
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
    cells = TrsExport.csv_rows(trs_format(:unpaid), [row]).last
    keys = trs_format(:unpaid).columns.map(&:last)
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
    assert_equal trs_format(:unpaid).headers.join(","), header

    cells = line.split(",")
    format_keys = trs_format(:unpaid).columns.map(&:last)
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
