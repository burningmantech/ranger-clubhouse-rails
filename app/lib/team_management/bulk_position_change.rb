# frozen_string_literal: true

# What a bulk grant or revoke will do to a pasted list of callsigns, and then
# the doing of it.
#
# One object answers both, so the preview a manager reads and the apply that
# follows cannot disagree: #apply! walks the same #changing the preview drew.
# The controller still rebuilds this object from its own params before applying
# -- the preview describes what will happen, it does not authorize it.
class TeamManagement::BulkPositionChange
  # Statuses this page refuses to touch, from upstream's
  # BulkPositionGrantRevoke. A locked status means the person is out; past
  # prospective means they never got in.
  BLOCKED_STATUSES = (Person::LOCKED_STATUSES + [Person::PAST_PROSPECTIVE]).freeze

  # Every verdict a line can draw, and which of the three buckets it lands in.
  # Upstream has only two -- anything that is not a write is an error -- which
  # paints "already has it" red on the ordinary case of re-running a list.
  # Unchanged is its own bucket here, and only a line that cannot be acted on
  # at all counts as a problem.
  CATEGORY = {
    grant: :changing,
    revoke: :changing,
    already_granted: :skipping,
    already_revoked: :skipping,
    duplicate: :skipping,
    not_found: :problem,
    ambiguous: :problem,
    self_change: :problem,
    blocked_status: :problem
  }.freeze

  # One line of the pasted list. `raw` is kept for the lines that match no one:
  # the reader needs to see what they typed to find the typo.
  Entry = Struct.new(:raw, :person, :verdict, :category, :message) do
    def callsign = person&.callsign || raw
  end

  Outcome = Struct.new(:changed, :failed, :reasons, keyword_init: true) do
    def failed? = failed.any?
  end

  # @param position [Position] the one position being granted or revoked
  # @param grant [Boolean] true to grant, false to revoke
  # @param callsigns [String] newline-separated list, as pasted
  def initialize(position:, grant:, callsigns:)
    @position = position
    @grant = grant
    # Normalized once, here, because both the lookup and the duplicate check
    # key on it. A line that normalizes to nothing -- blank, or punctuation
    # only, like the "---" separators that come with a pasted list -- is
    # dropped rather than reported as a missing callsign, which is what
    # upstream does and what stops it matching an empty callsign_normalized.
    pairs = callsigns.to_s.split("\n")
                     .map { |line| [line.strip, WordUtils.normalize_word(line)] }
                     .reject { |_line, key| key.blank? }
    @lines = pairs.map(&:first)
    @keys = pairs.map(&:last)
  end

  attr_reader :position

  def grant? = @grant

  def entries = @entries ||= build_entries

  def changing = bucket(:changing)

  def skipping = bucket(:skipping)

  def problems = bucket(:problem)

  # Each person is applied in their own transaction, so a failure part way
  # through cannot leave one of them half-changed and the rest of the batch is
  # still attempted. PersonPosition.add_ids_to_person raises on a position
  # whose roles the actor may not confer; the controller filters those out
  # before ever offering the position, and this rescue is what keeps a race
  # against a role revocation from 500ing mid-batch.
  def apply!
    changed = []
    failed = []
    reasons = []

    changing.each do |entry|
      ActiveRecord::Base.transaction { apply_to(entry.person) }
      changed << entry
    rescue StandardError => e
      Rails.logger.error("Bulk position #{verb} failed for person #{entry.person.id}: #{e.class}: #{e.message}")
      failed << entry
      reasons << e.message
    end

    Outcome.new(changed:, failed:, reasons: reasons.uniq)
  end

  private

  def verb = grant? ? "grant" : "revoke"

  # Upstream's action-log reason strings, unchanged: the same page in the
  # Laravel client writes these, and person history reads both.
  def reason = "bulk position #{verb}"

  def bucket(name) = entries.select { |entry| entry.category == name }

  # Two queries for the whole list. Upstream runs one SELECT per line, which a
  # 300-callsign paste turns into 300 round trips.
  #
  # Grouped rather than Person.find_all_by_callsigns, which indexes by
  # callsign_normalized -- a column with no unique index -- and so silently
  # keeps only the last of two people whose callsigns normalize alike. Here
  # both come back and the line is refused instead of landing on a guess.
  def build_entries
    matches = Person.where(callsign_normalized: @keys)
                    .group_by { |person| person.callsign_normalized.downcase }
    held = PersonPosition.where(position_id: position.id,
                                person_id: matches.values.flatten.map(&:id))
                         .pluck(:person_id).to_set
    seen = Set.new

    @lines.zip(@keys).map { |line, key| classify(line, matches[key] || [], key, held, seen) }
  end

  # Duplicates are caught before anything else, so a callsign repeated on two
  # lines is one verdict and not two -- otherwise a typo pasted twice counts as
  # two problems and the preview argues for a fix that is a single edit.
  # Set#add? answers nil for a value already present.
  def classify(line, found, key, held, seen)
    return entry(line, found.first, :duplicate, "Listed more than once") unless seen.add?(key)
    return entry(line, nil, :not_found, "Callsign not found") if found.empty?
    return entry(line, nil, :ambiguous, "More than one person matches that callsign") if found.many?

    person = found.first

    # No one hands themselves a position here. Every role the position carries
    # would land on the actor, which is the one grant no one else reviews.
    if person.id == Current.person&.id
      return entry(line, person, :self_change, "You cannot change your own positions here")
    end

    if BLOCKED_STATUSES.include?(person.status)
      return entry(line, person, :blocked_status,
                   "Status is #{person.status} — this page cannot change their positions")
    end

    holds = held.include?(person.id)
    if grant?
      holds ? entry(line, person, :already_granted, "Already has this position")
            : entry(line, person, :grant, nil)
    else
      holds ? entry(line, person, :revoke, nil)
            : entry(line, person, :already_revoked, "Does not have this position")
    end
  end

  def entry(raw, person, verdict, message)
    Entry.new(raw, person, verdict, CATEGORY.fetch(verdict), message)
  end

  # Both writers already record an ActionLog and a PersonPositionLog, and clear
  # the person's cached role set; revoking also drops their future sign-ups for
  # the position.
  def apply_to(person)
    if grant?
      PersonPosition.add_ids_to_person(person.id, [position.id], reason)
    else
      PersonPosition.remove_ids_from_person(person.id, [position.id], reason)
    end
  end
end
