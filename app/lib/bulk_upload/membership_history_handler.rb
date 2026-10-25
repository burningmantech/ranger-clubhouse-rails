# frozen_string_literal: true

# Records one span of team membership -- joined on, and optionally left on --
# for a list of callsigns.
#
# Upstream's TeamMembershipHandler, with the team taken out of the line. There
# the team name is the first column of every row and is looked up per row, which
# cannot be reconciled with a page a team manager reaches: a name typed into a
# line could name a team the reader does not manage, and the page would have to
# re-check the manager against a different team on every line. Here the team is
# chosen once from a select the controller has already narrowed, and the line
# carries only dates.
#
# History only. Nothing here touches person_team, so a row written by this
# handler never changes who is on the team today -- which is upstream's own
# caveat, and why this page carries an advisory saying so.
class BulkUpload::MembershipHistoryHandler < BulkUpload::Handler
  # One date format, and only one. Upstream hands the column to Carbon::parse,
  # which reads "8/1/2024" as August 1st; Ruby's Date.parse reads that same
  # string as 8 January. Either way a spreadsheet paste in the other convention
  # lands silently on the wrong date, and a wrong date in a history row is
  # invisible afterwards. The format is stated on the page, and anything else is
  # refused rather than guessed at.
  DATE_FORMAT = "%Y-%m-%d"
  DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

  # Repeated in every shape refusal, because a reader who got the shape wrong
  # cannot see the format from the message alone -- the textarea's help text is
  # on the previous screen by the time the preview is being read.
  LINE_FORMAT = "A line is callsign, joined on date, and optionally left on date."

  # No preload: every line writes a new history row, so there is no existing
  # state for a decision to be compared against. The inherited no-op stands.
  #
  # Which also means a list pasted twice records the span twice, as upstream
  # does. Deliberate: person_team_log carries no unique key, and a person can
  # legitimately join, leave and rejoin the same team, so two identical rows are
  # a duplicate only in the reader's head. The preview names every span it is
  # about to write, which is where a second run gets caught.

  def decide(entry)
    values = columns(entry)
    return entry.decide(:invalid, "Missing joined on date. #{LINE_FORMAT}") if values.first.blank?
    return entry.decide(:invalid, "Too many columns. #{LINE_FORMAT}") if values.size > 2

    joined_on = parse_date(values[0])
    return entry.decide(:invalid, bad_date("Joined on", values[0])) unless joined_on

    left_on = parse_date(values[1])
    return entry.decide(:invalid, bad_date("Left on", values[1])) if values[1].present? && left_on.nil?

    # PersonTeamLog refuses this pair, and upstream does not check it at all --
    # it saves without validating, so a reversed pair becomes a history row
    # there. The validation is kept, and answered here as well, so a swapped
    # line reads as a problem in the preview instead of arriving as a failed
    # line after the reader has confirmed.
    if left_on && left_on < joined_on
      return entry.decide(:invalid, "Left on #{left_on} is before joined on #{joined_on}. Swap the dates.")
    end

    entry.decide(:change, span(joined_on, left_on))
  end

  # Re-parsed rather than carried over from decide: an entry holds its verdict,
  # not a payload, and apply only ever sees a line decide has just accepted.
  #
  # entry.person's narrow projection is enough -- only the id is read, and the
  # person row itself is not written to.
  def apply(entry)
    values = columns(entry)

    PersonTeamLog.create!(person_id: entry.person.id,
                          team_id: context[:team].id,
                          joined_on: parse_date(values[0]),
                          left_on: parse_date(values[1]))
  end

  private

  def bad_date(which, value) = "#{which} date must be YYYY-MM-DD — #{value} is not."

  def span(joined_on, left_on)
    return "Joined #{joined_on}" if left_on.nil?

    "Joined #{joined_on}, left #{left_on}"
  end

  # nil for anything that is not exactly one ISO date, a blank column included.
  def parse_date(value)
    return nil unless value.to_s.match?(DATE_PATTERN)

    Date.strptime(value, DATE_FORMAT)
  rescue Date::Error
    # The pattern admits 2024-02-31; the calendar does not.
    nil
  end
end
