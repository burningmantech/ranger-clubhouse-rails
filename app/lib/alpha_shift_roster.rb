# frozen_string_literal: true

# The Alpha Schedule's data layer: a year's Alpha shifts for the index, and one
# shift's full roster for the shift page and its three printable sheets.
# (Upstream Laravel app/Lib/Alpha.php -- retrieveAlphaScheduleForYear,
# loadAlphaContext, buildPerson, populateIntakeTeams.)
#
# Two deliberate departures from upstream:
#
#   * The year every lookup hangs off is the SLOT's year, not the request's.
#     Upstream's apparel sheet reads the mentor status for `current_year()`, so
#     printing a past shift's sheet marks the whole roster "pending"; a sheet
#     describes its own shift whenever it is printed.
#   * Inactive slots are included (the index badges them). Upstream's schedule
#     query has no active filter either, but its sibling report here chose
#     active-only, so the difference is worth naming.
class AlphaShiftRoster
  # A mentor rank at or above this is what upstream's have_mentor_flags means
  # and what its roster column renders (`gte info.rank 3`).
  FLAG_RANK = Intake::BELOW_AVERAGE

  # Upstream's apparel split: anyone not passing or still pending is BONKED.
  PASSING_STATUSES = [PersonMentor::STATUS_PASS, PersonMentor::STATUS_PENDING].freeze

  # Who may be signed up for an Alpha shift at all. Upstream states this in
  # its add dialog and never enforces it; here it is the rule both the
  # dialog and the write path read, so they cannot disagree.
  ADDABLE_STATUSES = [Person::ALPHA, Person::PROSPECTIVE].freeze

  def self.addable?(person)
    ADDABLE_STATUSES.include?(person.status)
  end

  # A shift's headline numbers for the index cards. `signed_in` counts sign-ups
  # on an open Alpha timesheet right now, so a past year's shifts read 0.
  Shift = Data.define(:slot, :signed_up, :signed_in) do
    def full? = slot.max.to_i.positive? && signed_up >= slot.max.to_i
  end

  # One person on one Alpha shift. `mentor_team` is the mentor team's whole
  # year-by-year intake history (rank and notes, as the information sheet
  # prints it) and `flags` is the subset of it worth a warning, so the two can
  # never disagree. `mentor_years` is the separate prior-mentors history.
  Entry = Data.define(:person, :signed_in, :mentor_team, :trainings,
                      :mentor_years, :mentor_status) do
    def signed_in? = signed_in
    def flags = mentor_team.select { |team_year| team_year[:rank].to_i >= FLAG_RANK }
    def flagged? = flags.any?
    def bonked? = !PASSING_STATUSES.include?(mentor_status)
  end

  # Data instances are frozen, so these derive rather than memoize -- the
  # walks are over one shift's sign-ups (tens, not thousands). Everything
  # signed-in reads through #signed_in so the count and the list cannot drift.
  Roster = Data.define(:slot, :entries) do
    def signed_in = entries.select(&:signed_in?)
    def signed_in_count = signed_in.size
    def any_signed_in? = signed_in.any?
    def flagged_count = entries.count(&:flagged?)
  end

  class << self
    # The year's Alpha shifts with their counts, earliest first. Inactive slots
    # are kept -- a dormant shift that still has sign-ups is what a mentor lead
    # opens this page to catch.
    def shifts_for_year(year)
      slots = Slot.for_year(year).for_position(Position::ALPHA).ordered_by_begins.to_a
      return [] if slots.empty?

      # Counted from the sign-up rows, NOT from slot.signed_up. That counter
      # is only bumped by the scheduling write path, so anything writing
      # person_slot directly leaves it stale -- and a card disagreeing with
      # the roster page it links to is worse than one more grouped count.
      signed_up_by_slot = PersonSlot.where(slot_id: slots.map(&:id)).group(:slot_id).count
      signed_in_by_slot = signed_in_counts(slots)

      slots.map do |slot|
        Shift.new(slot:,
                  signed_up: signed_up_by_slot[slot.id] || 0,
                  signed_in: signed_in_by_slot[slot.id] || 0)
      end
    end

    # One shift's roster, callsign-sorted, carrying everything the shift page
    # and all three sheets need. Every source is loaded in bulk, so the query
    # count is flat in roster size -- but it is not small (the training
    # history alone is several), so prefer passing a Roster around over
    # calling this twice for one request.
    def for_slot(slot)
      people = roster_people(slot)
      return Roster.new(slot:, entries: []) if people.empty?

      year = slot.begins_year
      person_ids = people.map(&:id)
      context = load_context(person_ids, year)

      entries = people.map { |person| build_entry(person, year, context) }
      Roster.new(slot:, entries:)
    end

    private

    # How many of each shift's sign-ups are on an open Alpha timesheet right
    # now. Driven from the on-duty side because that set is tiny (no one, most
    # of the year) while the sign-ups are not.
    def signed_in_counts(slots)
      on_duty_ids = Timesheet.retrieve_signed_in_people(Position::ALPHA).keys
      return {} if on_duty_ids.empty?

      PersonSlot.where(slot_id: slots.map(&:id), person_id: on_duty_ids)
                .group(:slot_id).count
    end

    def roster_people(slot)
      slot.sign_ups
          .includes(:tshirt_swag, :tshirt_secondary_swag, :long_sleeve_swag)
          .to_a
          .sort_by { |person| person.callsign.to_s.downcase }
    end

    # Upstream's loadAlphaContext, one query per source.
    def load_context(person_ids, year)
      {
        intakes: PersonIntake.where(person_id: person_ids).where(year: ..year)
                             .order(:year).group_by(&:person_id),
        # Only the mentor team's notes are ever read here, and build_intake_team
        # discards the rest in Ruby -- so filter in SQL and skip preloading
        # authors this page will never print.
        notes: PersonIntakeNote.where(person_id: person_ids, is_log: false, type: "mentor")
                               .where(year: ..year)
                               .includes(:person_source)
                               .order(:created_at).group_by(&:person_id),
        trainings: Training.retrieve_training_history_for_ids(person_ids, Position::TRAINING, year),
        mentorships: PersonMentor.retrieve_all_mentors_for_ids(person_ids, position_id: Position::ALPHA),
        on_duty: Timesheet.retrieve_signed_in_people(Position::ALPHA)
      }
    end

    def build_entry(person, year, context)
      mentorships = context[:mentorships][person.id] || {}

      Entry.new(
        person:,
        signed_in: context[:on_duty].key?(person.id),
        mentor_team: Intake.build_intake_team("mentor",
                                              context[:intakes][person.id] || [],
                                              context[:notes][person.id] || []),
        trainings: context[:trainings][person.id] || [],
        mentor_years: PersonMentor.history_rows(mentorships),
        mentor_status: mentorships.dig(year, :status) || PersonMentor::STATUS_PENDING
      )
    end
  end
end
