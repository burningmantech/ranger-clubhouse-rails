# frozen_string_literal: true

# One training session -- a slot of a training position -- wrapped with the
# management page's data and mutations (Laravel TrainingSession model +
# TrainingSessionController). Named after the upstream model; the
# Training::Sessions::* controller namespace rules out Training::Session here.
#
# The roster readers are lazy and memoized so the mutation paths (score,
# trainer statuses) never pay for the full page assembly. "Trainee" is the
# house term everywhere -- upstream's "student" naming stops at this port.
class TrainingSession
  RANK_LABELS = {
    1 => "Above Average",
    2 => "Average",
    3 => "Below Average",
    4 => "FLAG"
  }.freeze

  # Every rank except Average must be justified by a note.
  NOTE_REQUIRED_RANKS = [1, 3, 4].freeze

  TRAINER_STATUSES = [
    TrainerStatus::STATUS_PENDING,
    TrainerStatus::STATUS_ATTENDED,
    TrainerStatus::STATUS_NO_SHOW
  ].freeze

  # A person with no person_status history at the session's end time.
  UNKNOWN_STATUS = "unknown"

  # One signed-up trainee with everything the roster card and score dialog
  # show. +status+ is the person's status at the session's end time;
  # +training_status+ is the trainer's verdict, pending when there is no row.
  Trainee = Data.define(
    :person, :status, :years, :need_ranking, :is_art_prospective,
    :training_status, :rank, :feedback_delivered,
    :notes, :fkas, :signed_up_at, :personnel_issue, :team_short_titles
  ) do
    def current_status = person.status
    def is_active = status == Person::ACTIVE
    def is_auditor = status == Person::AUDITOR
    def is_inactive = [Person::INACTIVE, Person::INACTIVE_EXTENSION].include?(status)
    def is_prospective = status == Person::PROSPECTIVE
    def is_retired = status == Person::RETIRED

    def trainer_notes = notes.reject(&:is_log)

    def rank_label
      return nil unless rank

      "#{rank} — #{RANK_LABELS[rank] || "Unknown"}"
    end

    def needs_rank? = need_ranking && rank.nil?
  end

  # One trainer position's slot matched to this session (the
  # Training::SessionList.trainer_slot_match? rule).
  TrainerGroup = Data.define(:slot, :position_id, :position_title, :trainers)
  Trainer = Data.define(:person, :status, :is_lead)

  attr_reader :slot, :training

  # @param slot [Slot] the session slot (already validated to belong to training)
  # @param training [Position] the training position
  def initialize(slot, training)
    @slot = slot
    @training = training
  end

  def art? = Training.art?(training)

  def dirt? = !art?

  # --- roster readers --------------------------------------------------------

  # @return [Array<Trainee>] callsign-ordered signed-up trainees
  def trainees
    @trainees ||= build_trainees
  end

  # One trainee off the roster; nil when the person is not signed up.
  # @param person_id [Integer]
  # @return [Trainee, nil]
  def trainee(person_id)
    trainees.find { |trainee| trainee.person.id == person_id }
  end

  # @return [Array<TrainerGroup>] one group per matched trainer slot
  def trainer_groups
    @trainer_groups ||= build_trainer_groups
  end

  # Position names shown on the trainer's report legend.
  # @return [Array<Array(String, String)>] [title, short_title] pairs
  def team_legend
    report_positions.map { |_id, title, short_title| [title, short_title] }
  end

  # --- roster counts ---------------------------------------------------------

  def passed_count = status_counts[TraineeStatus::STATUS_PASSED]

  # How many trainees hold each status, in TraineeStatus::STATUSES order. A
  # trainee with no row counts as pending, so the four always add up to the
  # roster.
  def status_counts
    counts = trainees.map(&:training_status).tally
    TraineeStatus::STATUSES.index_with { |status| counts.fetch(status, 0) }
  end

  # Dirt: rangered more than one year. ART: not an ART prospective. Feeds the
  # session page counts (the trainer's report bands in
  # Training::SessionsController use their own precedence).
  # @param trainee [Trainee]
  def veteran?(trainee)
    art? ? !trainee.is_art_prospective : trainee.years > 1
  end

  def vet_count = trainees.count { |t| veteran?(t) }

  def prospective_count
    trainees.count { |t| art? ? t.is_art_prospective : t.is_prospective }
  end

  def auditor_count = trainees.count { |t| t.is_auditor }

  def inactive_retired_count = trainees.count { |t| t.is_inactive || t.is_retired }

  def first_year_count = trainees.count { |t| t.is_active && t.years <= 1 }

  def trainer_count = trainer_groups.sum { |group| group.trainers.size }

  def full? = slot.max.positive? && trainees.size >= slot.max

  # Is at least one trainer signed up under a primary trainer position?
  def primary_trainers_signed_up?
    trainer_groups.any? { |group| primary_trainer_position?(group.position_id) && group.trainers.any? }
  end

  # --- mutations -------------------------------------------------------------

  # Persist a validated score (Training::ScoreForm). Mirrors upstream
  # scoreStudent: first-or-new TraineeStatus, an is_log audit note on rank
  # change, the trainer note appended, and the person's role cache cleared --
  # passing a training can grant or revoke training-gated roles.
  # @param person_id [Integer]
  # @param form [Training::ScoreForm]
  def score!(person_id, form)
    trainee_status = TraineeStatus.first_or_new_for_session(person_id, slot.id)
    # TraineeStatus#rank normalizes the legacy 0-means-none column values; a
    # fresh record reads nil, never the 0 column default.
    old_rank = trainee_status.persisted? ? trainee_status.rank : nil

    trainee_status.rank = form.rank
    trainee_status.status = form.status
    trainee_status.feedback_delivered = form.feedback_delivered if dirt? && !form.feedback_delivered.nil?
    new_rank = trainee_status.rank

    ApplicationRecord.transaction do
      trainee_status.save!

      if old_rank != new_rank
        TraineeNote.record(person_id:, slot_id: slot.id, is_log: true,
                           note: "rank change [#{old_rank || "no rank"}] -> [#{new_rank || "no rank"}]")
      end

      TraineeNote.record(person_id:, slot_id: slot.id, note: form.note) if form.note.present?
    end

    # The roster memo predates the save; the post-score section re-render
    # must see the new score. TraineeStatus purges the role cache itself.
    @trainees = nil
  end

  # Bulk-save the trainer attendance table. Rows whose trainer slot is not
  # one of this session's matched groups, or whose person is not on that
  # slot's roster, are skipped -- the form can only fall out of sync with the
  # roster, never widen it.
  # @param rows [Array<Hash>] {person_id:, trainer_slot_id:, status:, is_lead:}
  # @return [Integer] rows saved
  def save_trainer_statuses!(rows)
    on_roster = trainer_groups.flat_map do |group|
      group.trainers.map { |trainer| [group.slot.id, trainer.person.id] }
    end.to_set

    saved = 0
    ApplicationRecord.transaction do
      rows.each do |row|
        person_id = row[:person_id].to_i
        trainer_slot_id = row[:trainer_slot_id].to_i
        status_value = row[:status].presence || TrainerStatus::STATUS_PENDING

        next unless on_roster.include?([trainer_slot_id, person_id])
        next unless TRAINER_STATUSES.include?(status_value)

        status = TrainerStatus.first_or_new_for_session(slot.id, person_id)
        status.trainer_slot_id = trainer_slot_id
        status.status = status_value
        status.is_lead = ActiveModel::Type::Boolean.new.cast(row[:is_lead]) || false
        status.save!
        saved += 1
      end
    end
    @trainer_groups = nil
    saved
  end

  private

  # The retrieveStudents port: one bulk query per concern, then assembly.
  # avatar_photo_attachment rides along so the roster cards render photos
  # without a per-person query.
  def build_trainees
    roster = PersonSlot.where(slot_id: slot.id)
                       .includes(person: :avatar_photo_attachment)
                       .sort_by { |ps| ps.person.callsign.downcase }
    return [] if roster.empty?

    ids = roster.map(&:person_id)
    art_alpha_ids = (dirt? ? [] : Training.find_art_alphas(training.id, ids)).to_set
    statuses = TraineeStatus.where(slot_id: slot.id, person_id: ids).index_by(&:person_id)
    notes = TraineeNote.find_all_for_person_slot(ids, slot.id).group_by(&:person_id)
    statuses_at_time = PersonStatus.find_status_for_ids_time(ids, slot.ends)
    flagged = PersonIntake.personnel_issue_for_ids_year(ids, slot.ends.year).to_set
    team_titles = team_titles_by_person(ids)
    fkas = fkas_by_person(ids)

    roster.map do |person_slot|
      person = person_slot.person
      status = statuses_at_time[person.id]&.new_status || UNKNOWN_STATUS
      trainee_status = statuses[person.id]

      Trainee.new(
        person:,
        status:,
        # years_as_ranger is a serialized column on the rows already loaded.
        years: person.years_as_ranger.is_a?(Array) ? person.years_as_ranger.size : 0,
        need_ranking: dirt? && status != Person::ACTIVE && status != UNKNOWN_STATUS,
        is_art_prospective: art_alpha_ids.include?(person.id),
        training_status: trainee_status&.status || TraineeStatus::STATUS_PENDING,
        rank: trainee_status&.rank,
        feedback_delivered: trainee_status&.feedback_delivered || false,
        notes: notes[person.id] || [],
        fkas: fkas[person.id] || [],
        signed_up_at: person_slot.created_at,
        personnel_issue: flagged.include?(person.id),
        team_short_titles: team_titles[person.id] || []
      )
    end
  end

  # The retrieveTrainers port; the slot matching itself is
  # Training::SessionList.trainer_slot_match?, shared with the landing table.
  def build_trainer_groups
    trainer_position_ids = Position::TRAINERS[slot.position_id] || []
    return [] if trainer_position_ids.empty?

    titles = Position.titles_by_id(trainer_position_ids)

    trainer_position_ids.filter_map do |trainer_position_id|
      trainer_slot = Slot.for_position(trainer_position_id)
                         .for_year(slot.begins_year)
                         .order(:id)
                         .detect { |candidate| Training::SessionList.trainer_slot_match?(slot, candidate) }
      next unless trainer_slot

      people = PersonSlot.where(slot_id: trainer_slot.id)
                         .includes(:person)
                         .map(&:person)
                         .sort_by { |person| person.callsign.downcase }
      statuses = TrainerStatus.find_by_slot_person_ids(slot.id, people.map(&:id))
                              .index_by(&:person_id)

      TrainerGroup.new(
        slot: trainer_slot,
        position_id: trainer_position_id,
        position_title: titles[trainer_position_id],
        trainers: people.map do |person|
          status = statuses[person.id]
          Trainer.new(
            person:,
            status: status&.status || TrainerStatus::STATUS_PENDING,
            is_lead: status&.is_lead || false
          )
        end
      )
    end
  end

  # ART sessions treat every trainer group as primary; dirt's Trainer
  # Associate group is support, not primary.
  def primary_trainer_position?(trainer_position_id)
    art? || [Position::TRAINER, Position::TRAINER_UBER].include?(trainer_position_id)
  end

  # [id, title, short_title] rows for the on_trainer_report positions --
  # feeds both the per-trainee team titles and the report legend.
  def report_positions
    @report_positions ||= Position.where(on_trainer_report: true)
                                  .order(:title)
                                  .pluck(:id, :title, :short_title)
  end

  def team_titles_by_person(person_ids)
    display = report_positions.to_h { |id, title, short_title| [id, short_title.presence || title] }
    return {} if display.empty?

    PersonPosition.where(person_id: person_ids, position_id: display.keys)
                  .pluck(:person_id, :position_id)
                  .group_by(&:first)
                  .transform_values { |pairs| pairs.map { |_, position_id| display[position_id] }.sort }
  end

  def fkas_by_person(person_ids)
    PersonFka.where(person_id: person_ids)
             .order(:fka_normalized)
             .pluck(:person_id, :fka)
             .group_by(&:first)
             .transform_values { |pairs| PersonFka.filter_out_irrelevant(pairs.map(&:last)) }
  end
end
