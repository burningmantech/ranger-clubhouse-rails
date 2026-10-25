# frozen_string_literal: true

# Runs a PersonSearchForm's criteria against every account. The person query
# does whatever SQL does cheaply -- status, created year, photo, the
# person_status id set for a status-change year -- and everything that needs
# a second table (course, ticketing, photo status, training slots, claimed
# tickets) is batch-loaded by id afterward, with the years-rangered,
# training, and ticketing filters applied in Ruby against that batch.
class PeopleSearchReport
  # Copied before freezing: the array belongs to Position::TRAINERS, and
  # freezing it in place would turn an unrelated write elsewhere into an error
  # that only appears once this report has been loaded.
  TRAINER_POSITION_IDS = Position::TRAINERS[Position::TRAINING].dup.freeze
  CLAIMED_TICKET_TYPES = [AccessDocument::STAFF_CREDENTIAL, AccessDocument::SPT].freeze

  # The training verdict a row carries and prints -- separate from the
  # Training service class's own status words (which include "no-shift"
  # rather than "missing"), because these are exactly the four values the
  # training_status filter select and the results column both use.
  TRAINING_MISSING = "missing"
  TRAINING_PENDING = "pending"
  TRAINING_PASSED = "passed"
  TRAINING_FAILED = "failed"

  # One row per matched person, carrying only what the view and the CSV
  # export read. photo_status, the online-course pair, the training triple,
  # and the ticketing pair are nil unless the form asked to see them.
  Row = Data.define(:person, :old_status, :new_status, :status_changed_at,
                     :years_worked, :photo_status,
                     :online_course_started, :online_course_finished,
                     :training_status, :training_date, :training_signed_up_at,
                     :ticketing_started_at, :ticketing_finished_at)

  class << self
    def call(form)
      status_changes = form.status_year_mode? ? status_changes_by_person(form) : {}
      people = person_scope(form, status_changes.keys).to_a
      return [] if people.empty?

      ids = people.map(&:id)
      rows = build_rows(people, ids, form, status_changes)

      rows = apply_years_filter(rows, form)
      rows = apply_online_course_filter(rows, form)
      rows = apply_training_filter(rows, form)
      apply_ticketing_filter(rows, form)
    end

    private

    def person_scope(form, status_year_ids)
      scope = Person.order(:callsign)
      scope = if form.status_year_mode?
                scope.where(id: status_year_ids)
              elsif form.statuses.present?
                scope.where(status: form.statuses)
              else
                scope
              end

      scope = year_created_scope(scope, form.year_created.to_i) if form.year_created.to_i.positive?
      scope = photo_status_scope(scope, form.photo_status) if form.photo_status.present?
      scope
    end

    def year_created_scope(scope, year)
      return scope.where(created_at: nil) if year == PersonSearchForm::CREATED_PRIOR_SENTINEL

      scope.where_year(:created_at, year)
    end

    # Matched through the person's own photos rather than the person_photo_id
    # column, which nothing keeps up to date any more: people whose photo was
    # rejected and later approved still point at the rejected one, so that
    # column would leave them out of an approved search and put them in a
    # rejected one.
    #
    # Approved wins where a person has both. Someone partway through review,
    # holding only a submitted or uploaded photo, answers to none of the three
    # -- they have neither had a photo accepted nor turned one down, and the
    # column still names where they actually are.
    def photo_status_scope(scope, status)
      approved = PersonPhoto.approved.select(:person_id)

      case status
      when PersonPhoto::APPROVED then scope.where(id: approved)
      when PersonPhoto::MISSING then scope.where.not(id: PersonPhoto.select(:person_id))
      else scope.where(id: PersonPhoto.where(status:).select(:person_id)).where.not(id: approved)
      end
    end

    def build_rows(people, ids, form, status_changes)
      online_courses = form.show_online_course? ? online_courses_by_person(ids) : {}
      person_events = form.show_ticketing_info? ? person_events_by_person(ids) : {}
      training_verdicts = form.show_training_status? ? training_verdicts_by_person(ids) : {}
      photo_statuses = photo_statuses_by_person(people, form)
      show_years = form.show_years_worked?

      people.map do |person|
        change = status_changes[person.id]
        course = online_courses[person.id]
        event = person_events[person.id]
        training = training_verdicts[person.id]

        Row.new(
          person:,
          old_status: change&.old_status,
          new_status: change&.new_status,
          status_changed_at: change&.created_at,
          years_worked: (person.years_as_ranger.size if show_years),
          photo_status: photo_statuses[person.id],
          online_course_started: course&.enrolled_at,
          online_course_finished: course&.completed_at,
          training_status: training&.first,
          training_date: training&.second,
          training_signed_up_at: training&.third,
          ticketing_started_at: event&.ticketing_started_at,
          ticketing_finished_at: event&.ticketing_finished_at
        )
      end
    end

    # Two changes to the same status in the same year keep the latest. The id
    # breaks a tie, since bulk changes write several rows in the same second
    # and the newest of those would otherwise be whichever one came back
    # first. Keyed by person id so the same lookup both scopes person_scope
    # (its keys) and labels each row (its values) -- one query instead of one
    # to find who matched and a second to find what matched.
    def status_changes_by_person(form)
      PersonStatus.where(new_status: form.statuses)
                  .where_year(:created_at, form.status_year.to_i)
                  .order(created_at: :desc, id: :desc)
                  .group_by(&:person_id)
                  .transform_values(&:first)
    end

    def online_courses_by_person(ids)
      PersonOnlineCourse.where(person_id: ids, position_id: Position::TRAINING, year: Current.year)
                        .index_by(&:person_id)
    end

    def person_events_by_person(ids)
      PersonEvent.where(person_id: ids, year: Current.year).index_by(&:person_id)
    end

    # A person's photo status for the column: the filter value itself when one
    # was searched on (every matched row already carries it), otherwise the
    # person's own photos -- approved where they have one, the newest photo
    # they do have otherwise, and missing where they have none.
    def photo_statuses_by_person(people, form)
      return {} unless form.show_photo_status?
      return people.to_h { |person| [person.id, form.photo_status] } if form.photo_status.present?

      by_person = PersonPhoto.where(person_id: people.map(&:id))
                             .order(created_at: :desc, id: :desc)
                             .pluck(:person_id, :status)
                             .group_by(&:first)

      people.to_h do |person|
        statuses = by_person[person.id]&.map(&:last) || []
        current = statuses.include?(PersonPhoto::APPROVED) ? PersonPhoto::APPROVED : statuses.first
        [person.id, current || PersonPhoto::MISSING]
      end
    end

    def apply_years_filter(rows, form)
      return rows if form.years_worked.blank?

      target = form.years_worked.to_i
      rows.select do |row|
        case form.years_worked_op
        when "gte" then row.years_worked >= target
        when "lte" then row.years_worked <= target
        else row.years_worked == target
        end
      end
    end

    def apply_online_course_filter(rows, form)
      return rows if form.online_course_status.blank?

      rows.select do |row|
        case form.online_course_status
        when "missing" then row.online_course_started.blank? && row.online_course_finished.blank?
        when "started" then row.online_course_started.present?
        when "completed" then row.online_course_finished.present?
        else true
        end
      end
    end

    def apply_training_filter(rows, form)
      return rows if form.training_status.blank?

      rows.select do |row|
        case form.training_status
        when "missing" then row.training_date.blank?
        when "signed-up" then row.training_date.present?
        when "passed" then row.training_status == TRAINING_PASSED
        when "failed" then row.training_status == TRAINING_FAILED
        else true
        end
      end
    end

    def apply_ticketing_filter(rows, form)
      return rows if form.ticketing_status.blank?

      claimed_ids = claimed_ticket_person_ids(rows) if form.ticketing_status == "not-finished-claimed"

      rows.select do |row|
        started = row.ticketing_started_at.present?
        finished = row.ticketing_finished_at.present?

        case form.ticketing_status
        when "started" then started
        when "not-started" then !started
        when "finished" then finished
        when "not-finished" then started && !finished
        when "not-finished-claimed" then started && !finished && claimed_ids.include?(row.person.id)
        else true
        end
      end
    end

    def claimed_ticket_person_ids(rows)
      return Set.new if rows.empty?

      AccessDocument.where(person_id: rows.map { |row| row.person.id },
                           type: CLAIMED_TICKET_TYPES, status: AccessDocument::CLAIMED)
                    .distinct
                    .pluck(:person_id)
                    .to_set
    end

    # Trainer slots beat trainee slots for the same person: someone who
    # taught this year is judged as a trainer even if they also signed up as
    # a trainee. One query covers both groups; each person's own slots are
    # then split by position -- not decided by their first slot, since a
    # person can hold both kinds of signup in the same year.
    def training_verdicts_by_person(ids)
      signups = signups_by_person(ids, TRAINER_POSITION_IDS + [Position::TRAINING])

      trainer_signups = {}
      trainee_signups = {}
      signups.each do |person_id, slots|
        trainer, trainee = slots.partition { |person_slot| person_slot.slot.position_id.in?(TRAINER_POSITION_IDS) }
        trainer_signups[person_id] = trainer if trainer.any?
        trainee_signups[person_id] = trainee if trainee.any?
      end

      trainer_statuses = status_by_key(TrainerStatus, :trainer_slot_id, trainer_signups)
      trainee_statuses = status_by_key(TraineeStatus, :slot_id, trainee_signups)

      ids.index_with do |id|
        if trainer_signups[id]
          trainer_verdict(trainer_signups[id], trainer_statuses)
        else
          trainee_verdict(trainee_signups[id], trainee_statuses)
        end
      end
    end

    def signups_by_person(ids, position_ids)
      PersonSlot.joins(:slot)
                .where(person_id: ids, slot: { position_id: position_ids, begins_year: Current.year })
                .includes(:slot)
                .order("slot.begins")
                .group_by(&:person_id)
    end

    # One trainer slot can cover more than one taught session, so a person can
    # hold several rows against the same slot. They are grouped rather than
    # indexed, and the verdict below reads whichever of them settles it, so
    # the answer does not depend on which row came back first.
    def status_by_key(model, slot_id_column, signups_by_person)
      return {} if signups_by_person.empty?

      slot_ids = signups_by_person.values.flatten.map(&:slot_id)
      model.where(slot_id_column => slot_ids, person_id: signups_by_person.keys)
           .group_by { |status| [status.public_send(slot_id_column), status.person_id] }
    end

    # Walks a person's signups in begins order, folding each into a verdict
    # via the block, and stops at the first PASSED -- a later slot cannot
    # undo an earlier pass. Otherwise the last slot's outcome stands.
    def verdict_from_signups(signups)
      status = TRAINING_PENDING
      date = nil
      signed_up_at = nil

      signups.each do |person_slot|
        slot = person_slot.slot
        date = slot.begins
        signed_up_at = person_slot.created_at
        status = yield(person_slot, slot)
        break if status == TRAINING_PASSED
      end

      [status, date, signed_up_at]
    end

    # Attending any session on the slot settles it; a no-show only stands
    # where nothing was attended.
    def trainer_verdict(signups, trainer_statuses)
      verdict_from_signups(signups) do |person_slot, slot|
        statuses = trainer_statuses[[slot.id, person_slot.person_id]].to_a.map(&:status)

        if statuses.include?(TrainerStatus::STATUS_ATTENDED)
          TRAINING_PASSED
        elsif statuses.include?(TrainerStatus::STATUS_NO_SHOW)
          TRAINING_FAILED
        else
          TRAINING_PENDING
        end
      end
    end

    # A pass settles it. A no-show or not-passed was entered by a trainer, so
    # it fails at once; the grace period covers only a session no one has
    # scored yet, which reads exactly like one with no status row at all.
    def trainee_verdict(signups, trainee_statuses)
      return [TRAINING_MISSING, nil, nil] if signups.blank?

      verdict_from_signups(signups) do |person_slot, slot|
        statuses = trainee_statuses[[slot.id, person_slot.person_id]].to_a.map(&:status)

        if statuses.include?(TraineeStatus::STATUS_PASSED)
          TRAINING_PASSED
        elsif statuses.all?(TraineeStatus::STATUS_PENDING) &&
              Training.time_within_grace_period?(slot.ends, Time.zone.now, slot.timezone)
          TRAINING_PENDING
        else
          TRAINING_FAILED
        end
      end
    end
  end
end
