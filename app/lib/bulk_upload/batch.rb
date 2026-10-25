# frozen_string_literal: true

# A pasted list of callsigns, one chosen action, and what that action would do
# to each line -- then, on the second step, the doing of it.
#
# One object answers both questions, exactly as BulkTeamChange does for the team
# page: the preview a reader checks and the apply that follows are the same
# code, so they cannot disagree. The controller still rebuilds this from its own
# params before applying; the preview describes what will happen, it does not
# authorize it.
#
# This is the shared half of upstream's BulkUploader. Everything here is the
# same for all eight pages the single admin/bulk-upload page became -- the
# paste, the callsign lookup, the three buckets, the commit log -- and
# everything that differs lives in a BulkUpload::Handler.
class BulkUpload::Batch
  # Statuses no bulk action may touch. Upstream checks these too, but in
  # buildResult, which runs AFTER the handler: on a commit the write is saved
  # and then reported as failed, so a locked account is quietly changed while
  # the page says it was not. Checked before anything is decided here, so the
  # row the reader sees and the row the database keeps say the same thing.
  BLOCKED_STATUSES = Person::LOCKED_STATUSES

  # CONSTRAINT: these four columns are every attribute a preview reads off a
  # person. `person` is 88 columns wide including four LONGTEXTs, and a
  # 300-callsign paste would otherwise haul all of it twice, once to preview and
  # once to apply. A handler needing more asks for it in its own preload, and a
  # handler writing to the person row re-finds it whole in apply.
  PERSON_COLUMNS = %i[id callsign callsign_normalized status].freeze

  # What the audit trail says when the reader gave no reason of their own.
  # Upstream's default for the same field, kept so the two applications' history
  # rows read alike.
  DEFAULT_REASON = "bulk upload"

  Outcome = Struct.new(:changed, :failed, keyword_init: true) do
    def failed? = failed.any?
  end

  attr_reader :action

  # @param action [BulkUpload::Action] the chosen option
  # @param records [String] the pasted list, one record per line
  # @param reason [String] audit reason recorded on every write
  # @param context [Hash] page extras handed through to the handler
  def initialize(action:, records:, reason:, context: {})
    @action = action
    @records = records.to_s
    @reason = reason.presence || DEFAULT_REASON
    @handler = action.handler.new(action:, reason: @reason, context:)
  end

  def entries = @entries ||= build_entries

  def changing = bucket(:changing)

  def skipping = bucket(:skipping)

  def problems = bucket(:problem)

  # Each line is applied in its own transaction, so one bad row cannot undo the
  # rows before it and the rest of the list is still attempted. A raise lands in
  # `failed` with its message logged -- the page names the callsigns and sends
  # the reader to the log, because a raw SQL or Ruby message is not something to
  # hand an administrator.
  def apply!
    changed = []
    failed = []

    changing.each do |entry|
      ActiveRecord::Base.transaction { @handler.apply(entry) }
      changed << entry
    rescue StandardError => e
      Rails.logger.error("Bulk upload #{@action.id} failed for person #{entry.person.id}: " \
                         "#{e.class}: #{e.message}")
      failed << entry
    end

    record_commit(changed, failed)
    Outcome.new(changed:, failed:)
  end

  private

  def bucket(name) = buckets.fetch(name, [])

  def buckets = @buckets ||= entries.group_by(&:category)

  # One query for the whole list, plus whatever the handler preloads.
  #
  # Grouped rather than Person.find_all_by_callsigns, which indexes by
  # callsign_normalized -- a column with no unique index -- and so silently
  # keeps only the last of two people whose callsigns normalize alike. Here both
  # come back and the line is refused instead of landing on a guess.
  def build_entries
    parsed = parse
    matches = Person.select(*PERSON_COLUMNS)
                    .where(callsign_normalized: parsed.map { |line| line[:key] })
                    .group_by { |person| person.callsign_normalized.downcase }

    seen = Set.new
    entries = parsed.map { |line| resolve(line, matches[line[:key]] || [], seen) }

    # Preloaded once the people are known, and only for the lines still in play:
    # a handler asking "does this person already have one" has nothing to ask
    # about a callsign that matched no one.
    @handler.preload(entries.reject(&:decided?))
    entries.each { |entry| @handler.decide(entry) unless entry.decided? }
  end

  # A record is a callsign and then whatever that action's line format calls
  # for. Blank lines and lines whose callsign normalizes to nothing -- the "---"
  # separators that come with a pasted list -- are dropped rather than reported
  # as missing callsigns, which is what upstream does.
  #
  # `line_key` is the whole record, not just the callsign: several actions take
  # more than one line per person on purpose -- two access documents of different
  # types, two spells on a team, a certification's dates on one line and its card
  # number on the next -- and keying the repeat check on the callsign alone threw
  # every line after the first away.
  def parse
    @records.split("\n").filter_map do |line|
      callsign, *data = line.split(",")
      key = WordUtils.normalize_word(callsign.to_s)
      next if key.blank?

      { raw: line.strip, data:, key:, line_key: [key, *significant(data)] }
    end
  end

  # The line's columns as a handler will read them: trimmed, with trailing
  # blanks dropped, so "hubcap" and "hubcap," are the same record and repeat
  # each other. Mirrors BulkUpload::Handler#columns.
  def significant(data)
    values = data.map(&:strip)
    values.pop while values.any? && values.last.empty?
    values
  end

  # Repeats are caught before anything else, so the same record pasted twice
  # draws one verdict and not two -- otherwise a typo pasted twice counts as two
  # problems and the preview argues for a fix that is a single edit. Two lines
  # for one person that ask for different things are two records, not a repeat.
  # Set#add? answers nil for a value already present.
  #
  # A repeat carries a person only when the first occurrence resolved to exactly
  # one: naming a specific human on an ambiguous row would put a person link on
  # the very row whose point is that the callsign identified no one.
  def resolve(line, found, seen)
    entry = BulkUpload::Entry.new(raw: line[:raw], data: line[:data], person: found.one? ? found.first : nil)

    return entry.decide(:duplicate, "Listed more than once") unless seen.add?(line[:line_key])
    return entry.decide(:not_found, "Callsign not found") if found.empty?
    return entry.decide(:ambiguous, "More than one person matches that callsign") if found.many?

    person = found.first
    if @handler.refuses_locked_statuses? && BLOCKED_STATUSES.include?(person.status)
      return entry.decide(:blocked_status,
                          "Status is #{person.status} — this account is locked")
    end

    entry
  end

  # One row per commit, under upstream's event name so the two applications'
  # bulk history reads as one list. The pasted text is kept verbatim: it is the
  # only record of what was asked for, as opposed to what was found.
  #
  # Every line is reported, not just the ones that wrote. Upstream logs a result
  # per record too, and on the four pages whose targets keep no audit history of
  # their own this row is the entire trail -- "was Hubcap in that batch, and did
  # it take?" cannot be answered by a list of successes alone.
  def record_commit(changed, failed)
    written = Set.new(changed)
    stopped = Set.new(failed)

    results = entries.map do |entry|
      status = if written.include?(entry)
                 "success"
               elsif stopped.include?(entry)
                 "failed"
               else
                 entry.verdict.to_s
               end

      { callsign: entry.callsign, status: }.tap do |row|
        row[:details] = entry.message if entry.message.present?
      end
    end

    ActionLog.record(Current.person_id, "bulk-upload", "bulk upload commit",
                     { action: @action.id, reason: @reason, records: @records, results: })
  end
end
