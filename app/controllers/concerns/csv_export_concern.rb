# frozen_string_literal: true

# Hand-rolled CSV export plumbing. Controllers build an array of row arrays
# (header row first) and call send_csv; non-controller callers (e.g. data:
# URI downloads) call CsvExportConcern.build for the text alone, so every
# producer shares one set of quoting rules.
# The stdlib CSV library is deliberately not used anywhere in the app.
module CsvExportConcern
  extend ActiveSupport::Concern

  # Serialize rows into CSV text.
  def self.build(rows)
    rows.map { |row| row.map { |value| cell(value) }.join(",") }.join("\n")
  end

  # A cell a spreadsheet would read as a formula rather than as text. Excel and
  # Sheets evaluate anything opening with one of these, so a callsign, position
  # title, or shift description someone typed can run on the reader's machine
  # and address the rest of the sheet. The leading tab and carriage return are
  # here too: both are stripped on import, exposing the character behind them.
  #
  # A character has to follow it -- a cell holding only "-" is a placeholder
  # several exports use for "none", and one character can name no function and
  # reach no other cell.
  FORMULA_LEAD = /\A[=+\-@\t\r]./m

  # Plain numbers are exempt -- a negative amount opens with "-" and has to stay
  # a number, or every numeric column in every export becomes text.
  PLAIN_NUMBER = /\A[+-]?\d+(\.\d+)?\z/

  # Quotes a cell only when it contains a comma, quote, or newline, doubling
  # embedded quotes per RFC 4180. A formula lead is disarmed first with an
  # apostrophe, which spreadsheets read as "the rest is text" and do not display.
  def self.cell(value)
    text = value.to_s
    text = "'#{text}" if text.match?(FORMULA_LEAD) && !text.match?(PLAIN_NUMBER)
    escaped = text.gsub('"', '""')

    if text.match?(/[",\r\n]/)
      %("#{escaped}")
    else
      escaped
    end
  end

  private

  # The Y/N a spreadsheet column of yes-or-no answers holds. Spelled once so
  # every export answers the question the same way, and so a column stays
  # comparable against the same export from an earlier year.
  def csv_yes_no(value) = value ? "Y" : "N"

  def send_csv(rows, filename:)
    send_data(CsvExportConcern.build(rows),
              filename:,
              type: "text/csv; charset=utf-8",
              disposition: "attachment")
  end
end
