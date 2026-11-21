# frozen_string_literal: true

require "test_helper"

class TrsFormatTest < ActiveSupport::TestCase
  def errors_for(columns)
    format = trs_format(:lsd)
    format.columns = columns
    format.valid?
    format.errors.details[:columns].map { |detail| [detail[:row], detail[:error]] }
  end

  test "a fixture reads its columns, headers and sources and is not changed by loading" do
    format = trs_format(:paid)

    assert_equal "Paid & Gift Tickets", format.title
    assert_equal "paid", format.to_param
    assert_equal 16, format.columns.size
    assert_equal ["Request: Gift Ticket", nil], format.columns[8]
    assert_equal "Request: $250 Ticket", format.headers[6]
    assert_equal %w[first_name last_name email delivery_type project_name note spt gift_vp gift_ticket sp_vp],
                 format.sources
    assert_not format.changed?
    assert format.valid?
  end

  # ---------------------------------------------------------------- the rows

  test "rows are paired and kept in the order they were posted" do
    assert_equal [["B", nil], ["A", "first_name"], ["C", "note"]],
                 TrsFormat.columns_from_rows(%w[B A C], ["", "first_name", "note"])
  end

  test "a row with neither a header nor a source is dropped, and a lone source is kept to be refused" do
    assert_equal [["A", nil], ["B", "spt"]], TrsFormat.columns_from_rows(["A", "", " ", "B"], ["", "", " ", "spt"])
    assert_equal [["", "spt"]], TrsFormat.columns_from_rows([""], ["spt"])
    assert_empty TrsFormat.columns_from_rows(nil, nil)
  end

  test "only the ends of a header are trimmed: the vendor's inner spacing and &amp; are kept" do
    header = "Request: Setup Access Pass  8/15 &amp; Later"

    assert_equal [[header, "sap_0815"]], TrsFormat.columns_from_rows(["  #{header} "], [" sap_0815 "])
  end

  test "a pasted non-breaking or zero-width space is trimmed from the ends too" do
    assert_equal [["Request: $250 Ticket", "spt"]],
                 TrsFormat.columns_from_rows(["\u00A0Request: $250 Ticket\u200B\u00A0"], ["spt\uFEFF"])
    assert_empty TrsFormat.columns_from_rows(["\u00A0"], ["\u200B"])
  end

  test "the version follows the saved columns, not ones being edited" do
    format = trs_format(:lsd)
    before = format.version

    format.columns = [["Only", nil]]
    assert_equal before, format.version
    format.save!
    assert_not_equal before, format.version
  end

  test "the columns survive a save and a reload to the character" do
    format = trs_format(:unpaid)
    before = format.columns.deep_dup

    format.update!(columns: TrsFormat.columns_from_rows(before.map(&:first), before.map(&:last)))

    assert_equal before, format.reload.columns
    assert_includes format.headers, "Request: Setup Access Pass  8/15 &amp; Later"
  end

  # ------------------------------------------------------------ validations

  test "a format needs at least one column" do
    assert_equal [[nil, "Add at least one column to the format."]], errors_for([])
  end

  test "each bad column is named by its row" do
    problems = errors_for([["First Name", "first_name"],
                           ["", "spt"],
                           ["Bad Source", "sap_826"],
                           ["Again", "first_name"],
                           ["x" * 256, nil],
                           ["Unused", nil]])

    assert_equal [1, 2, 3, 4], problems.map(&:first)
    assert_equal "The source Special Price Tickets needs a CSV header beside it.", problems[0].last
    assert_equal '"sap_826" beside "Bad Source" is not a source the export can fill.', problems[1].last
    assert_equal "The source First Name fills more than one column. Use each source once.", problems[2].last
    assert_match(/is too long\. Use 255 characters or fewer\.\z/, problems[3].last)
  end

  test "a header may be used once, and may not open the way a spreadsheet formula does" do
    problems = errors_for([["Email", "email"], ["Email", nil], ["email", nil],
                           ["=SUM(A1)", nil], ["-Directed", nil], ["+1", nil], ["@home", nil], ["-", nil], ["-5", nil]])

    assert_equal [1, 3, 4, 6], problems.map(&:first), "case differs, a lone dash and a plain number are fine"
    assert_equal 'The CSV header "Email" is on more than one column. Use each header once.', problems[0].last
    assert_match(/\AThe CSV header "=SUM\(A1\)" starts with a character the export cannot write as typed/, problems[1].last)
  end

  test "any number of columns may go unused" do
    assert_empty errors_for([["A", nil], ["B", nil], ["C", "sc_anytime"]])
  end
end
