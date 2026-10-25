# frozen_string_literal: true

# What one bulk action decides about a line, and then does to it.
#
# The batch owns everything that is the same for every action -- parsing the
# paste, resolving callsigns, duplicates, locked accounts -- and a handler owns
# only the part that differs: what the line's remaining columns mean, whether
# the change is already in place, and the write itself.
#
# Two methods, called in two passes:
#
#   preload(entries)  once, before any decision, to fetch in one query what
#                     every line will be compared against. Upstream runs a
#                     SELECT per line; a 300-callsign paste turns that into 300
#                     round trips, twice, because the preview and the apply both
#                     evaluate the whole list.
#   decide(entry)     per line, verdict plus the sentence the preview prints.
#   apply(entry)      per line, only for entries decided :change or :replace,
#                     inside a transaction the batch opens.
#
# `decide` runs again on apply against freshly preloaded state, so a line whose
# world moved between the two steps is re-judged rather than written blind.
class BulkUpload::Handler
  # The season turns over after the event, not on New Year's Day: until
  # September a record being entered was earned at the event that has just
  # happened, which belongs to last year.
  SEASON_ROLLOVER_MONTH = 9

  # How far either side of the current year a typed year may land before it is
  # read as a typo rather than an intention.
  YEAR_SLACK = 5

  attr_reader :action, :reason, :context

  # @param action [BulkUpload::Action] the option that was chosen
  # @param reason [String] audit reason, recorded on every model that keeps one
  # @param context [Hash] page-supplied extras, e.g. the chosen team
  def initialize(action:, reason:, context: {})
    @action = action
    @reason = reason
    @context = context
  end

  # Bulk-load whatever `decide` compares against. Handlers that need nothing
  # keep the no-op.
  def preload(entries) = nil

  def decide(entry) = raise(NotImplementedError, "#{self.class}#decide")

  def apply(entry) = raise(NotImplementedError, "#{self.class}#apply")

  # The year every action operates in. Upstream reads current_year() inside each
  # handler; naming it once here keeps a page from quietly working in two
  # different years across its preview and its apply.
  def year = Current.year

  # Whether a locked account is refused before this handler is asked anything.
  # True for every action that does something TO a person, and false only where
  # moving a person out of a locked status is the point -- see StatusHandler.
  def refuses_locked_statuses? = true

  # The years an earned document or provision falls back on when its line names
  # none. Public because two pages print them: "the default" means something
  # different in August than it does in October, and a reader in April should
  # not have to know that.
  #
  # @return [Array(Integer, Integer)] source year, expiry year
  def self.default_years
    now = Current.time
    return [now.year, now.year + 4] if now.month >= SEASON_ROLLOVER_MONTH

    [now.year - 1, now.year + 3]
  end

  private

  # A typed count or year, or nil when the column is not one.
  #
  # Base 10 is named because Integer() would otherwise read a leading zero as
  # octal and "0x" as hex, and it is stricter than upstream's is_numeric plus an
  # integer cast, which turns "2.5" radios into 2 and the year "2026.9" into
  # 2026 without saying so.
  def whole_number(input) = Integer(input, 10, exception: false)

  # Upstream's checkYearRange, which takes the year by reference and returns a
  # boolean. Returns [year, nil] or [nil, refusal] instead.
  #
  # A source year may not be in the future -- the year a thing was earned has to
  # have happened -- while an expiry year of course may.
  #
  # @return [Array(Integer, nil), Array(nil, String)]
  def check_year_range(input, source:)
    label = source ? "Source Year" : "Expiry Year"
    parsed = whole_number(input)

    return [nil, "#{label} is not a number"] if parsed.nil?
    return [nil, "#{label} is more than #{YEAR_SLACK} years in the past"] if parsed < year - YEAR_SLACK
    return [nil, "#{label} is in the future [#{parsed}]"] if source && parsed > year
    return [nil, "#{label} is more than #{YEAR_SLACK} years in the future"] if parsed > year + YEAR_SLACK

    [parsed, nil]
  end

  def format_date(time) = time.strftime("%Y-%m-%d")

  # The columns after the callsign, trimmed and with trailing blanks dropped.
  #
  # Upstream leaves these untrimmed and then trims at each use, which it misses
  # in places -- "hubcap, 2024" reaches checkYearRange as " 2024". Trimmed once,
  # here. A trailing empty column is dropped so "hubcap," parses as a bare
  # callsign rather than as a line carrying one blank field, which is what a
  # spreadsheet export produces.
  def columns(entry)
    values = entry.data.map(&:strip)
    values.pop while values.any? && values.last.empty?
    values
  end

  # True when the line carries nothing but the callsign.
  def bare?(entry) = columns(entry).empty?

  def ids(entries) = entries.filter_map { |entry| entry.person&.id }
end
