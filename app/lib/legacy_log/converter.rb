# frozen_string_literal: true

# Turns one row of the Clubhouse 1 log into a legacy_log row, or names why the
# row is skipped. Until the grammar that reads a statement lands in
# LegacyLog::Parser, every SQL statement is written as `unknown`.
module LegacyLog::Converter
  # Rulings of 2026-10-28, by the opening of the event: `#` events (logins,
  # requests, credits) map to no action; `!` diagnostics (errors, failed
  # logins) are not actions; the session purges (`-sessions@...`, 804,000
  # rows) are housekeeping.
  SKIPS = { events: "#", diagnostics: "!", sessions: "-sessions" }.freeze

  class << self
    # Why a row is skipped, or nil when it is converted.
    def skip_reason(event)
      SKIPS.find { |_reason, opening| event.start_with?(opening) }&.first
    end

    # The five columns of a log row, in table order.
    #
    # @return [Array(Hash, String)] the legacy_log row and the statement's family
    def convert(id, user_person_id, current_person_id, occurred, event)
      text, _truncated = LegacyLog::Parser.normalize(event)
      [unknown_row(id, user_person_id, current_person_id, occurred, event), LegacyLog::Parser.family(text)]
    end

    private

    # Ruling 6: an unknown row keeps the session's person as its target, and
    # says so in data. The whole event travels in data as well, so a later
    # conversion never needs the log table again. The first Clubhouse wrote 0
    # as well as NULL for no one; nonzero? reads both as nil.
    def unknown_row(id, user_person_id, current_person_id, occurred, event)
      {
        log_id: id,
        person_id: user_person_id&.nonzero?,
        target_person_id: current_person_id&.nonzero?,
        event: LegacyLog::UNKNOWN,
        message: event,
        data: { "event" => event, "log_id" => id, "target_source" => "session" },
        created_at: occurred
      }
    end
  end
end
