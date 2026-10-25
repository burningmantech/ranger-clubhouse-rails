# frozen_string_literal: true

# The Alpha Acceptance Sheets' data layer: this year's Alpha roster with
# everything the picker table and the printed acceptance form need.
# (Upstream Laravel app/Lib/Alpha.php -- retrieveAllAlphas, buildPerson,
# loadAlphaContext, populateIntakeTeams, evaluateEligibility.)
#
# The roster is a CURRENT-STANDING snapshot: everyone whose status is Alpha
# right now, exactly as upstream's mentor/alphas endpoint reads it. The year is
# not a filter on people -- it only scopes the trained check, the Alpha shift
# sign-ups, and how far the intake notes reach back.
class AlphaAcceptanceSheets
  # The three things upstream's Errors column checks before an Alpha is ready
  # to be walked. Strings rather than symbols: the table prints them verbatim
  # and the sheet never re-words them.
  NO_TRAINING = "No training sign-ups"
  NOT_TRAINED = "Did not pass training"
  NO_ALPHA_SHIFT = "No mentor shift"

  # The filter sentinels and the printed form's signature-row count live here,
  # where the controller, the helper, and the sheet can all read them: a helper
  # that reaches for a controller constant at load time deadlocks the two
  # autoloads against each other.
  #
  # The shift filter's value is a slot id, or NO_SHIFT for Alphas signed up to
  # nothing (upstream's "No Mentor Shift" option).
  NO_SHIFT = "none"
  WITHOUT_ISSUES = "without"
  WITH_ISSUES = "with"

  # Blank signature rows on the printed form. Upstream prints three; a pod
  # rarely runs larger, and a fourth mentor writes in the margin.
  MENTOR_SIGNOFF_ROWS = 3

  # One Alpha. `trainings` is the person's whole Dirt training history (upstream
  # lists all of it, not just this year's), while `trained` is the year-scoped
  # verdict -- a pass in an earlier year does not make someone trained now.
  # `vc_team` and `mentor_team` are the year-by-year intake ranks and notes the
  # form's comment boxes print; `mentor_years` is the separate prior-mentors
  # history from person_mentor.
  Entry = Data.define(:person, :trainings, :alpha_slots, :mentor_years,
                      :vc_team, :mentor_team, :trained) do
    # Upstream's Errors column, in its order. A person with none of these is
    # ready to be handed a form.
    def issues
      [
        (NO_TRAINING if trainings.empty?),
        (NOT_TRAINED unless trained),
        (NO_ALPHA_SHIFT if alpha_slots.empty?)
      ].compact
    end

    def issues? = issues.any?

    # The form's Training Notes box covers passed sessions only -- upstream
    # guards the whole block on training_passed, so an unpassed session shows
    # in Training Location and nowhere else.
    def passed_trainings = trainings.select(&:training_passed)
  end

  class << self
    # Every current Alpha, callsign-sorted, carrying both the picker table's
    # columns and the printed form's fields. One roster is tens of people and
    # every source is bulk-loaded, so the query count is flat in roster size.
    #
    # @param year [Integer] scopes the trained check, Alpha shifts, and note cap
    # @param person_ids [Array<Integer>, nil] narrows the roster to a printed
    #   selection. Ids that are not current Alphas simply drop out, which is
    #   what keeps a hand-edited print URL to the page's own roster.
    # @return [Array<Entry>]
    def for_year(year, person_ids: nil)
      people = roster_people(person_ids)
      return [] if people.empty?

      context = load_context(people.map(&:id), year)
      people.map { |person| build_entry(person, year, context) }
    end

    private

    # Upstream's `Person::where('status', ALPHA)->orderBy('callsign')`. Sorted
    # in Ruby, case-insensitively, the way every sibling roster in this app
    # sorts callsigns -- MySQL's collation sort is case-insensitive too, so this
    # matches upstream's output without depending on the column's collation.
    def roster_people(person_ids)
      scope = Person.where(status: Person::ALPHA)
      scope = scope.where(id: person_ids) if person_ids

      # Only the photo is preloaded: formerly_known_as_array re-queries through
      # order(...).pluck, so an :person_fka preload would be paid for and thrown away.
      scope.includes(:profile_photo_attachment)
           .to_a
           .sort_by { |person| person.callsign.to_s.downcase }
    end

    # Upstream's loadAlphaContext, one query per source.
    def load_context(person_ids, year)
      {
        # Ranks are NOT year-capped -- upstream's retrieveIntakeHistory loads
        # every year and caps only the notes, one line below.
        intakes: PersonIntake.where(person_id: person_ids)
                             .order(:year).group_by(&:person_id),
        # Both teams the form prints, and only those: it has a VC box and a
        # Mentor box, so the other two teams' rows would be loaded and dropped.
        # Log notes are audit entries the form never prints (upstream renders
        # the same `unless is_log` guard), so they are filtered in SQL.
        notes: PersonIntakeNote.where(person_id: person_ids, is_log: false, type: %w[vc mentor])
                               .where(year: ..year)
                               .order(:created_at).group_by(&:person_id),
        trainings: Training.retrieve_training_history_for_ids(person_ids, Position::TRAINING, year),
        alpha_slots: alpha_slots_by_person(person_ids, year),
        mentorships: PersonMentor.retrieve_all_mentors_for_ids(person_ids, position_id: Position::ALPHA)
      }
    end

    # This year's Alpha shift sign-ups per person, earliest first. Inactive
    # shifts count: upstream's active filter is a no-op (its controller
    # validates `is_active` while the query reads `active`, so the parameter
    # never survives validation) and a sign-up on a dormant shift is still a
    # sign-up.
    def alpha_slots_by_person(person_ids, year)
      PersonSlot.eager_load(:slot)
                .where(person_id: person_ids,
                       slot: { position_id: Position::ALPHA, begins_year: year })
                .order("slot.begins")
                .group_by(&:person_id)
                .transform_values { |rows| rows.map(&:slot) }
    end

    def build_entry(person, year, context)
      trainings = context[:trainings][person.id] || []
      intakes = context[:intakes][person.id] || []
      notes = context[:notes][person.id] || []

      Entry.new(
        person:,
        trainings:,
        alpha_slots: context[:alpha_slots][person.id] || [],
        # Most recent mentoring year first, as upstream's retrieveMentorHistory
        # sorts it -- the last verdict is the one a mentor reads first.
        mentor_years: PersonMentor.history_rows(context[:mentorships][person.id] || {}).reverse,
        vc_team: Intake.build_intake_team("vc", intakes, notes),
        mentor_team: Intake.build_intake_team("mentor", intakes, notes),
        # Upstream's evaluateEligibility: this year's session, and passed.
        trained: trainings.any? { |t| t.slot_year == year && t.training_passed }
      )
    end
  end
end
