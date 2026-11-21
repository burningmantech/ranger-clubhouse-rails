# frozen_string_literal: true

# One of the ticket vendor's three TRS import templates: the CSV columns a TRS
# export carries, in order. The set is fixed -- TrsExport picks one by slug for
# each export filter -- and only the columns are edited (Ticketing > TRS Formats).
#
# columns holds [header, source] pairs. The header is the vendor's text and is
# kept to the character: the literal &amp;, a double space and the capitals are
# all what TRS matches on. The source says what fills the column
# (TrsExport.source?); a nil source is a column the template needs and the
# Clubhouse always leaves empty.
class TrsFormat < ApplicationRecord
  self.table_name = "trs_format"
  self.audit_model = true

  # In the order the formats are listed.
  TITLES = { "paid" => "Paid & Gift Tickets", "unpaid" => "Unpaid", "lsd" => "LSD" }.freeze
  HEADER_LIMIT = 255

  # What is trimmed from the ends of a header or a source: any Unicode space,
  # and the zero-width characters a paste from a spreadsheet or a web page can
  # carry. A plain strip leaves a non-breaking space behind, where nobody can
  # see it and TRS no longer matches the header.
  EDGE_BLANKS = /\A[[:space:]\u200B\u200C\u200D\uFEFF]+|[[:space:]\u200B\u200C\u200D\uFEFF]+\z/

  # JSON is LONGTEXT on MariaDB and reads back as a String without this.
  serialize :columns, coder: JSON

  validate :columns_are_usable

  # The form's rows, as two lists side by side (flat lists for the reason
  # ShiftCoveragePosition.entries_from_rows gives), in the order they are to be
  # saved: the page's arrows reorder them before they are posted. A row with
  # neither a header nor a source is dropped, which is how a column is removed.
  #
  # Only the ends of a header are trimmed. Never squish one: the vendor's
  # "Setup Access Pass  8/15" has two spaces in it.
  def self.columns_from_rows(headers, sources)
    Array(headers).zip(Array(sources)).filter_map do |header, source|
      header = header.to_s.gsub(EDGE_BLANKS, "")
      source = source.to_s.gsub(EDGE_BLANKS, "").presence

      [header, source] unless header.empty? && source.nil?
    end
  end

  def self.in_order = all.sort_by { |format| TITLES.keys.index(format.slug) || TITLES.size }

  def title = TITLES.fetch(slug, slug)

  # A fingerprint of the columns as saved. The edit form carries the one it was
  # drawn from, so a save from a page someone else has saved over since is
  # refused instead of writing the old list back on top of theirs.
  def version = Digest::SHA256.hexdigest(JSON.generate(columns_in_database))

  def to_param = slug

  def headers = columns.map(&:first)

  # What the format's columns are filled from, the unused columns left out.
  def sources = columns.filter_map(&:last)

  private

  # Whole sentences, since errors.format prints a message alone. Each names its
  # column by row:, its place in the list, so the form can mark that row.
  def columns_are_usable
    list = Array(columns)
    return errors.add(:columns, "Add at least one column to the format.") if list.empty?

    seen = { headers: Set.new, sources: Set.new }
    list.each_with_index do |(header, source), row|
      message = header_problem(header.to_s, source, seen[:headers]) || source_problem(header.to_s, source, seen[:sources])
      errors.add(:columns, message, row:) if message
    end
  end

  # What is wrong with one column's header, or nil. TRS finds a column by its
  # header, so two columns cannot share one. A header the CSV writer would
  # disarm as a spreadsheet formula (CsvExportConcern.cell) would reach the
  # vendor with an apostrophe in front of it, so it is refused here instead.
  def header_problem(header, source, seen)
    return "The source #{TrsExport.source_label(source)} needs a CSV header beside it." if header.empty?

    if header.length > HEADER_LIMIT
      return "The CSV header #{header.truncate(40).inspect} is too long. Use #{HEADER_LIMIT} characters or fewer."
    end

    if header.match?(CsvExportConcern::FORMULA_LEAD) && !header.match?(CsvExportConcern::PLAIN_NUMBER)
      return "The CSV header #{header.inspect} starts with a character the export cannot write as typed (=, +, - or @)."
    end

    "The CSV header #{header.inspect} is on more than one column. Use each header once." unless seen.add?(header)
  end

  # What is wrong with one column's source, or nil. A source that filled two
  # columns would send the vendor the same request twice.
  def source_problem(header, source, seen)
    return if source.nil?
    return "#{source.inspect} beside #{header.inspect} is not a source the export can fill." unless TrsExport.source?(source)

    "The source #{TrsExport.source_label(source)} fills more than one column. Use each source once." unless seen.add?(source)
  end
end
