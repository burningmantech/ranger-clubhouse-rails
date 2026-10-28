# frozen_string_literal: true

# Training provides training-related functionality for Position records.
# This is a service class that wraps Position records and provides methods
# for checking training status, education progress, and related operations.
#
# Note: This is not an ActiveRecord model. It wraps Position records that
# are of type "Training" and provides specialized behavior.

require "ostruct"

class Training
  # Training status constants
  FAIL = "fail" # Marked not-passed or no-show, or not scored once the grace period ran out
  PASS = "pass" # Person passed or taught a session
  NO_SHOW = "no-show" # Person (as a trainer) was no show
  PENDING = "pending" # Training hasn't happened yet, or within grace period
  NO_SHIFT = "no-shift" # No training sign up was found

  # Grace period after training ends before marking as failed
  GRACE_PERIOD_HOURS = 72

  # Custom error for invalid training position lookups
  class NotTrainingPositionError < StandardError; end

  # Education status for a person + training position in a year. A Struct so the
  # green-dot fields (mentee_slot/mentee_timesheet) that #add_green_dot_info assigns
  # are first-class members. Unset booleans read as nil (falsy), matching the old
  # false defaults everywhere they are consumed.
  EducationInfo = Struct.new(
    :status, :slot, :is_trainer, :is_green_dot_pnv, :is_green_dot_mentee,
    :position_id, :position_title, :has_online_course, :required_by,
    :mentee_slot, :mentee_timesheet,
    keyword_init: true
  )

  class << self
    # Did the person pass training in a given year? Checks both student and teacher status.
    # @param person [Person, Integer] person or person_id to check
    # @param position_id [Integer] training position in question
    # @param year [Integer] the year to check
    # @return [Boolean] true if the person passed in the given year
    def did_person_pass_for_year?(person, position_id, year)
      person_id = person.is_a?(Person) ? person.id : person

      TraineeStatus.did_person_pass_for_year?(person_id, position_id, year) ||
        TrainerStatus.taught?(person_id, position_id, year)
    end

    # Did any of the ids pass training? Online Course is not considered.
    # @param person_ids [Array<Integer>] people to check
    # @param position_id [Integer] training position
    # @param year [Integer] the year to check
    # @return [Hash<Integer, Boolean>] hash of person_id => true for those who passed
    def did_ids_pass_for_year(person_ids, position_id, year)
      return {} if person_ids.blank?

      trainee_position_ids = session_position_ids(position_id)

      # Find trainees who passed
      passed_trainees = TraineeStatus.passed
                          .joins(:slot)
                          .where(person_id: person_ids)
                          .where(slot: { position_id: trainee_position_ids, begins_year: year })
                          .pluck(:person_id)

      # Find trainers who attended. TrainerStatus#slot is the session slot; the
      # Trainer position is on #trainer_slot (Slot has_many :trainer_status via
      # trainer_slot_id), so query from the Trainer slot like TrainerStatus.taught?.
      trainer_position_ids = Position::TRAINERS[position_id]
      passed_trainers = if trainer_position_ids.present?
                          Slot.active
                              .joins(:trainer_status)
                              .where(position_id: trainer_position_ids, begins_year: year)
                              .where(trainer_status: { person_id: person_ids, status: TrainerStatus::STATUS_ATTENDED })
                              .pluck("trainer_status.person_id")
                        else
                          []
                        end

      (passed_trainees + passed_trainers).uniq.index_with { true }
    end

    # The slot positions a training manages: itself, plus the refresher for
    # HQ Full Training (the same pairing Position::TRAINERS encodes). The
    # single authority for the fold -- resolution, pass checks, and the
    # session pages must never disagree on which slots belong to a training.
    # @param position_id [Integer]
    # @return [Array<Integer>]
    def session_position_ids(position_id)
      ids = [position_id]
      ids << Position::HQ_REFRESHER_TRAINING if position_id == Position::HQ_FULL_TRAINING
      ids
    end

    # The positions whose shifts this training qualifies someone for: active,
    # actually requiring training, not a training position themselves, and
    # neither the training nor its trainer positions. In-Person Training gates
    # every training-requiring position; an ART gates only the positions
    # pointing back at it. Single authority shared by the trained-no-work and
    # untrained-people reports so the two can never disagree on what "requires
    # this training" means.
    # @param position [Position] the training position
    # @return [Array<Integer>]
    def working_position_ids(position)
      excluded = [position.id, *Position::TRAINERS[position.id]]
      scope = Position.active
                      .where(no_training_required: false)
                      .where.not(type: Position::TYPE_TRAINING)
                      .where.not(id: excluded)
      scope = scope.where(training_position_id: position.id) unless position.id == Position::TRAINING
      scope.ids
    end

    # Find a training position by its URL slug (see Training.slug). The slug
    # is matched by generating slugs for the training-type positions rather
    # than inverting the title transform, so resolution can never disagree
    # with the URLs the menus build. Upstream's "dirt" alias and numeric ids
    # are not accepted.
    # @param slug [String] URL slug ("in-person", "green-dot", ...)
    # @return [Position] the training position
    # @raise [NotTrainingPositionError] if no training position has the slug
    def find_training_position(slug)
      position = Position.where(type: Position::TYPE_TRAINING)
                         .order(:id)
                         .find { |p| training_position?(p) && slug(p) == slug }
      raise NotTrainingPositionError, "No training position matches #{slug.inspect}" unless position

      position
    end

    # Is this a position the training interface serves? Trainer positions are
    # also type Training, so the title check is part of the rule.
    # @param position [Position]
    # @return [Boolean]
    def training_position?(position)
      position.type == Position::TYPE_TRAINING && !position.title.downcase.include?("trainer")
    end

    # The TrainingPolicy view rule as a role list (OR semantics; the admin
    # bypass is Role::ADMIN's membership): ART trainings need the position's
    # composed ART interface role, In-Person Training takes Trainer, Mentor,
    # or VC. Drives both the controller gate and the menu visibility, so the
    # two cannot drift.
    # @param position [Position]
    # @return [Array<Integer>]
    def view_roles(position)
      if art?(position)
        [Role::ADMIN, Role::ART_TRAINER_BASE | position.id]
      else
        [Role::ADMIN, Role::TRAINER, Role::MENTOR, Role::VC]
      end
    end

    # The OnlineCoursePolicy#progressReport rule as a role list: Admin or
    # Trainer, upstream's flat pair -- deliberately tighter than view_roles,
    # which also admits Dirt Mentors and VCs. Takes the position so an ART
    # course, should one ever exist, can widen to its composed role without
    # touching callers. Drives both the controller gate and the menu item's
    # visibility, so the two cannot drift.
    # @param position [Position]
    # @return [Array<Integer>]
    def online_course_progress_roles(_position)
      [Role::ADMIN, Role::TRAINER]
    end

    # The Unified Flagging rule as a role list: Admin or Intake, matching the
    # Ember route's roleRequired and the /vc twin's gate. Intake data is not
    # position-scoped, so the list does not vary -- the position is accepted
    # only so the menu can call this alongside its siblings. This layers ON TOP
    # of view_roles rather than replacing it (Training::BaseController's
    # before_action still runs), which is upstream's pairing: the training tree
    # admits Trainers and Mentors, but a PNV's personnel flags and mentor bonks
    # need Intake. Drives both the controller gate and the menu item, so the
    # two cannot drift.
    # @param position [Position]
    # @return [Array<Integer>]
    def unified_flagging_roles(_position = nil)
      [Role::ADMIN, Role::INTAKE]
    end

    # The SurveyPolicy management rule as a role list, mirroring
    # Survey.has_role_for_position? for a TRAINING position: In-Person takes
    # the flat Survey Management role, an ART takes its composed one, and a
    # training with no survey-management mapping is admin-only (upstream's
    # walk falls through to false). One role covers a training's mentor and
    # mentee surveys too -- they map back through
    # Position::SURVEY_MANAGEMENT_POSITIONS to the same training. Drives both
    # the controller gate and the menu item, so the two cannot drift.
    # @param position [Position]
    # @return [Array<Integer>]
    def survey_management_roles(position)
      if position.id == Position::TRAINING
        [Role::ADMIN, Role::SURVEY_MANAGEMENT_TRAINING]
      elsif Position::SURVEY_MANAGEMENT_POSITIONS.key?(position.id)
        [Role::ADMIN, Role::SURVEY_MANAGEMENT_BASE | position.id]
      else
        [Role::ADMIN]
      end
    end

    # The positions whose surveys the interface presents for a training: the
    # training itself, plus its mentor and mentee positions when it has them.
    # The index renders one section per entry and the report/trainer pages
    # admit a survey only if its position is on this list, which is what stops
    # a survey id from another training loading under this slug.
    # @param position [Position]
    # @return [Array<Integer>]
    def survey_position_ids(position)
      [position.id, mentor_position_id(position), mentee_position_id(position)].compact
    end

    # Find out the education status for a given person, position and year
    # @param person_id [Integer]
    # @param position [Position] training position
    # @param year [Integer]
    # @return [EducationInfo] education status object
    def retrieve_education(person_id, position, year)
      now = Current.time
      training_position_id = position.id

      ed = EducationInfo.new(
        position_id: training_position_id,
        position_title: position.title,
        has_online_course: position.has_online_course
      )

      # In session order, so a pass wins and otherwise the latest session, as
      # upstream picks: its own verdict stands unless a later sign-up has no row.
      trainings = TraineeStatus.find_for_person_year(person_id, year, training_position_id)
      training = trainings.find(&:passed?) || trainings.last

      teaching_positions = Position::TRAINERS[training_position_id]
      if teaching_positions.present?
        taught = TrainerStatus.retrieve_sessions_for_person(person_id, teaching_positions, year)
        trainer = taught.find { |t| t.trainer_status == TrainerStatus::STATUS_ATTENDED }
      else
        taught = []
        trainer = nil
      end

      slot = find_training_slot(person_id, training_position_id, year) if training.blank? || !training.passed?

      populate_education_status(ed, trainer, training, slot, taught, teaching_positions, now)
      # Only the requiring positions this person holds (upstream constrains the eager
      # load the same way); holding none falls through to add_fallback_required_by.
      ed.required_by = position.training_positions
                               .joins(:person_position)
                               .where(person_position: { person_id: })
                               .order(:title)
                               .pluck(:id, :title)
                               .map { |id, title| { id:, title: } }

      add_green_dot_info(ed, person_id, training_position_id, year) if training_position_id == Position::GREEN_DOT_TRAINING && ed.status != NO_SHIFT

      add_fallback_required_by(ed, training_position_id) if ed.required_by.empty?

      ed
    end

    # Is the given time within the grace period?
    # @param time [Time, String] end time of training
    # @param now [Time] current time
    # @param timezone [String] timezone name
    # @return [Boolean]
    def time_within_grace_period?(time, now, timezone)
      parsed_time = time.is_a?(String) ? Time.zone.parse(time).in_time_zone(timezone) : time.in_time_zone(timezone)
      parsed_time + GRACE_PERIOD_HOURS.hours > now
    end

    # Find people who hold a training position but not the trained positions (ART alphas)
    # @param position_id [Integer] training position
    # @param person_ids [Array<Integer>] people to check
    # @return [Array<Integer>] person ids who are ART alphas
    def find_art_alphas(position_id, person_ids)
      return [] if person_ids.blank?

      trained = Position.find_trained_positions(position_id)
      return [] if trained.empty?

      people_with_positions = PersonPosition
                                .where(position_id: trained.pluck(:id), person_id: person_ids)
                                .pluck(:person_id)
                                .to_set

      person_ids.reject { |id| people_with_positions.include?(id) }
    end

    # Retrieve all trainings up to the given year and position for ids
    # @param people_ids [Array<Integer>] people to look up
    # @param position_id [Integer] position to find
    # @param year [Integer] find trainings up to and including the year
    # @return [Hash] grouped by person_id
    def retrieve_training_history_for_ids(people_ids, position_id, year)
      return {} if people_ids.blank?

      rows = Slot
               .select(
                 "slot.*",
                 "person_slot.person_id AS person_id",
                 "trainee_status.status AS training_status",
                 "trainee_status.rank AS training_rank",
                 "trainee_status.feedback_delivered AS feedback_delivered"
               )
               .joins(person_slot: :person)
               # LEFT JOIN with compound condition cannot be converted to ActiveRecord association
               .joins("LEFT JOIN trainee_status ON trainee_status.person_id = person_slot.person_id AND trainee_status.slot_id = person_slot.slot_id")
               .where(begins_year: ..year)
               .where(position_id: position_id)
               .where(person_slot: { person_id: people_ids })
               .order("person_slot.person_id", :begins)
               .to_a

      # Loaded before the emptiness check: on a relation, `empty?` issues its
      # own SELECT and the four-table join below then runs a second time.
      return {} if rows.empty?

      person_statuses = PersonStatus
                          .where(person_id: people_ids)
                          .order(created_at: :desc)
                          .group_by(&:person_id)

      slot_ids = rows.map(&:id).uniq
      training_notes = TraineeNote
                         .where(person_id: people_ids, slot_id: slot_ids)
                         .includes(:person_source)
                         .order(:created_at)
                         .group_by { |n| [n.slot_id, n.person_id] }

      trainings = rows.map do |row|
        status = determine_person_status(person_statuses[row.person_id], row.begins)

        OpenStruct.new(
          person_id: row.person_id,
          training_notes: training_notes[[row.id, row.person_id]],
          person_status: status,
          slot_id: row.id,
          slot_description: row.description,
          slot_begins: row.begins,
          slot_year: row.begins_year,
          slot_tz: row.timezone,
          slot_tz_abbr: row.timezone_abbr,
          slot_has_ended: row.has_ended,
          # No trainee status row reads as pending, the same as a pending one.
          training_status: row.training_status || TraineeStatus::STATUS_PENDING,
          training_passed: row.training_status == TraineeStatus::STATUS_PASSED,
          training_rank: row.training_rank,
          # feedback_delivered is a raw SELECT alias, not a Slot column, so
          # ActiveRecord has no type to cast it with and MariaDB's TINYINT
          # arrives as Integer 0/1 -- and 0 is truthy in Ruby. Callers branch on
          # it directly, so it is cast here rather than at each site.
          feedback_delivered: ActiveModel::Type::Boolean.new.cast(row.feedback_delivered)
        )
      end

      trainings.group_by(&:person_id)
    end

    # Does the person require full training and/or are they a binary?
    # @param person [Person]
    # @return [Array<Boolean, Boolean>] [full_day_required, is_binary]
    def requires_training_full_day?(person)
      if person.status == Person::ACTIVE
        is_binary = Timesheet.person_binary?(person)
        [is_binary, is_binary]
      else
        [true, false]
      end
    end

    # Check if position is an ART (Advanced Ranger Training)
    # @param position [Position]
    # @return [Boolean]
    def art?(position)
      position.id != Position::TRAINING
    end

    # The position's URL slug: "in-person" for In-Person Training, otherwise
    # the title with the "Training" token stripped, parameterized
    # ("Green Dot Training" -> "green-dot", "Training - Radio Practice" ->
    # "radio-practice").
    # @param position [Position]
    # @return [String]
    def slug(position)
      (position.id == Position::TRAINING) ? "in-person" : strip_training_token(position.title).parameterize
    end

    # The title with the "Training" token removed wherever it appears, along
    # with any separator it leaves dangling. Shared by the URL slug and the
    # menu category title so the two always agree on a position's name.
    # @param title [String]
    # @return [String]
    def strip_training_token(title)
      title.gsub(/[-–—\s]*\bTraining\b[-–—\s]*/, " ").squish
    end

    # Get graduation info for a training position
    # @param position [Position]
    # @return [Hash, nil]
    def graduation_info(position)
      graduate = Position::ART_GRADUATE_TO_POSITIONS[position.id]
      return nil unless graduate

      result = {
        positions: graduate[:positions].map { |p| { id: p, title: Position.retrieve_title(p) } }
      }

      if graduate[:veteran].present?
        result[:fully_graduated_position] = {
          id: graduate[:veteran],
          title: Position.retrieve_title(graduate[:veteran])
        }
      end

      result
    end

    # The mentor position an ART mentoring training pairs with its mentees on
    # shift: the position on the training's own team flagged is_art_mentor
    # (Position holds a team to one). Nil unless the training has_art_mentoring.
    #
    # Found by team, not by training_position_id (ruled 2026-10-21): pointing a
    # position's training_position_id at an ART also makes its holders need that
    # ART's pass to sign in (SignInBlocker#check_for_training), and
    # Troubleshooter Training records no passes, so the Troubleshooters' mentor
    # and mentee positions cannot point at it.
    # @param position [Position] the training position
    # @return [Integer, nil]
    def mentor_position_id(position)
      art_mentoring_position_id(position, :is_art_mentor)
    end

    # The mentee position an ART mentoring training pairs on shift, found the
    # same way as mentor_position_id: flagged is_art_mentee on its team.
    # @param position [Position] the training position
    # @return [Integer, nil]
    def mentee_position_id(position)
      art_mentoring_position_id(position, :is_art_mentee)
    end

    # Every mentor (or mentee) position an ART mentoring training pairs, by
    # id. Some do not say which they are in their title -- the Troubleshooters'
    # mentee position is called "Prospective" -- so a rule built on titles
    # alone leaves that cadre out.
    # @param category [Symbol] :mentor or :mentee
    # @return [Array<Integer>]
    def cadre_position_ids(category)
      flag = (category == :mentor) ? :is_art_mentor : :is_art_mentee
      Position.where(flag => true, team_id: Position.where(has_art_mentoring: true).select(:team_id)).ids
    end

    # The ART mentoring training on each of these teams, by team id: the
    # reverse of mentor_position_id / mentee_position_id, for a walk filed
    # under a mentee position.
    # @param team_ids [Array<Integer>]
    # @return [Hash{Integer => Position}]
    def art_mentoring_trainings_by_team(team_ids)
      Position.where(has_art_mentoring: true, team_id: team_ids).index_by(&:team_id)
    end

    # Does this training have mentees?
    # @param position [Position]
    # @return [Boolean]
    def has_mentees?(position)
      Position::ART_GRADUATE_TO_POSITIONS.dig(position.id, :has_mentees) || false
    end

    # The ART's mentee positions -- the ones a graduate is granted on the way
    # in and revoked on the way out (Tow Truck Mentee; Green Dot Mentee and
    # Sanctuary Mentee). NOT the same thing as mentee_position_id above, which
    # is the one position an ART mentoring training pairs with mentors on
    # shift. Single authority for the Current Mentees report and its revoke
    # action.
    # @param position [Position]
    # @return [Array<Integer>]
    def mentee_position_ids(position)
      return [] unless has_mentees?(position)

      Position::ART_GRADUATE_TO_POSITIONS.dig(position.id, :positions) || []
    end

    private

    def art_mentoring_position_id(position, flag)
      return nil unless position.has_art_mentoring && position.team_id

      Position.where(team_id: position.team_id, flag => true).order(:id).pick(:id)
    end

    def find_training_slot(person_id, training_position_id, year)
      ids = session_position_ids(training_position_id)

      Slot
        .joins(:person_slot)
        .where(position_id: ids, begins_year: year, active: true)
        .where(person_slot: { person_id: person_id })
        .order(begins: :desc)
        .first
    end

    def populate_education_status(ed, trainer, training, slot, taught, teaching_positions, now)
      if trainer
        ed.slot = trainer
        ed.is_trainer = true
        ed.status = PASS
      elsif training
        populate_training_status(ed, training, slot, now)
      elsif slot
        ed.slot = slot
        ed.status = time_within_grace_period?(slot.ends, now, slot.timezone) ? PENDING : FAIL
      elsif teaching_positions.present? && taught.present?
        populate_trainer_fallback_status(ed, taught)
      else
        ed.status = NO_SHIFT
      end
    end

    def populate_training_status(ed, training, slot, now)
      # If not passed but there's a later sign-up, use that
      if !training.passed? && slot && slot.id != training.slot_id && slot.ends > training.slot.ends
        ed.slot = slot
        ed.status = time_within_grace_period?(slot.ends, now, slot.timezone) ? PENDING : FAIL
      else
        ed.slot = training.slot
        ed.status = case training.status
                    when TraineeStatus::STATUS_PASSED
                      PASS
                    when TraineeStatus::STATUS_PENDING
                      # Not scored yet: the grace period covers the trainer's lag.
                      time_within_grace_period?(training.slot.ends, now, training.slot.timezone) ? PENDING : FAIL
                    else
                      # A no-show or not-passed was entered: nothing is left to wait for.
                      FAIL
                    end
      end
    end

    def populate_trainer_fallback_status(ed, taught)
      slot = taught.find { |t| t.trainer_status == TrainerStatus::STATUS_PENDING } ||
             taught.find { |t| t.trainer_status == TrainerStatus::STATUS_NO_SHOW } ||
             taught.first

      ed.slot = slot
      ed.is_trainer = true
      ed.status = (slot.trainer_status == TrainerStatus::STATUS_NO_SHOW) ? NO_SHOW : PENDING
    end

    def add_green_dot_info(ed, person_id, _training_position_id, year)
      ed.is_green_dot_pnv = !PersonPosition.have_position?(person_id, Position::DIRT_GREEN_DOT)
      ed.is_green_dot_mentee = PersonPosition.have_position?(person_id, Position::GREEN_DOT_MENTEE)

      return unless ed.is_green_dot_mentee

      ed.mentee_slot = Slot.find_first_sign_up(person_id, Position::GREEN_DOT_MENTEE, year)
      ed.mentee_timesheet = Timesheet.find_latest_for_person_position(person_id, Position::GREEN_DOT_MENTEE, year)
    end

    def add_fallback_required_by(ed, training_position_id)
      requires = case training_position_id
                 when Position::GREEN_DOT_TRAINING
                   { id: Position::GREEN_DOT_MENTEE, title: "Green Dot Mentee" }
                 when Position::SANDMAN_TRAINING
                   { id: Position::SANDMAN, title: "Sandman" }
                 when Position::TOW_TRUCK_TRAINING
                   { id: Position::TOW_TRUCK_MENTEE, title: "Tow Truck Mentee" }
                 when Position::HQ_FULL_TRAINING
                   { id: Position::HQ_WINDOW, title: "HQ Window" }
                 end

      if requires
        requires[:not_granted] = true
        ed.required_by = [requires]
      end
    end

    def determine_person_status(statuses, begins_time)
      return "unknown" if statuses.blank?

      # statuses are newest-first; the status at training time is the first
      # change recorded before the training begins. Fall back to the newest.
      found = statuses.find { |ps| ps.created_at < begins_time } || statuses.first

      (found.new_status == Person::VINTAGE) ? Person::ACTIVE : found.new_status
    end
  end
end
