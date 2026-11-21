# frozen_string_literal: true

require "application_system_test_case"

# A TRS format's grid is edited in the browser: its buttons move, insert and
# delete columns (form_rows_controller.js) and a column's source is chosen from
# a picker (source_picker_controller.js). Nothing is saved until the form is,
# so this is the one place any of it can be seen working.
class Ticketing::TrsFormatRowsTest < ApplicationSystemTestCase
  include TimesheetAdminTestHelper # ensure_role / grant_role

  GRID = "[data-controller='form-rows']"
  PICKER = "dialog[open]#trs-source-picker"

  setup do
    admin = person(:active_ranger)
    ensure_role(Role::ADMIN, "Admin")
    grant_role(admin, Role::ADMIN)
    sign_in(admin)

    @format = trs_format(:paid)
    visit edit_ticketing_trs_format_path(@format)
    wait_for_controller("form-rows", GRID)
    wait_for_controller("source-picker", "[data-controller='source-picker']")
  end

  def press(title, row:)
    find("#{GRID} tbody tr:nth-child(#{row}) button[title='#{title}']").click
  end

  # A column that holds something is asked about before it goes. The answer
  # reaches the controller a turn after the press, so wait for the row to go.
  def delete_column(row, leaves: row_count - 1)
    press "Delete column", row: row
    accept_confirm_dialog
    assert_selector "#{GRID} tbody tr", count: leaves
  end

  # The header as typed, and the source as the form will post it.
  def row(number)
    [find("#trs-column-#{number - 1}-header").value, find("#trs-column-#{number - 1}-source", visible: :all).value]
  end

  # The source as the row's button names it.
  def source_name(row)
    find("#{GRID} tbody tr:nth-child(#{row}) [data-source-picker-target=label]").text
  end

  def open_picker(row)
    find("#{GRID} tbody tr:nth-child(#{row}) [data-source-picker-target=field] button").click
    assert_selector PICKER
  end

  def choice(key)
    find("#{PICKER} button[data-source='#{key}']", visible: :all)
  end

  # Greyed: another column holds it. It is aria-disabled, not disabled, so it still takes a press.
  def greyed?(key) = choice(key)["aria-disabled"] == "true"

  def focused
    page.evaluate_script("document.activeElement.getAttribute('aria-label') || document.activeElement.textContent.trim()")
  end

  def row_count = all("#{GRID} tbody tr").size

  def duplicate_ids
    page.evaluate_script(<<~JS)
      (() => { const ids = [...document.querySelectorAll("[id]")].map((element) => element.id);
               return ids.filter((id, index) => ids.indexOf(id) !== index) })()
    JS
  end

  # ------------------------------------------------------------ the picker

  test "the picker opens on the column's own source, with the sources other columns use greyed out" do
    open_picker 7

    assert_selector "#{PICKER} h3", text: "Source for Column 7"
    assert_selector "#{PICKER} p", text: "Request: $250 Ticket"
    assert_equal "true", choice("spt")["aria-pressed"]
    assert_equal "Special Price Tickets", focused, "the dialog opens with the focus on the current choice"

    # Paid uses the six person fields and four item counts; spt is this column's own.
    assert_equal %w[email first_name gift_ticket gift_vp last_name note project_name delivery_type sp_vp].sort,
                 all("#{PICKER} button[data-source][aria-disabled=true]").map { |button| button["data-source"] }.sort
    assert_equal "Fills column 10", choice("gift_vp")["title"]
    assert_not greyed?("sap_0831")
    assert_not greyed?(""), "Not Used is never taken"

    # A greyed choice takes a press, which changes nothing and says which column holds it.
    choice("gift_vp").click

    assert_selector "#{PICKER} [data-source-picker-target=note][role=status]",
                    text: "Gift Vehicle Passes already fills column 10. Change that column first to free it."
    find("#{PICKER} button", text: "Cancel").click
    assert_equal ["Request: $250 Ticket", "spt"], row(7)
  end

  # The second press lands inside the dialog the first one opened, on whatever is
  # under the pointer there: before it was dropped, column 10 came out of this
  # holding Setup Access Pass, Aug 10.
  test "a double-click on a column's button opens the picker and chooses nothing" do
    before = (1..16).map { |number| row(number) }

    (1..16).each do |number|
      find("#{GRID} tbody tr:nth-child(#{number}) [data-source-picker-target=field] button").double_click
      assert_selector PICKER
      find("#{PICKER} button", text: "Cancel").click
      assert_no_selector PICKER
    end

    assert_equal before, (1..16).map { |number| row(number) }
  end

  test "choosing the source a column already has changes nothing and leaves nothing unsaved" do
    open_picker 7
    choice("spt").click

    assert_no_selector PICKER
    assert_equal ["Request: $250 Ticket", "spt"], row(7)

    click_link "Cancel"

    assert_current_path ticketing_trs_formats_path
    assert_no_selector "#turbo-confirm-modal dialog[open]"
  end

  test "choosing writes the key the form posts and the name on the button, and is unsaved" do
    open_picker 8
    assert_equal "true", choice("")["aria-pressed"]

    choice("sap_0831").click

    assert_no_selector PICKER
    assert_equal ["Request: $165 Vehicle Pass", "sap_0831"], row(8)
    assert_equal "Setup Access Pass · Aug 31", source_name(8)
    assert_no_selector "#{GRID} tbody tr:nth-child(8) [data-source-picker-target=label].text-stone-muted"
    assert_equal "Source of column 8: Setup Access Pass · Aug 31", focused, "the focus is back on the column's button"

    # Back to Not Used, and the name is drawn muted again.
    open_picker 8
    assert_not greyed?("lsd")
    choice("").click
    assert_equal "Not Used", source_name(8)
    assert_selector "#{GRID} tbody tr:nth-child(8) [data-source-picker-target=label].text-stone-muted"

    open_picker 8
    choice("sc_0801").click
    click_button "Save Format"

    assert_text "Paid & Gift Tickets format saved."
    assert_equal ["Request: $165 Vehicle Pass", "sc_0801"], @format.reload.columns[7]
  end

  test "cancel, the close button and escape leave the column as it was" do
    ["Cancel", nil, :escape].each do |way|
      open_picker 7
      case way
      when "Cancel" then find("#{PICKER} button", text: "Cancel").click
      when nil then find("#{PICKER} .modal-header-bar button").click
      else find("#{PICKER} button[data-source='spt']").send_keys(:escape)
      end

      assert_no_selector PICKER
      assert_no_selector "dialog#trs-source-picker", visible: :all
      assert_equal ["Request: $250 Ticket", "spt"], row(7)
    end
  end

  test "a group of choices is one tab stop, walked with the arrow keys, Home and End" do
    open_picker 8

    # Staff Credentials: none in use on Paid, so the stop is the first choice.
    assert_equal "0", choice("sc_anytime")[:tabindex]
    assert_equal "-1", choice("sc_0801")[:tabindex]
    choice("sc_anytime").send_keys(:right, :right)
    assert_equal "Staff Credential · Aug 2", focused
    choice("sc_0802").send_keys(:end)
    assert_equal "Staff Credential · Aug 31", focused
    choice("sc_0831").send_keys(:home)
    assert_equal "Staff Credential · Any time", focused

    # How Many of an Item: four of the six are in use. The stop is the first that is free,
    # and the keys walk the greyed ones too, so a press can ask which column holds one.
    assert_equal "0", choice("lsd")[:tabindex]
    choice("lsd").send_keys(:right)
    assert_equal "LSD Vehicle Passes", focused
    choice("lsd_vp").send_keys(:left, :left)
    assert_equal "Gift Vehicle Passes", focused
    choice("gift_vp").send_keys(:enter)
    assert_selector "#{PICKER} [data-source-picker-target=note]", text: "Gift Vehicle Passes already fills column 10."
  end

  # ---------------------------------------------------------------- the rows

  test "an arrow moves a column with its source and keeps the focus on the one that moved" do
    press "Move up", row: 3

    assert_equal ["Email", "email"], row(2)
    assert_equal "Email", source_name(2)
    assert_equal ["Last Name", "last_name"], row(3)
    assert_equal "Move column 2 up", focused

    # Up again lands on the first row, whose up arrow is hidden.
    press "Move up", row: 2

    assert_equal ["Email", "email"], row(1)
    assert_equal ["First Name", "first_name"], row(2)
    assert_equal "Move column 1 down", focused
    assert_empty duplicate_ids
    assert_equal "First Name", @format.reload.headers.first, "nothing is saved by a move"
  end

  test "insert puts a blank column under the one pressed, numbered and ready to type in" do
    press "Insert a column below", row: 6

    assert_equal 17, row_count
    assert_equal "CSV header of column 7", focused
    assert_equal ["", ""], row(7)
    assert_equal "Not Used", source_name(7)
    assert_equal ["Request: $250 Ticket", "spt"], row(8), "the rows below it are numbered again"
    assert_selector "#{GRID} tbody tr:nth-child(17) th", text: "17"
    assert_selector "#{GRID} tbody tr:nth-child(17) button[title='Move down'].invisible", visible: :all
    assert_selector "#{GRID} tbody tr:nth-child(16) button[title='Move down']:not(.invisible)"
    assert_empty duplicate_ids

    fill_in "trs-column-6-header", with: "Request: New Thing"
    open_picker 7
    assert_selector "#{PICKER} h3", text: "Source for Column 7"
    choice("lsd").click
    press "Move up", row: 7
    assert_equal ["Request: New Thing", "lsd"], row(6)
    assert_equal "LSD Tickets", source_name(6)

    click_button "Save Format"

    assert_text "Paid & Gift Tickets format saved."
    columns = @format.reload.columns
    assert_equal 17, columns.size
    assert_equal [["Question: Nickname/Project:", "project_name"], ["Request: New Thing", "lsd"], ["Question: Notes:", "note"]],
                 columns[4, 3]
  end

  test "delete asks first, takes the column out, numbers the rest again, and is saved with the form" do
    press "Delete column", row: 2

    assert_selector "dialog[open]", text: "Delete column 2, “Last Name”? It is gone for good once the form is saved."
    find("dialog[open] button", text: "Cancel").click
    assert_equal 16, row_count, "a no leaves the column where it was"

    delete_column 2

    assert_equal 15, row_count
    assert_equal ["Email", "email"], row(2)
    assert_equal "Delete column 2", focused
    assert_equal 16, @format.reload.columns.size, "nothing is saved by a delete"

    # The last row: the row above becomes the last and loses its down arrow.
    delete_column 15

    assert_equal 14, row_count
    assert_equal "Delete column 14", focused
    assert_selector "#{GRID} tbody tr:nth-child(14) button[title='Move down'].invisible", visible: :all
    assert_empty duplicate_ids

    # Its source is free again for another column.
    open_picker 8
    assert_not greyed?("last_name")
    find("#{PICKER} button", text: "Cancel").click

    click_button "Save Format"

    assert_text "Paid & Gift Tickets format saved."
    headers = @format.reload.headers
    assert_equal 14, headers.size
    assert_not_includes headers, "Last Name"
    assert_not_includes headers, "Request: $75 Vehicle Pass"
  end

  test "a blank column goes without a question, one with only a source is asked about, and the last is reset" do
    press "Insert a column below", row: 1
    press "Delete column", row: 2

    assert_no_selector "dialog[open]"
    assert_equal 16, row_count

    # A source and no header: the row holds something, though nothing names it.
    press "Insert a column below", row: 1
    open_picker 2
    choice("lsd").click
    press "Delete column", row: 2
    assert_selector "dialog[open]", text: "Delete column 2? It is gone for good once the form is saved."
    accept_confirm_dialog
    assert_selector "#{GRID} tbody tr", count: 16

    15.times { delete_column 1 }
    assert_equal 1, row_count

    delete_column 1, leaves: 1

    assert_field "trs-column-0-header", with: ""
    assert_equal ["", ""], row(1)
    assert_equal "Not Used", source_name(1)
    assert_equal 1, row_count
  end

  test "a refused save redraws the columns as sent, and a move takes the red mark with it" do
    press "Insert a column below", row: 3
    fill_in "trs-column-3-header", with: "First Name"
    click_button "Save Format"

    assert_selector "#trs-columns-error", text: "is on more than one column"
    assert_equal 17, row_count
    assert_equal ["First Name", ""], row(4)
    assert_equal ["Question: Method Of Delivery:", "delivery_type"], row(5)
    assert_selector "#trs-column-3-header[aria-invalid=true].input-error"
    assert_empty duplicate_ids
    assert_equal 16, @format.reload.columns.size

    # The red outline belongs to the column, not to the line it was drawn on.
    press "Move up", row: 4

    assert_equal ["First Name", ""], row(3)
    assert_selector "#trs-column-2-header[aria-invalid=true].input-error"
    assert_no_selector "#trs-column-3-header[aria-invalid], #trs-column-3-header.input-error"
  end

  test "a row's buttons take one tab stop, and the arrow keys walk them" do
    toolbar = "#{GRID} tbody tr:nth-child(2) [role=toolbar]"
    find("#{toolbar} button[title='Move up']").send_keys(:right)
    assert_equal "Move column 2 down", focused

    find("#{toolbar} button[title='Move down']").send_keys(:right, :right)
    assert_equal "Delete column 2", focused

    find("#{toolbar} button[title='Delete column']").send_keys(:left)
    assert_equal "Insert a column below column 2", focused

    # The first row's up arrow is hidden, so its stop is the down arrow; after a
    # delete the row that takes its place is given the same. The Source button
    # is no part of the toolbar and keeps a stop of its own.
    stops = -> { all("#{GRID} tbody tr:nth-child(1) [role=toolbar] button", visible: :all).map { |b| b[:tabindex] } }
    assert_equal ["-1", "0", "-1", "-1"], stops.call
    delete_column 1
    assert_equal ["-1", "0", "-1", "-1"], stops.call
    assert_nil find("#{GRID} tbody tr:nth-child(1) [data-source-picker-target=field] button")[:tabindex]
  end

  test "leaving with a change unsaved asks first" do
    open_picker 8
    choice("lsd").click
    click_link "Cancel"

    assert_selector "#turbo-confirm-modal dialog[open]", text: "Your changes have not been saved"
    find("dialog[open] button", text: "Stay on Page").click

    assert_equal "LSD Tickets", source_name(8), "staying keeps the page as it was left"
  end
end
