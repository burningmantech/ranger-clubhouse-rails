# frozen_string_literal: true

# Ticket holders who have not finished what the ticket was for.
#
# Despite the name it inherited from upstream, sign-ups are not a filter here.
# The rule is: everyone holding a claimed or submitted special price ticket or
# staff credential, minus anyone who *both* completed the online course *and*
# has a timesheet entry this year. Someone with a full schedule still lands on
# the list if they skipped the course; someone with no sign-ups at all does not,
# so long as they finished the course and rangered.
#
# Rangering is read from timesheets, so before the event no one has rangered and every
# claimed ticket holder is listed. This is a during- and after-event follow-up
# report, not a pre-event one.
#
# Port of the Laravel ClaimedTicketsWithNoSignups behind the Ember
# vc/access-documents/claimed-with-no-signups page.
class ClaimedTicketsWithNoSignupsReport
  # documents holds every claimed/submitted ticket the person has, so someone
  # with both an SPT and a staff credential is one row rather than two.
  Row = Data.define(:person, :documents, :oc_completed, :has_signups, :rangered, :trainings) do
    # Passed a training session, or turned up to teach one.
    def trained?
      trainings.any?(&:counts_as_trained)
    end
  end

  # One training session the person signed up for, as trainee or as trainer.
  # Upstream drew these as two parallel columns the reader had to scan in
  # lockstep; they are one sorted list here, with the status carrying the role.
  TrainingSession = Data.define(:begins, :status, :counts_as_trained) do
    # Reads come back cast into Time.zone, an hour ahead of the stored wall
    # clock for half the year; getlocal returns to the clock the session was
    # scheduled against.
    def begins_label
      begins.getlocal.strftime(DateTimeHelper::MONTH_DAY_TIME)
    end
  end

  # What an ended session's stored verdict prints as. A session no one scored
  # reads "not passed", as it always has.
  TRAINEE_VERDICTS = {
    TraineeStatus::STATUS_PASSED => "passed",
    TraineeStatus::STATUS_NO_SHOW => "no-show",
    TraineeStatus::STATUS_NOT_PASSED => "not passed"
  }.freeze

  # The statuses that mean the person took the ticket. A qualified ticket has
  # been earned but not accepted, so its holder has promised nothing yet.
  CLAIMED_STATUSES = [AccessDocument::CLAIMED, AccessDocument::SUBMITTED].freeze

  # @param year [Integer]
  # @return [Array<Row>] sorted by callsign, case-insensitively
  def self.execute(year)
    new(year).execute
  end

  def initialize(year)
    @year = year
  end

  def execute
    return [] if documents_by_person.empty?

    signed_up = signed_up_ids
    rangered_people = rangered_ids
    completed = completed_oc_ids
    sessions = training_sessions

    documents_by_person.filter_map { |person_id, documents|
      oc_completed = completed.include?(person_id)
      rangered = rangered_people.include?(person_id)

      # Course finished and shifts rangered — nothing left to chase.
      next if oc_completed && rangered

      Row.new(person: documents.first.person, documents:, oc_completed:, rangered:,
              has_signups: signed_up.include?(person_id),
              trainings: sessions[person_id] || [])
    }.sort_by { |row| row.person.callsign.downcase }
  end

  private

  # Documents whose person has since been deleted are dropped rather than
  # rendered as a blank row.
  def documents_by_person
    @documents_by_person ||=
      AccessDocument.where(type: AccessDocument::REGULAR_TICKET_TYPES, status: CLAIMED_STATUSES)
                    .includes(:person)
                    .to_a
                    .select(&:person)
                    .group_by(&:person_id)
  end

  def person_ids
    @person_ids ||= documents_by_person.keys
  end

  # Training sign-ups do not count: showing up to be trained is not the same as
  # showing up to ranger. Collected as ids rather than joined so the comparison
  # stays NULL-safe — a position with no type set would drop out of a
  # `type != 'Training'` join, which is how upstream wrote it.
  def training_position_ids
    @training_position_ids ||= Position.where(type: Position::TYPE_TRAINING).pluck(:id)
  end

  # A shift starting on or after the cutoff. The date lives in the sibling
  # report, which is the only place it is defined.
  def signed_up_ids
    PersonSlot.joins(:slot)
              .where(person_id: person_ids)
              .where(slot: { begins_year: @year,
                             begins: UnclaimedTicketsWithSignupsReport.signup_cutoff(@year).. })
              .where.not(slot: { position_id: training_position_ids })
              .distinct
              .pluck(:person_id)
              .to_set
  end

  def rangered_ids
    Timesheet.for_year(@year).where(person_id: person_ids).distinct.pluck(:person_id).to_set
  end

  # An enrollment row alone is not completion — Moodle sync creates one when
  # the person starts. completed_at is what the rest of the app checks.
  def completed_oc_ids
    PersonOnlineCourse.where(person_id: person_ids, year: @year, position_id: Position::TRAINING)
                      .where.not(completed_at: nil)
                      .distinct
                      .pluck(:person_id)
                      .to_set
  end

  # @return [Hash{Integer => Array<TrainingSession>}] sorted by start time
  def training_sessions
    (trainee_sessions + trainer_sessions)
      .group_by(&:first)
      .transform_values { |pairs| pairs.map(&:last).sort_by(&:begins) }
  end

  # A session is only settled once it has ended; until then the outcome is
  # pending no matter what the status row says.
  def trainee_sessions
    signups = signups_for(Position::TRAINING)
    statuses = keyed(TraineeStatus.where(person_id: person_ids, slot_id: slot_ids(signups))
                                  .pluck(:person_id, :slot_id, :status))

    signups.map do |person_id, slot_id, begins, ends|
      verdict = statuses[[person_id, slot_id]]
      did_pass = ended?(ends) && verdict == TraineeStatus::STATUS_PASSED
      status = ended?(ends) ? TRAINEE_VERDICTS.fetch(verdict, "not passed") : "pending"

      [person_id, TrainingSession.new(begins:, status:, counts_as_trained: did_pass)]
    end
  end

  def trainer_sessions
    signups = signups_for(Position::TRAINER)
    # The trainer's own sign-up is trainer_slot_id; slot_id points at the
    # session they were teaching.
    statuses = keyed(TrainerStatus.where(person_id: person_ids, trainer_slot_id: slot_ids(signups))
                                  .pluck(:person_id, :trainer_slot_id, :status))

    signups.map do |person_id, slot_id, begins, ends|
      taught = statuses[[person_id, slot_id]]
      status = ended?(ends) ? (taught || TrainerStatus::STATUS_PENDING) : "pending"

      [person_id, TrainingSession.new(begins:, status: "#{status} (as trainer)",
                                      counts_as_trained: taught == TrainerStatus::STATUS_ATTENDED)]
    end
  end

  # @return [Array<Array>] [person_id, slot_id, begins, ends] per sign-up
  def signups_for(position_id)
    PersonSlot.joins(:slot)
              .where(person_id: person_ids)
              .where(slot: { position_id:, begins_year: @year, active: true })
              .pluck(:person_id, :slot_id, "slot.begins", "slot.ends")
  end

  def slot_ids(signups)
    signups.map { |_, slot_id, _, _| slot_id }
  end

  # Status rows keyed by [person_id, slot_id]. A hash rather than a left join on
  # two columns, which ActiveRecord cannot express without raw SQL.
  def keyed(rows)
    rows.to_h { |person_id, slot_id, value| [[person_id, slot_id], value] }
  end

  # Slot#has_ended without loading the slots to ask it. That method first shifts
  # the end time into the slot's own timezone; training sessions run in the
  # event's timezone, so the shift is a no-op for every row this report reads.
  def ended?(ends)
    ends <= Current.time
  end
end
