# frozen_string_literal: true

# Everyone holding the Sandman position, and whether they may stand a Sandman
# shift for an event year.
#
# Up to three things have to be true before someone counts as qualified: they
# passed this year's training, they signed the affidavit, and they have rangered
# a burn perimeter shift recently. The last two are switched on and off by the
# Clubhouse's own settings, and the report asks those settings rather than
# deciding for itself -- a rule that cannot keep anybody off a shift has no
# business marking them unqualified here.
#
# Being signed up for a shift is reported alongside the checks but is never one
# of them: the question the page exists to answer is who holds a shift they
# cannot yet stand.
class SandmanQualifiedReport
  # What each check is called when it is the one somebody is missing.
  CHECK_NAMES = { trained: "training", affidavit: "affidavit",
                  experience: "experience" }.freeze

  # One person and their answers. `required` names the checks in force, so a
  # row can tell what it is being measured against.
  Row = Struct.new(:person, :trained, :affidavit, :experience, :signed_up,
                   :required) do
    def person_id = person.id
    def callsign = person.callsign

    def qualified? = required.all? { |check| self[check] }

    # Ready, and holding a shift to stand.
    def qualified_signed_up? = signed_up && qualified?

    # Holding a shift they cannot yet stand. This is the row the page exists to
    # surface, so it is named once here rather than spelled out by each reader.
    def unqualified_signed_up? = signed_up && !qualified?

    # What is still missing, named the way the page's columns are.
    def missing
      required.reject { |check| self[check] }.map { |check| CHECK_NAMES.fetch(check) }
    end
  end

  # The whole report. The counts live here rather than in the page so the
  # scoreboard, the filters, and the summary line cannot drift apart.
  #
  # Every figure is counted once, in a single walk of the list. The page asks
  # for most of them more than once -- the summary line and the scoreboard both
  # want the qualified -- and each answer is settled the moment the report is
  # built, so no amount of asking walks the roster again.
  Result = Struct.new(:rows, :cutoff_year, :required) do
    # Which checks the page should show a column and a box for. A check no one
    # is enforcing is left off the page entirely rather than printed as a
    # shortfall for somebody to chase.
    def affidavit_required? = required.include?(:affidavit)
    def experience_required? = required.include?(:experience)

    def total = counts[:total]
    def trained_count = counts[:trained]
    def affidavit_count = counts[:affidavit]
    def experience_count = counts[:experience]
    def signed_up_count = counts[:signed_up]
    def qualified_count = counts[:qualified]
    def qualified_signed_up_count = counts[:qualified_signed_up]
    def unqualified_signed_up_count = counts[:unqualified_signed_up]

    private

    def counts
      @counts ||= rows.each_with_object(Hash.new(0)) { |row, tally|
        tally[:total] += 1
        tally[:trained] += 1 if row.trained
        tally[:affidavit] += 1 if row.affidavit
        tally[:experience] += 1 if row.experience
        tally[:signed_up] += 1 if row.signed_up
        tally[:qualified] += 1 if row.qualified?
        tally[:qualified_signed_up] += 1 if row.qualified_signed_up?
        tally[:unqualified_signed_up] += 1 if row.unqualified_signed_up?
      }
    end
  end

  class << self
    # Every sandman and their answers for the year, in callsign order.
    def build(year:)
      affidavit_required = Setting.get_value(Setting::SANDMAN_REQUIRE_AFFIDAVIT)
      cutoff_year = experience_cutoff_year(year)

      # Training is always asked for. The other two are only asked for while the
      # Clubhouse is set to ask for them.
      required = [:trained]
      required << :affidavit if affidavit_required
      required << :experience if cutoff_year

      people = sandpeople

      return Result.new([], cutoff_year, required) if people.empty?

      person_ids = people.map(&:id)
      trained = trained_person_ids(year:, person_ids:)
      # A check no one is enforcing is not worth a trip to the database.
      affidavit = affidavit_required ? affidavit_person_ids(year:, person_ids:) : Set.new
      experience = cutoff_year ? experienced_person_ids(year:, cutoff_year:, person_ids:) : Set.new
      signed_up = signed_up_person_ids(year:, person_ids:)

      rows = people.map { |person|
        id = person.id
        Row.new(person, trained.include?(id), affidavit.include?(id),
                experience.include?(id), signed_up.include?(id), required)
      }

      Result.new(rows, cutoff_year, required)
    end

    private

    # The earliest year a burn perimeter shift still counts for, or nil when
    # there is no window to ask about.
    #
    # Read exactly the way the sign-in check reads it, so the two cannot
    # disagree about who may stand a shift. Note that a blank setting arrives
    # here as nought rather than as nothing, which asks for a shift in the
    # report's own year -- the same thing it asks of anyone signing in.
    def experience_cutoff_year(year)
      within_years = Setting.get_value(Setting::SANDMAN_REQUIRE_PERIMETER_EXP_WITHIN_YEARS)
      return nil if within_years.blank?

      year - within_years.to_i
    end

    # The people the report is about: active accounts granted the Sandman
    # position. Status and position grants are read as they stand today, so an
    # earlier year shows today's sandmen against that year's answers.
    #
    # Only the strictly active are listed. Someone who has gone inactive or
    # retired is not standing a burn this year, and listing them would pad
    # every count with people no one is going to chase.
    # Only the two columns the page prints are read: the rest of a person row is
    # of no use to a roster of callsigns.
    #
    # Distinct because the grant table carries no rule against holding the same
    # position twice, and a person listed twice would be counted twice in every
    # figure above the table.
    def sandpeople
      Person.where(status: Person::ACTIVE)
            .joins(:person_position)
            .where(person_position: { position_id: Position::SANDMAN })
            .select(:id, :callsign)
            .distinct
            .order(:callsign)
            .to_a
    end

    # Sitting this year's training and teaching it both count.
    def trained_person_ids(year:, person_ids:)
      (passed_person_ids(year:, person_ids:) +
        trainer_person_ids(year:, person_ids:)).to_set
    end

    # Whoever sat this year's training and passed it.
    def passed_person_ids(year:, person_ids:)
      slot_ids = training_slot_ids(year:, position_id: Position::SANDMAN_TRAINING)
      return [] if slot_ids.empty?

      TraineeStatus.passed.where(slot_id: slot_ids, person_id: person_ids)
                   .pluck(:person_id)
    end

    # Whoever turned up to teach this year's training, limited to the people
    # actually holding the trainer position.
    def trainer_person_ids(year:, person_ids:)
      trainer_ids = PersonPosition.where(position_id: Position::SANDMAN_TRAINER,
                                         person_id: person_ids).pluck(:person_id)
      return [] if trainer_ids.empty?

      slot_ids = training_slot_ids(year:, position_id: Position::SANDMAN_TRAINER)
      return [] if slot_ids.empty?

      TrainerStatus.where(trainer_slot_id: slot_ids, person_id: trainer_ids,
                          status: TrainerStatus::STATUS_ATTENDED)
                   .pluck(:person_id)
    end

    # A switched-off session teaches no one, so it cannot train anyone either.
    def training_slot_ids(year:, position_id:)
      Slot.active.for_year(year).for_position(position_id).pluck(:id)
    end

    # A missing row for the year means the affidavit was never signed.
    def affidavit_person_ids(year:, person_ids:)
      PersonEvent.where(year:, person_id: person_ids, sandman_affidavit: true)
                 .pluck(:person_id).to_set
    end

    # Anyone who has stood a burn perimeter shift, or one of its neighbours,
    # inside the years that still count.
    #
    # The window closes at the end of the report's year as well as opening five
    # years before it. Without the closing end, reading an earlier year would
    # credit people for shifts they had not yet rangered. It opens where the
    # sign-in check's window does -- change one boundary and change both.
    def experienced_person_ids(year:, cutoff_year:, person_ids:)
      Timesheet.where(person_id: person_ids, position_id: Position::SANDMAN_QUALIFIED_POSITIONS)
               .where_years("timesheet.on_duty", cutoff_year, year)
               .distinct.pluck(:person_id).to_set
    end

    # Sign-ups count even for a shift that was later switched off: the person
    # still holds it, and it is still on their schedule.
    def signed_up_person_ids(year:, person_ids:)
      PersonSlot.joins(:slot)
                .where(person_id: person_ids)
                .where(slot: { begins_year: year, position_id: Position::SANDMAN })
                .distinct.pluck(:person_id).to_set
    end
  end
end
