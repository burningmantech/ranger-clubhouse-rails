# frozen_string_literal: true

# One line of the pasted list, from the raw text through to the verdict the
# preview prints for it.
#
# `raw` is kept for the lines that match no one: a reader looking for their typo
# needs to see what they actually typed. `data` is the rest of the comma
# separated line, which is everything the handler parses -- a date, a ticket
# type, a count -- and is empty for the callsign-only actions.
class BulkUpload::Entry
  # Every verdict a line can draw, and which of the three buckets it lands in.
  #
  # Upstream has two -- anything that is not a write is an error -- which paints
  # "already recorded" red on the ordinary case of re-running a list. Unchanged
  # is its own bucket here, and only a line that cannot be acted on at all
  # counts as a problem.
  CATEGORY = {
    change: :changing,
    replace: :changing,
    duplicate: :skipping,
    no_change: :skipping,
    not_found: :problem,
    ambiguous: :problem,
    blocked_status: :problem,
    invalid: :problem
  }.freeze

  attr_reader :raw, :data, :person, :verdict, :message

  def initialize(raw:, data:, person: nil)
    @raw = raw
    @data = data
    @person = person
  end

  def callsign = person&.callsign || raw

  def category = CATEGORY.fetch(@verdict)

  def decided? = !@verdict.nil?

  # The handler's answer for this line. `replace` and `change` both write; the
  # split exists so the preview can say that a write lands on top of something
  # that already exists, which is the one case a reader would want to stop for.
  def decide(verdict, message = nil)
    @verdict = verdict
    @message = message
    self
  end
end
