# frozen_string_literal: true

# One year of the event, counted: who signed up, who rangered, how the Alphas
# fared, and how many people finished a training.
#
# Every count here is people unless its name says entries. "Rangered" means a
# timesheet entry on a position that is neither Alpha nor a training, which is
# the same exclusion the sign-up estimates use, so the two can be compared.
class EventStatsReport
  # The turnout half of the page. Every field is a count of people except
  # timesheet_entries, and on_site, which is nil for a past year -- the flag it
  # counts is live, so only the current year has an honest answer.
  Turnout = Data.define(:people_rangered, :estimated_people, :estimated_returning,
                        :shiny_pennies_rangered, :shiny_pennies_not_rangered,
                        :timesheet_entries, :on_site) do
    def rangered_share = EventStatsReport.share(people_rangered, estimated_people)

    def returning_share = EventStatsReport.share(estimated_returning, estimated_people)

    # The denominator the Shiny Penny bar divides. Normally the number of Alphas
    # who passed, which is where shiny_pennies_not_rangered comes from. If more
    # people were minted and rangered than have a passing mentor record, the
    # floor below leaves this equal to shiny_pennies_rangered instead, and the
    # bar reads full while the page's own "Alphas passed" says less. Preferred
    # to the alternative of printing a negative count of people.
    def shiny_pennies_minted = shiny_pennies_rangered + shiny_pennies_not_rangered

    def shiny_penny_share = EventStatsReport.share(shiny_pennies_rangered, shiny_pennies_minted)
  end

  # The Alpha half. walked is everyone with a mentor record for the year;
  # passed, bonked, and walking split that group three ways.
  Alphas = Data.define(:timesheet_entries, :walked, :passed, :bonked, :walking) do
    def passed_share = EventStatsReport.share(passed, walked)

    def bonked_share = EventStatsReport.share(bonked, walked)

    def walking_share = EventStatsReport.share(walking, walked)
  end

  # One training's row. passed and taught overlap -- a trainer who also sat a
  # session appears in both -- so people is the merged set, not the sum. share
  # is this training against the biggest one of the year, for its bar.
  Training = Data.define(:title, :passed, :taught, :people, :share)

  # people_trained is its own count, not the sum of the rows: somebody who
  # finished an ART as well as In-Person Training belongs to both rows and to
  # the headline once.
  Result = Data.define(:turnout, :alphas, :trainings, :people_trained) do
    # Nothing happened that year, or nothing was recorded. The page says so
    # rather than printing a screen of zeroes.
    def empty?
      turnout.timesheet_entries.zero? && turnout.estimated_people.zero? &&
        alphas.walked.zero? && trainings.empty?
    end
  end

  # Mentor records that mean the Alpha did not pass.
  BONKED_STATUSES = [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].freeze

  # Every position type that is not a training, listed out rather than excluded.
  # Asking SQL for "type is not Training" quietly drops the positions carrying no
  # type at all, and those are ordinary shifts that belong in these counts.
  NON_TRAINING_TYPES = (Position::TYPES - [Position::TYPE_TRAINING] + [nil]).freeze

  class << self
    # @param year [Integer]
    # @return [Result]
    def execute(year:)
      alpha_ids = alpha_person_ids(year)
      alphas = build_alphas(year)
      trainings, people_trained = build_trainings(year)

      Result.new(turnout: build_turnout(year, alpha_ids, alphas.passed),
                 alphas:, trainings:, people_trained:)
    end

    # One number's share of another as a whole percent, clamped to the range a
    # progress bar can draw. Zero out of zero is zero, not a division error.
    #
    # @param part [Integer]
    # @param whole [Integer]
    # @return [Integer] 0..100
    def share(part, whole)
      return 0 if whole.to_i.zero?

      ((part.to_f / whole) * 100).round.clamp(0, 100)
    end

    private

    # Everyone who held an Alpha entry that year: this year's Alphas, whether or
    # not they went on to pass.
    def alpha_person_ids(year)
      Timesheet.for_year(year).where(position_id: Position::ALPHA).distinct.pluck(:person_id)
    end

    def build_turnout(year, alpha_ids, alphas_passed)
      shiny_pennies = shiny_pennies_rangered(year, alpha_ids)

      Turnout.new(
        people_rangered: rangered_scope(year).distinct.count(:person_id),
        estimated_people: signup_scope(year).distinct.count(:person_id),
        estimated_returning: returning_signups(year, alpha_ids),
        shiny_pennies_rangered: shiny_pennies,
        # A difference between two counts, not a set of people -- see the note
        # the page carries. Floored at zero so the page can never print a
        # negative number of people.
        shiny_pennies_not_rangered: [alphas_passed - shiny_pennies, 0].max,
        timesheet_entries: Timesheet.for_year(year).count,
        on_site: (Person.where(on_site: true).count if year == Current.year)
      )
    end

    def build_alphas(year)
      mentored = PersonMentor.where(mentor_year: year, position_id: Position::ALPHA)

      Alphas.new(
        timesheet_entries: Timesheet.for_year(year).where(position_id: Position::ALPHA).count,
        walked: mentored.distinct.count(:person_id),
        passed: mentored.where(status: PersonMentor::STATUS_PASS).distinct.count(:person_id),
        bonked: mentored.where(status: BONKED_STATUSES).distinct.count(:person_id),
        walking: mentored.where(status: PersonMentor::STATUS_PENDING).distinct.count(:person_id)
      )
    end

    # Timesheet entries that count as rangering: not Alpha, and not a training.
    def rangered_scope(year)
      Timesheet.for_year(year)
               .joins(:position)
               .where.not(position_id: Position::ALPHA)
               .where(position: { type: NON_TRAINING_TYPES })
    end

    # Sign-ups for the same kind of shift, which is what makes the estimate
    # comparable to the count of people who actually rangered.
    #
    # Every sign-up counts, including one left on a shift since deactivated:
    # somebody who put their name down is somebody who might turn up, whatever
    # later became of that particular slot. Deliberate, and the reason no
    # `active` filter appears here.
    def signup_scope(year)
      PersonSlot.joins(slot: :position)
                .where(slot: { begins_year: year })
                .where.not(slot: { position_id: Position::ALPHA })
                .where(position: { type: NON_TRAINING_TYPES })
    end

    # The same estimate without this year's Alphas, leaving the Rangers who have
    # already been through a season.
    def returning_signups(year, alpha_ids)
      scope = signup_scope(year)
      scope = scope.where.not(person_slot: { person_id: alpha_ids }) if alpha_ids.any?
      scope.distinct.count(:person_id)
    end

    # Alphas who became active during the year and then took a shift of their
    # own. The status change is what separates a new Shiny Penny from an Alpha
    # who was already active for some other reason.
    def shiny_pennies_rangered(year, alpha_ids)
      return 0 if alpha_ids.empty?

      minted = PersonStatus.all.where_year("created_at", year)
                           .where(new_status: Person::ACTIVE)
                           .select(:person_id)

      rangered_scope(year).where(person_id: alpha_ids).where(person_id: minted)
                          .distinct.count(:person_id)
    end

    # One row per training that trained somebody this year, biggest first,
    # alongside the number of distinct people the whole set covers.
    #
    # Both halves are keyed off the session slot, so a training's row collects
    # its trainees and its trainers alike. That also keeps the trainer positions
    # out on their own: they are type Training too, but a trainer signs up to
    # one and is never trained by it.
    #
    # @return [Array(Array<Training>, Integer)]
    def build_trainings(year)
      passed = people_by_position(TraineeStatus.passed, year)
      taught = people_by_position(
        TrainerStatus.where(status: TrainerStatus::STATUS_ATTENDED), year
      )

      everyone = Set.new
      counted = training_titles(passed.keys | taught.keys).map do |position_id, title|
        trainees = passed[position_id] || Set.new
        trainers = taught[position_id] || Set.new
        people = trainees | trainers
        everyone.merge(people)
        [title, trainees.size, trainers.size, people.size]
      end.sort_by { |title, _, _, people| [-people, title] }

      largest = counted.first&.last || 0
      rows = counted.map do |title, trainees, trainers, people|
        Training.new(title:, passed: trainees, taught: trainers, people:,
                     share: share(people, largest))
      end

      [rows, everyone.size]
    end

    # { session position id => Set of person ids } for one kind of status record.
    def people_by_position(scope, year)
      scope.joins(:slot)
           .where(slot: { begins_year: year, active: true })
           .pluck("slot.position_id", :person_id)
           .each_with_object({}) do |(position_id, person_id), by_position|
             (by_position[position_id] ||= Set.new) << person_id
           end
    end

    # The name each training goes by on the page. Position::TRAINING is titled
    # plain "Training" in the database, which says nothing next to the ARTs.
    def training_titles(position_ids)
      Position.where(id: position_ids).pluck(:id, :title).to_h do |id, title|
        [id, (id == Position::TRAINING) ? "In-Person Training" : title]
      end
    end
  end
end
