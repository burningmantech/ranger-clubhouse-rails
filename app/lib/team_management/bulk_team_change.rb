# frozen_string_literal: true

# What a bulk team grant or revoke will do to a pasted list of callsigns, and
# then the doing of it.
#
# The sibling of BulkPositionChange, and deliberately its twin: one object
# answers both questions, so the preview a manager reads and the apply that
# follows cannot disagree. The controller still rebuilds this object from its
# own params before applying -- the preview describes what will happen, it does
# not authorize it.
#
# A team membership is never moved alone. Granting one also grants the team's
# Recommended positions; revoking one also revokes the Recommended and Optional
# positions. Both sets are named here rather than by the caller, so the sentence
# the preview prints and the write the apply performs come from one place.
class TeamManagement::BulkTeamChange
  # Statuses this page refuses to touch, from upstream's BulkTeamGrantRevoke. A
  # locked status means the person is out; past prospective means they never
  # got in.
  BLOCKED_STATUSES = (Person::LOCKED_STATUSES + [Person::PAST_PROSPECTIVE]).freeze

  # Every verdict a line can draw, and which of the three buckets it lands in.
  # Upstream has only two -- anything that is not a write is an error -- which
  # paints "already a member" red on the ordinary case of re-running a list.
  # Unchanged is its own bucket here, and only a line that cannot be acted on at
  # all counts as a problem.
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

  # @param team [Team] the one team being granted or revoked
  # @param grant [Boolean] true to grant, false to revoke
  # @param callsigns [String] newline-separated list, as pasted
  def initialize(team:, grant:, callsigns:)
    @team = team
    @grant = grant
    # Normalized once, here, because both the lookup and the duplicate check key
    # on it. A line that normalizes to nothing -- blank, or punctuation only,
    # like the "---" separators that come with a pasted list -- is dropped
    # rather than reported as a missing callsign, which is what upstream does
    # and what stops it matching an empty callsign_normalized.
    pairs = callsigns.to_s.split("\n")
                     .map { |line| [line.strip, WordUtils.normalize_word(line)] }
                     .reject { |_line, key| key.blank? }
    @lines = pairs.map(&:first)
    @keys = pairs.map(&:last)
  end

  attr_reader :team

  def grant? = @grant

  def entries = @entries ||= build_entries

  def changing = bucket(:changing)

  def skipping = bucket(:skipping)

  def problems = bucket(:problem)

  # The positions a membership carries in one direction, in title order.
  #
  # Granting adds only the Recommended positions: Optional ones are the member's
  # own choice, and handing them out with the membership would sign people up
  # for roles no one asked them about. Revoking takes both, because someone
  # leaving the team keeps neither -- upstream draws the same asymmetry. A class
  # method as well, so an ART mentoring pass (ArtMentoring::Pass) grants the
  # same set without a pasted list.
  #
  # REVOCABLE_CATEGORIES is the single authority for what leaving a team costs,
  # shared with Roster Management's team removal. Asking for it here rather than
  # respelling the pair keeps the pages from drifting apart.
  def self.positions_for(team, grant:)
    categories = grant ? [Position::TEAM_CATEGORY_ALL_MEMBERS] : TeamMembershipReport::REVOCABLE_CATEGORIES
    Position.where(team_id: team.id, team_category: categories).order(:title).to_a
  end

  def moved_positions = @moved_positions ||= self.class.positions_for(team, grant: grant?)

  # What the controller checks before it lets any of this run: these are the
  # positions whose role grants would move. Memoized because apply! asks once
  # per person.
  def position_ids = @position_ids ||= moved_positions.map(&:id)

  # Each person is applied in their own transaction, so a failure part way
  # through cannot leave someone holding the membership but not its positions,
  # and the rest of the batch is still attempted. PersonPosition and PersonTeam
  # both raise on a grant whose roles the actor may not confer; the controller
  # refuses those before ever building the change, and this rescue is what keeps
  # a race against a role revocation from 500ing mid-batch.
  def apply!
    changed = []
    failed = []
    reasons = []

    changing.each do |entry|
      ActiveRecord::Base.transaction { apply_to(entry.person) }
      changed << entry
    rescue StandardError => e
      Rails.logger.error("Bulk team #{verb} failed for person #{entry.person.id}: #{e.class}: #{e.message}")
      failed << entry
      reasons << e.message
    end

    Outcome.new(changed:, failed:, reasons: reasons.uniq)
  end

  private

  def verb = grant? ? "grant" : "revoke"

  # Upstream's action-log reason strings, unchanged: the same page in the
  # Laravel client writes these, and person history reads both.
  def reason = "bulk team #{verb}"

  # Grouped once rather than re-scanning per call: the preview asks a
  # bucket question about fifteen times per render.
  def bucket(name) = buckets.fetch(name, [])

  def buckets = @buckets ||= entries.group_by(&:category)

  # Two queries for the whole list. Upstream runs one SELECT per line, which a
  # 300-callsign paste turns into 300 round trips.
  #
  # Grouped rather than Person.find_all_by_callsigns, which indexes by
  # callsign_normalized -- a column with no unique index -- and so silently
  # keeps only the last of two people whose callsigns normalize alike. Here both
  # come back and the line is refused instead of landing on a guess.
  #
  # CONSTRAINT: these four columns are every attribute this page reads, and
  # person is 88 columns wide including four LONGTEXTs -- a 300-callsign paste
  # would otherwise haul all of it twice, once to preview and once to apply.
  # Reading any other attribute off Entry#person raises MissingAttributeError;
  # add the column here first.
  def build_entries
    matches = Person.select(:id, :callsign, :callsign_normalized, :status)
                    .where(callsign_normalized: @keys)
                    .group_by { |person| person.callsign_normalized.downcase }
    members = PersonTeam.where(team_id: team.id, person_id: matches.values.flatten.map(&:id))
                        .pluck(:person_id).to_set
    seen = Set.new

    @lines.zip(@keys).map { |line, key| classify(line, matches[key] || [], key, members, seen) }
  end

  # Duplicates are caught before anything else, so a callsign repeated on two
  # lines is one verdict and not two -- otherwise a typo pasted twice counts as
  # two problems and the preview argues for a fix that is a single edit.
  # Set#add? answers nil for a value already present.
  # A repeat carries a person only when the first occurrence resolved to exactly
  # one -- `found.first` on an ambiguous line would name a specific human on a
  # row whose whole point is that the callsign did not identify anybody, and the
  # preview renders a person link the moment there is a person to link.
  def classify(line, found, key, members, seen)
    return entry(line, found.one? ? found.first : nil, :duplicate, "Listed more than once") unless seen.add?(key)
    return entry(line, nil, :not_found, "Callsign not found") if found.empty?
    return entry(line, nil, :ambiguous, "More than one person matches that callsign") if found.many?

    person = found.first

    # No one adds themselves to a team here. Every role the team and its
    # positions carry would land on the actor, which is the one grant no one
    # else reviews.
    if person.id == Current.person&.id
      return entry(line, person, :self_change, "You cannot change your own team memberships here")
    end

    if BLOCKED_STATUSES.include?(person.status)
      return entry(line, person, :blocked_status,
                   "Status is #{person.status} — this page cannot change their memberships")
    end

    member = members.include?(person.id)
    if grant?
      member ? entry(line, person, :already_granted, "Already a member")
             : entry(line, person, :grant, nil)
    else
      member ? entry(line, person, :revoke, nil)
             : entry(line, person, :already_revoked, "Not a member")
    end
  end

  def entry(raw, person, verdict, message)
    Entry.new(raw, person, verdict, CATEGORY.fetch(verdict), message)
  end

  # Membership first on the way in and last on the way out, so the person is
  # never left holding the team's positions without the membership that explains
  # them. Both writers record an ActionLog and clear the person's cached role
  # set; revoking the positions also drops their future sign-ups for each one.
  #
  # Someone who already holds one of the moved positions keeps it on a grant,
  # and a position they never held is not reported as removed on a revoke --
  # both writers ignore the ids that would be no-ops.
  def apply_to(person)
    if grant?
      PersonTeam.add_person(team.id, person.id, reason)
      PersonPosition.add_ids_to_person(person.id, position_ids, reason)
    else
      PersonPosition.remove_ids_from_person(person.id, position_ids, reason)
      PersonTeam.remove_person(team.id, person.id, reason)
    end
  end
end
