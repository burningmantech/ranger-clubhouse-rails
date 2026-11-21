# frozen_string_literal: true

require "test_helper"

# Ticketing > TRS Formats: the list of the three formats and the grid that
# edits one format's columns. What a format is and how its rows are paired and
# checked lives in test/models/trs_format_test.rb.
class Ticketing::TrsFormatsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper # assert_unique_dom_ids

  HEADERS = "trs_format[row_headers][]"
  SOURCES = "trs_format[row_sources][]"

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    @paid = trs_format(:paid)
    ActionLog.delete_all

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # What the edit form would post back, read from its own fields.
  def posted_rows
    values = ->(name) { css_select("tbody input[name='#{name}']").map { |input| input["value"].to_s } }
    { version: css_select("input[name='trs_format[version]']").sole["value"],
      row_headers: values.call(HEADERS), row_sources: values.call(SOURCES) }
  end

  def save(format, headers:, sources:, version: format.version)
    patch ticketing_trs_format_path(format),
          params: { trs_format: { version:, row_headers: headers, row_sources: sources } }
  end

  test "the pages are refused without the admin or edit access documents role" do
    sign_in_as(@outsider)

    get ticketing_trs_formats_path
    assert_redirected_to me_root_path
    assert_equal "Admin or Edit Access Documents role required to manage TRS formats.", flash[:error]

    save(@paid, headers: ["Only"], sources: [""])
    assert_redirected_to me_root_path
    assert_equal 16, @paid.reload.columns.size
  end

  test "the index lists the three formats with the filters that use each" do
    get ticketing_trs_formats_path

    assert_response :success
    assert_select "tbody tr", 3
    assert_select "tbody tr:nth-child(1) th", text: "Paid & Gift Tickets"
    assert_select "tbody tr:nth-child(1)", text: /Gift Tickets/
    assert_select "tbody tr:nth-child(2) th", text: "Unpaid"
    assert_select "tbody tr:nth-child(2)", text: /SAP Ranger/
    assert_select "tbody tr:nth-child(3) th", text: "LSD"
    assert_select "a[href=?]", edit_ticketing_trs_format_path(@paid)
    assert_equal "/ticketing/trs-format-manage/paid/edit", edit_ticketing_trs_format_path(@paid)
  end

  test "the edit form draws a row per column, each field saying where it stands" do
    get edit_ticketing_trs_format_path(@paid)

    assert_response :success
    assert_select "tbody input[name=?]", HEADERS, count: 16
    assert_select "tbody input[name=?]", SOURCES, count: 16
    assert_select "input[type=hidden][name='trs_format[version]'][value=?]", @paid.version
    assert_select "tbody tr:nth-child(7) th[data-form-rows-number]", text: "7"
    assert_select "input#trs-column-6-header[value=?][aria-label=?]", "Request: $250 Ticket", "CSV header of column 7"
    assert_select "input#trs-column-6-header[data-form-rows-label=?][data-form-rows-id=?]",
                  "CSV header of column {n}", "trs-column-{i}-header"
    assert_select "input[type=hidden]#trs-column-6-source[value=spt][data-form-rows-id='trs-column-{i}-source']"
    assert_select "input[type=hidden]#trs-column-7-source:not([value])"
    assert_select "tbody input[type=text]", count: 16, message: "the header is the only field a column has to type in"
    assert_unique_dom_ids
  end

  # The buttons change the rows in the page (form-rows), so they submit nothing.
  # Every row has all four; an end row's arrow is hidden, not left out, because
  # which row is first or last changes in the page.
  test "each row carries in-page buttons to move it, insert under it and delete it" do
    get edit_ticketing_trs_format_path(@paid)

    assert_select "[data-controller=form-rows] tbody tr[data-form-rows-target=row]", count: 16
    { "up" => "Move up", "down" => "Move down",
      "insert" => "Insert a column below", "remove" => "Delete column" }.each do |action, title|
      assert_select "tbody button[type=button][data-action=?].btn-square[title=?]", "form-rows##{action}", title, count: 16
    end
    assert_select "tbody button.invisible", count: 2
    assert_select "tbody tr:first-child button[data-action='form-rows#up'].invisible"
    assert_select "tbody tr:last-child button[data-action='form-rows#down'].invisible"
    assert_select "tbody tr:nth-child(2) button[data-action='form-rows#remove'][aria-label=?][data-form-rows-label=?]",
                  "Delete column 2", "Delete column {n}"
    assert_select "[data-controller=form-rows][data-form-rows-noun-value=column]"
  end

  # Tabbing down the grid passes a row's four buttons in one stop: the first that
  # shows. The arrow keys reach the rest (form-rows#step).
  test "a row's buttons are one toolbar with one tab stop" do
    get edit_ticketing_trs_format_path(@paid)

    assert_select "tbody [role=toolbar][data-action='keydown->form-rows#step']", count: 16
    assert_select "tbody tr:nth-child(2) [role=toolbar][aria-label='Column 2 actions'][data-form-rows-label=?]",
                  "Column {n} actions"
    assert_select "tbody button[tabindex='0']", count: 16
    assert_select "tbody tr:first-child button[tabindex='0'][data-action='form-rows#down']"
    assert_select "tbody tr:nth-child(2) button[tabindex='0'][data-action='form-rows#up']"
    assert_select "tbody tr:nth-child(2) button[tabindex='-1']", count: 3
  end

  # The browser must not put typed values back after a reload (it matches by id,
  # and ids are renumbered in the page), and Turbo must not show a cached copy.
  test "the form is guarded against unsaved changes and against restored copies" do
    get edit_ticketing_trs_format_path(@paid)

    assert_select "form[autocomplete=off][data-controller~=unsaved-changes]:not([data-unsaved-changes-dirty-value])"
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "#trs-format-stale", 0
  end

  # A column's source is chosen, not typed: the row shows its name on a button
  # that opens the picker, and posts its key from a hidden field.
  test "each row names its source on a button that opens the picker" do
    get edit_ticketing_trs_format_path(@paid)

    assert_select "[data-controller=source-picker] form[data-controller~=unsaved-changes]"
    assert_select "tbody [data-source-picker-target=field]", count: 16
    assert_select "tbody td[class~='max-lg:grow'] > [data-source-picker-target=field]", count: 16
    assert_select "tbody [data-source-picker-target=field] button[type=button][aria-haspopup=dialog][data-action='source-picker#open']", count: 16
    assert_select "tbody tr:nth-child(7) [data-source-picker-target=label]", text: "Special Price Tickets"
    assert_select "tbody tr:nth-child(7) [data-source-picker-target=field] button .sr-only", text: "Source of column 7:"
    assert_select "tbody tr:nth-child(8) [data-source-picker-target=label].text-stone-muted", text: "Not Used"
    assert_select "tbody [data-source-picker-target=label].text-stone-muted", count: 6
  end

  # One dialog for the page, in a template the controller copies; outside the
  # form, whose own form the dialog's backdrop could not sit in.
  test "the picker offers every source once, with every day of August for a credential and a pass" do
    get edit_ticketing_trs_format_path(@paid)

    assert_select "form template[data-source-picker-target]", 0
    template = css_select("[data-controller=source-picker] > template[data-source-picker-target=template]").sole
    picker = Nokogiri::HTML5.fragment(template.inner_html)
    choices = picker.css("dialog#trs-source-picker button[data-source-picker-target=choice][data-action='source-picker#choose']")

    assert_equal 77, choices.size
    assert_equal choices.size, choices.map { |choice| choice["data-source"] }.uniq.size
    assert_equal ["Not Used: Export This Column Empty", "First Name"], choices.first(2).map { |choice| choice.text.strip }
    assert_equal ["", "Not Used", nil], %w[data-source data-label aria-label].map { |name| choices.first[name] }
    assert_equal "status", picker.at_css("[data-source-picker-target=note]")["role"]
    assert_equal ["Person", "How Many of an Item", "Staff Credentials, by Access Date in August",
                  "Setup Access Passes, by Access Date in August"], picker.css("h4").map { |heading| heading.text.strip }

    %w[sc sap].each do |base|
      days = choices.select { |choice| choice["data-source"].match?(/\A#{base}_08\d\d\z/) }
      assert_equal (1..31).map(&:to_s), days.map { |choice| choice.text.strip }, base
      assert_equal "Any time", choices.find { |choice| choice["data-source"] == "#{base}_anytime" }.text.strip
    end
    last = choices.find { |choice| choice["data-source"] == "sap_0831" }
    assert_equal ["Setup Access Pass · Aug 31", "Setup Access Pass · Aug 31"], %w[data-label aria-label].map { |name| last[name] }
    assert_equal 5, picker.css("[role=toolbar][data-action='keydown->source-picker#step']").size
    assert_equal "Source for Column", picker.at_css("[data-source-picker-target=title]").text.strip
  end

  test "an access date outside August that the format holds keeps a choice in the picker" do
    @paid.update!(columns: @paid.columns.map { |header, source| [header, source == "spt" ? "sc_0731" : source] })

    get edit_ticketing_trs_format_path(@paid)

    template = css_select("template[data-source-picker-target=template]").sole
    choice = Nokogiri::HTML5.fragment(template.inner_html).at_css("button[data-source=sc_0731]")
    assert_equal ["Jul 31", "Staff Credential · Jul 31"], [choice.text.strip, choice["aria-label"]]
  end

  # The blank row an insert copies. It sits outside the table, where the form
  # does not post it, and carries the patterns but no number, label or id yet.
  test "the grid holds one blank row in a template for the insert button" do
    get edit_ticketing_trs_format_path(@paid)

    template = css_select("[data-controller=form-rows] > template[data-form-rows-target=template]").sole
    row = Nokogiri::HTML5.fragment(template.inner_html, context: "tbody")

    assert_equal 1, row.css("tr[data-form-rows-target=row]").size
    assert_equal ["trs_format[row_headers][]", "trs_format[row_sources][]"], row.css("input").map { |input| input["name"] }
    assert_empty row.css("input[id], input[value], input[aria-label], button.invisible, [role=toolbar][aria-label]")
    assert_equal 4, row.css("button[data-form-rows-label]").size
    assert_equal ["0", "-1", "-1", "-1"], row.css("[role=toolbar] button").map { |button| button["tabindex"] }
    assert_equal "Not Used", row.at_css("[data-source-picker-target=field] [data-source-picker-target=label].text-stone-muted").text
  end

  # The vendor's bytes have to survive the trip through HTML and back, and so do
  # the unused columns between the used ones (6 in Paid, 14 in LSD).
  test "posting each form back as drawn leaves its format unchanged to the character" do
    %i[paid unpaid lsd].each do |name|
      format = trs_format(name)
      before = format.columns.deep_dup

      get edit_ticketing_trs_format_path(format)
      rows = posted_rows
      patch ticketing_trs_format_path(format), params: { trs_format: rows }

      assert_redirected_to ticketing_trs_formats_path
      assert_equal "#{format.title} format saved.", flash[:success]
      assert_equal before, format.reload.columns, name.to_s
    end

    assert_includes trs_format(:unpaid).headers, "Request: Setup Access Pass  8/15 &amp; Later"
    assert_empty ActionLog.pluck(:event), "nothing changed, so nothing is logged"
  end

  test "a save from a page drawn before someone else saved keeps the rows and saves nothing" do
    stale = @paid.version
    @paid.update!(columns: @paid.columns + [["Added Meanwhile", nil]])
    ActionLog.delete_all

    save(@paid, headers: ["Mine", "Also Mine"], sources: ["", "spt"], version: stale)

    assert_response :unprocessable_entity
    assert_equal 17, @paid.reload.columns.size
    assert_empty ActionLog.pluck(:event)
    assert_select "#trs-format-stale[role=alert][data-refusal]", text: /Someone else saved this format/
    assert_select "#trs-format-stale a[target=_blank][href=?]", edit_ticketing_trs_format_path(@paid)
    assert_select "input#trs-column-0-header[value=Mine]"
    assert_select "input#trs-column-1-source[value=spt]"
    assert_select "tbody input[name=?]", HEADERS, count: 2
    assert_select "form[data-unsaved-changes-dirty-value=true]"

    # The form now carries the saved format's fingerprint: saving again is a choice.
    current = css_select("input[name='trs_format[version]']").sole["value"]
    assert_equal @paid.version, current
    save(@paid, headers: ["Mine", "Also Mine"], sources: ["", "spt"], version: current)

    assert_redirected_to ticketing_trs_formats_path
    assert_equal [["Mine", nil], ["Also Mine", "spt"]], @paid.reload.columns
  end

  test "lists that do not line up are a bad request, never a save" do
    save(@paid, headers: %w[A B C], sources: %w[spt lsd])

    assert_response :bad_request
    assert_equal 16, @paid.reload.columns.size
  end

  test "an update saves the rows in the order posted, drops blank ones, and is logged" do
    save(trs_format(:lsd),
         headers: ["First Name", "New Column", "Last Name", "", "Email", "Unused"],
         sources: ["first_name", "lsd", "last_name", "", "email", ""])

    assert_redirected_to ticketing_trs_formats_path
    assert_equal [["First Name", "first_name"], ["New Column", "lsd"], ["Last Name", "last_name"],
                  ["Email", "email"], ["Unused", nil]],
                 trs_format(:lsd).reload.columns
    assert_equal ["trs-format-update"], ActionLog.pluck(:event)
  end

  test "a refused update redraws the rows as sent, marks the bad one and stays unsaved" do
    save(@paid, headers: ["Mystery", "First Name"], sources: ["sap_826", "first_name"])

    assert_response :unprocessable_entity
    assert_equal 16, @paid.reload.columns.size
    assert_select "#trs-columns-error", text: /"sap_826" beside "Mystery" is not a source the export can fill\./
    assert_select "input#trs-column-0-header[value=Mystery][aria-invalid=true]"
    assert_select "input#trs-column-1-header[value='First Name']:not([aria-invalid])"
    assert_select "tbody input[name=?]", HEADERS, count: 2
    assert_select "form[data-unsaved-changes-dirty-value=true]"
    assert_select "input[name='trs_format[version]'][value=?]", @paid.version
    assert_empty ActionLog.pluck(:event)
  end

  test "an unknown format is not found" do
    get edit_ticketing_trs_format_path("nope")

    assert_response :not_found
  end
end
