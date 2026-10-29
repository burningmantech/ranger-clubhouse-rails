# frozen_string_literal: true

# The run behind `bin/rails legacy_log:convert`: walks the Clubhouse 1 log in
# id order, a batch at a time, and upserts what LegacyLog::Converter makes of
# each row. The rows are keyed by log_id, so a rerun rewrites the same rows
# and a grammar fix needs only a rerun. It reads `log` and writes
# `legacy_log`, and deletes nothing. The report at the end is the evidence the
# conversion is judged by: rows read, skipped by reason, converted, unknown,
# and each family with a few of its unknown rows.
class LegacyLog::Conversion
  BATCH = 5_000
  EXAMPLES = 3
  EXAMPLE_LENGTH = 120

  attr_reader :counts, :families

  # @param from_id, to_id [Integer, nil] bound the log ids, for a rehearsal
  # @param dry_run [Boolean] read and report, write nothing
  # @param output [IO] where the progress lines and the report go
  def initialize(from_id: nil, to_id: nil, dry_run: false, output: $stdout)
    @from_id = from_id
    @to_id = to_id
    @dry_run = dry_run
    @output = output
    @counts = Hash.new(0)
    @families = Hash.new { |hash, family| hash[family] = { converted: 0, unknown: 0, examples: [] } }
    @last_id = 0
  end

  def run
    Clubhouse1Log.in_batches(of: BATCH, start: @from_id, finish: @to_id) do |batch|
      rows = batch.pluck(:id, :user_person_id, :current_person_id, :occurred, :event)
                  .filter_map { |values| convert(values) }
      # No unique_by: MariaDB has no conflict target, its ON DUPLICATE KEY
      # UPDATE takes the table's unique index (log_id) by itself. No returning:
      # MariaDB would otherwise send every id back, to be thrown away.
      LegacyLog.upsert_all(rows, returning: false) if rows.any? && !@dry_run
      @output.puts "  #{delimited(@counts[:read])} read, #{delimited(@counts[:converted])} converted, " \
                   "#{delimited(@counts[:unknown])} unknown, through log ##{delimited(@last_id)}"
    end

    @output.puts report
    self
  end

  def report
    written = @counts[:converted] + @counts[:unknown]
    skipped = LegacyLog::Converter::SKIPS.map { |reason, opening| "#{delimited(@counts[reason])} #{reason} (#{opening})" }
    lines = ["Legacy log conversion#{" (dry run)" if @dry_run}: #{delimited(@counts[:read])} rows read"]
    lines << "  Skipped: #{skipped.join(", ")}"
    lines << "  Converted: #{delimited(@counts[:converted])}#{share(@counts[:converted], written)}"
    lines << "  Unknown: #{delimited(@counts[:unknown])}#{share(@counts[:unknown], written)}"
    lines << "  By family (converted / unknown, with unknown examples):"
    @families.sort_by { |family, tally| [-(tally[:converted] + tally[:unknown]), family] }.each do |family, tally|
      lines << "    #{family}: #{delimited(tally[:converted])} / #{delimited(tally[:unknown])}"
      tally[:examples].each { |example| lines << "      #{example}" }
    end
    lines.join("\n")
  end

  private

  def convert(values)
    @counts[:read] += 1
    @last_id = [@last_id, values.first].max
    if (reason = LegacyLog::Converter.skip_reason(values.last))
      @counts[reason] += 1
      return nil
    end

    row, family = LegacyLog::Converter.convert(*values)
    result = (row[:event] == LegacyLog::UNKNOWN) ? :unknown : :converted
    tally = @families[family || "other"]
    @counts[result] += 1
    tally[result] += 1
    if result == :unknown && tally[:examples].size < EXAMPLES
      tally[:examples] << "##{row[:log_id]} #{row[:message].truncate(EXAMPLE_LENGTH)}"
    end
    row
  end

  def delimited(number)
    number.to_fs(:delimited)
  end

  def share(count, total)
    total.positive? ? " (#{(100.0 * count / total).round(2)}% of #{delimited(total)})" : ""
  end
end
