class Survey < ApplicationRecord
  self.table_name = "survey"
  self.inheritance_column = nil # Disable STI
  self.audit_model = true

  # Nested classes for result objects
  # Represents a person reference in survey context
  class PersonInfo
    attr_reader :id, :callsign, :position_title

    def initialize(id:, callsign:, position_title: nil)
      @id = id
      @callsign = callsign
      @position_title = position_title
    end
  end

  # Represents a training or mentoring session
  class SurveySession
    attr_reader :id, :type, :begins, :timezone, :description, :position_id, :position_title, :mentoring

    def initialize(id:, type:, begins:, description:, position_id:, position_title:, mentoring: nil, timezone: nil)
      @id = id
      @type = type
      @begins = begins
      @description = description
      @position_id = position_id
      @position_title = position_title
      @mentoring = mentoring
      @timezone = timezone
    end
  end

  # Represents a trainer survey with trainers list
  class TrainerSurvey
    attr_reader :id, :type, :description, :begins, :timezone, :position_id, :position_title, :trainers

    def initialize(id:, type:, description:, begins:, position_id:, position_title:, trainers:, timezone: nil)
      @id = id
      @type = type
      @description = description
      @begins = begins
      @position_id = position_id
      @position_title = position_title
      @trainers = trainers
      @timezone = timezone
    end
  end

  # Root result container for unanswered surveys
  class UnansweredResult
    attr_reader :sessions, :trainers, :alpha_survey

    def initialize(sessions:, trainers:, alpha_survey:)
      @sessions = sessions
      @trainers = trainers
      @alpha_survey = alpha_survey
    end
  end

  # Constants
  ALPHA = "alpha"
  MENTEES_FOR_MENTOR = "mentees-for-mentor"
  MENTOR_FOR_MENTEES = "mentor-for-mentees"
  TRAINER = "trainer"
  TRAINING = "training"

  TARGET_LABELS = {
    ALPHA => "Alpha",
    MENTEES_FOR_MENTOR => "Mentor",
    MENTOR_FOR_MENTEES => "Mentee",
    TRAINER => "Trainer",
    TRAINING => "Training"
  }.freeze

  TYPE_FOR_REPORTS_LABELS = {
    TRAINER => "Trainer-on-Trainer Feedback",
    TRAINING => "Trainee-on-Trainer Feedback",
    ALPHA => "Alpha Feedback",
    MENTEES_FOR_MENTOR => "Mentee-on-Mentor Feedback",
    MENTOR_FOR_MENTEES => "Mentor-on-Mentee Feedback"
  }.freeze

  # Every kind of survey, in the order the management page offers them.
  TYPES = [TRAINING, TRAINER, ALPHA, MENTOR_FOR_MENTEES, MENTEES_FOR_MENTOR].freeze

  # The two kinds where one cadre rates another, and so name a second
  # position: the one the survey asks about.
  MENTORING_TYPES = [MENTOR_FOR_MENTEES, MENTEES_FOR_MENTOR].freeze

  # The kind of position each kind of survey sits at. A survey's position is
  # the one held by the people answering it, which is how the Clubhouse knows
  # who to show it to.
  POSITION_CATEGORIES = {
    TRAINING => :training,
    TRAINER => :training,
    ALPHA => :alpha,
    MENTOR_FOR_MENTEES => :mentor,
    MENTEES_FOR_MENTOR => :mentee
  }.freeze

  # For the two mentoring kinds, the kind of position the survey asks about.
  MENTORING_CATEGORIES = {
    MENTOR_FOR_MENTEES => :mentee,
    MENTEES_FOR_MENTOR => :mentor
  }.freeze

  POSITION_CATEGORY_LABELS = {
    training: "a training position",
    mentor: "a mentor position",
    mentee: "a mentee position",
    alpha: "the Alpha position"
  }.freeze

  # Relations
  belongs_to :position, optional: true
  belongs_to :mentoring_position, class_name: "Position", optional: true
  has_many :survey_groups, -> { ordered }, dependent: :destroy
  has_many :survey_questions, dependent: :destroy
  # Answers are plain rows with nothing hanging off them, and a popular survey
  # holds thousands, so they go in one statement rather than one at a time.
  has_many :survey_answers, dependent: :delete_all

  # Validations
  validates :year, presence: true, numericality: { only_integer: true }
  validates :type, presence: true,
            inclusion: { in: TYPES, allow_blank: true,
                         message: "Who answers must be one of the kinds this page offers" }
  # A survey with no position can be managed by no one, admin included:
  # can_manage_surveys? answers false before it looks at any role.
  validates :position_id, presence: { message: "Position must be chosen" }
  # The error summary prints a message on its own, with no field name in
  # front of it, so each message says which field it is about.
  validates :title, presence: { message: "Title can't be blank" },
            length: { maximum: 190, message: "Title is too long (190 characters at most)" }
  validates :prologue, allow_blank: true, length: { maximum: 65535 }
  validates :epilogue, allow_blank: true, length: { maximum: 65535 }
  validate :validate_mentoring_position
  validate :validate_position_category
  validate :validate_one_survey_per_position_and_year
  validate :validate_active_survey_has_questions

  # Changing a survey's kind away from a mentoring one leaves nothing behind.
  # Only when the kind is being changed: a save that touches the title alone
  # should not quietly empty a column it never asked about.
  before_validation :clear_unused_mentoring_position, if: -> { new_record? || type_changed? }

  # Attributes defaults. The text columns hold no nulls, so a survey saved
  # without one of them stores an empty string rather than failing.
  attribute :active, :boolean, default: false
  attribute :prologue, :string, default: ""
  attribute :epilogue, :string, default: ""

  # Neither is required, so an editor left untouched must store nothing: empty
  # blocks would make the survey page show an empty callout for a field that
  # was never written.
  normalizes :prologue, :epilogue, with: BLANK_WHEN_EMPTY_RICH_TEXT

  # Scopes
  scope :active, -> { where(active: true) }

  # Virtual attributes for reporting (populated during queries)
  attr_accessor :slots, :reports
  attr_writer :has_responses

  # Has anyone answered this survey? A list of surveys sets this for the whole
  # page in one query; a survey asked on its own answers for itself, rather
  # than reporting "none yet" because no one told it otherwise.
  def has_responses
    return @has_responses unless @has_responses.nil?

    @has_responses = SurveyAnswer.exists?(survey_id: id)
  end

  # Does this survey have one cadre rate another, and so ask about a second
  # position?
  def mentoring_type?
    MENTORING_TYPES.include?(type)
  end

  def validate_mentoring_position
    return unless mentoring_type?

    if mentoring_position_id.blank?
      errors.add(:mentoring_position_id, "About must name the position this survey asks about")
      return
    end

    return unless category_check_needed?(:mentoring_position_id)

    category = MENTORING_CATEGORIES[type]
    return if Survey.position_in_category?(mentoring_position_id, category)

    errors.add(:mentoring_position_id,
               "About must be #{POSITION_CATEGORY_LABELS[category]} for this kind of survey")
  end

  # The position has to match the kind of survey, because it is what the
  # people answering hold: a training for a survey trainees answer, a mentor
  # position for one mentors answer, and so on.
  def validate_position_category
    return if position_id.blank? || !TYPES.include?(type)
    return unless category_check_needed?(:position_id)

    category = POSITION_CATEGORIES[type]
    return if Survey.position_in_category?(position_id, category)

    errors.add(:position_id,
               "Position must be #{POSITION_CATEGORY_LABELS[category]} for this kind of survey")
  end

  def clear_unused_mentoring_position
    self.mentoring_position_id = nil unless mentoring_type?
  end

  def position_title
    position&.title
  end

  def mentoring_position_title
    mentoring_position&.title || ""
  end

  # Only check the pairing when the kind or the position is actually being
  # set. A row written by something else, holding some other pairing, can
  # still have its title or its text fixed here rather than being stuck.
  def category_check_needed?(attribute)
    new_record? || type_changed? || public_send(:"#{attribute}_changed?")
  end

  # Only one survey of a kind, per position, per year. The page people answer
  # looks a survey up by exactly those three and takes the first it finds, so
  # a second one quietly collects the answers meant for the first. Checked
  # only when one of the three is being set, so a row written elsewhere that
  # already collides can still have its wording fixed.
  def validate_one_survey_per_position_and_year
    return if position_id.blank? || type.blank?
    return unless new_record? || type_changed? || position_id_changed? || year_changed?
    return unless self.class.where(type:, position_id:, year:).where.not(id: id).exists?

    errors.add(:type, "There is already a #{year} survey of this kind for this position. " \
                      "Edit that one instead of making a second.")
  end

  # A survey with no questions cannot be answered, but it can still be
  # offered: the dashboard keeps asking for it, and answering writes nothing,
  # so the task never clears. Switching one on is refused until it asks
  # something. A survey is always built before it is switched on -- the form
  # that makes one does not offer the setting -- so this is asked of a survey
  # that already exists.
  def validate_active_survey_has_questions
    return unless active? && persisted? && active_changed?
    return if survey_questions.exists?

    errors.add(:active, "Add a question before switching this survey on. " \
                        "An empty survey cannot be answered, so it would never clear.")
  end

  # A copy of this survey for another year: the same groups and questions with
  # new ids, and switched off until someone has looked it over. A year in the
  # title moves along with it.
  def duplicate_into(year)
    self.class.transaction do
      copy = dup
      copy.assign_attributes(year:, active: false, title: title.sub(/\b#{self.year}\b/, year.to_s))
      copy.save!

      survey_groups.includes(:survey_questions).each do |group|
        new_group = group.dup
        new_group.survey_id = copy.id
        new_group.save!

        group.survey_questions.each do |question|
          new_question = question.dup
          new_question.assign_attributes(survey_id: copy.id, survey_group_id: new_group.id)
          new_question.save!
        end
      end

      copy
    end
  end

  # The training whose pages show this survey's answers: the survey's own
  # position when that is a training, and otherwise the training whose cadre
  # the position belongs to. Nil when no page shows them.
  def feedback_training_position
    return nil unless position
    return position if Training.training_position?(position)

    training_id, = Position::SURVEY_MANAGEMENT_POSITIONS.find { |_id, ids| ids.include?(position_id) }
    training = training_id ? Position.find_by(id: training_id) : nil
    # The Mentor position walks back to Alpha, which is a cadre rather than a
    # training and has no page of its own. Nothing shows those answers.
    training if training && Training.training_position?(training)
  end

  def can_manage_survey?(user)
    Survey.can_manage_surveys?(user, position_id)
  end

  def is_trainer_for_survey?(user)
    Survey.has_role_for_position?(user, Role::TRAINER, Role::ART_TRAINER_BASE, position_id)
  end

  def self.can_manage_surveys?(user, position_id)
    has_role_for_position?(user, Role::SURVEY_MANAGEMENT_TRAINING, Role::SURVEY_MANAGEMENT_BASE, position_id)
  end

  # May the person reach the survey management page at all? Which surveys they
  # may then touch is can_manage_survey?, one survey at a time.
  def self.can_manage_any?(user)
    return false unless user
    return true if user.has_role?([Role::ADMIN, Role::SURVEY_MANAGEMENT_TRAINING])

    user.has_role_base?(Role::SURVEY_MANAGEMENT_BASE)
  end

  # Every position a survey of this kind may sit at. The training list is the
  # one the Clubhouse offers everywhere else: a training position whose title
  # says so, which leaves out the trainer positions of the same type.
  def self.positions_in_category(category)
    case category
    when :training then Position.find_for_query({ art_training: true })
    when :mentor, :mentee then cadre_positions(category)
    when :alpha then Position.where(id: Position::ALPHA).to_a
    else []
    end
  end

  # Is one position of the given kind? Asked while saving, so it probes for
  # the one id rather than reading a whole list to scan it.
  def self.position_in_category?(position_id, category)
    return false if position_id.blank?

    case category
    when :mentor, :mentee then cadre_positions(category).any? { |p| p.id == position_id }
    when :training then Position.find_for_query({ art_training: true }).any? { |p| p.id == position_id }
    when :alpha then position_id == Position::ALPHA
    else false
    end
  end

  # The mentor or mentee positions a survey of that kind may sit at: the ones
  # whose title says so, plus the ones the Clubhouse names for each training
  # cadre. The Troubleshooters' mentee position is called "Prospective", so
  # the titles alone would leave that cadre unable to have a survey at all.
  def self.cadre_positions(category)
    titled = Position.find_for_query({ category => true })
    named = Training.cadre_position_ids(category) - titled.map(&:id)

    (titled + Position.where(id: named).ordered_by_title).sort_by(&:title)
  end

  # What the survey form offers, from one read of each list: the positions
  # this person manages, grouped by kind, and every position of each kind --
  # the second is what a mentoring survey may ask about, which is not narrowed
  # to what the reader manages because it names who is being rated.
  def self.form_positions(user)
    every = POSITION_CATEGORIES.values.uniq.index_with { |category| positions_in_category(category) }
    manageable = every.transform_values do |list|
      list.select { |position| can_manage_surveys?(user, position.id) }
    end

    [manageable, every]
  end

  # The positions the person manages surveys for, in the groups the survey
  # form offers them. Most people manage one cadre, so most groups come back
  # empty.
  def self.manageable_positions(user)
    form_positions(user).first
  end

  # Does this person manage no position at all? A survey permission can name a
  # position the Clubhouse does not connect to surveys, and then this page has
  # nothing to offer. Stops at the first kind that answers yes.
  def self.manages_no_positions?(user)
    POSITION_CATEGORIES.values.uniq.none? do |category|
      positions_in_category(category).any? { |position| can_manage_surveys?(user, position.id) }
    end
  end

  # The kinds of survey the person may create: a kind is offered when they
  # manage at least one position a survey of that kind could sit at.
  def self.type_options_for(user, positions = manageable_positions(user))
    TYPES.select { |type| positions[POSITION_CATEGORIES[type]].present? }
  end

  def self.has_role_for_position?(user, trainer_role, base, position_id)
    return false unless position_id

    return true if user.has_role?(Role::ADMIN)

    if position_id == Position::TRAINING
      return user.has_role?(trainer_role)
    end

    if Position::SURVEY_MANAGEMENT_POSITIONS[position_id]
      return user.has_role?(base | position_id)
    end

    Position::SURVEY_MANAGEMENT_POSITIONS.each do |id, positions|
      if positions.include?(position_id)
        return user.has_role?(base | id)
      end
    end

    false
  end

  def self.find_all
    order(:year)
  end

  def self.find_for_type_position_year(type, position_id, year)
    where(type: type, position_id: position_id, year: year)
      .includes(:survey_groups, :position)
      .first!
  end

  def self.find_for_query(query)
    year = query[:year]
    position_id = query[:position_id]
    include_slots = query[:include_slots] || false
    type = query[:type]

    scope = includes(:position, :survey_groups).order(:year)
    scope = scope.where(year: year) if year
    scope = scope.where(position_id: position_id) if position_id
    scope = scope.where(type: type) if type

    user = Current.person
    results = scope.to_a.select { |row| row.can_manage_survey?(user) }
    return results if results.empty?

    # One query for the whole list, scoped to the surveys themselves. The
    # slots' own has_responses alias cannot answer this: its EXISTS carries no
    # survey_id predicate, so it claims a sibling survey's answers when two
    # surveys share a position and year, and an Alpha answer carries no slot
    # at all.
    answered = SurveyAnswer.where(survey_id: results.map(&:id)).distinct.pluck(:survey_id).to_set

    results.each do |row|
      row.reports = row.report_list
      row.has_responses = answered.include?(row.id)
      row.slots = row.retrieve_slots if include_slots
    end
  end

  # The reports this survey produces: the main group, plus one for every group
  # that asked to stand on its own. The index links these and the report page
  # validates against them, so a link the index offers is never a report the
  # page rejects.
  #
  # A trainer-on-trainer survey is reported whole, one trainer at a time
  # (SurveyBuilder.all_trainers_report), and its groups are never rendered
  # separately -- listing them would offer links that render the same page.
  #
  # @return [Array<Hash>] { id: "main" or a survey_group id, title: String }
  def report_list
    reports = [{ id: "main", title: main_report_title }]
    return reports if type == TRAINER

    survey_groups.each do |group|
      next if group.type == SurveyGroup::TYPE_NORMAL

      reports << { id: group.get_report_id, title: group.get_report_title_default(type) }
    end

    reports
  end

  # What the survey's main group of questions is asking about. In-Person
  # Training rates the venue; an ART's main group is its general questions.
  def main_report_title
    case type
    when ALPHA
      "Alpha Overall Feedback"
    when TRAINER
      "Trainer-On-Trainer Feedback"
    else
      (position_id == Position::TRAINING) ? "Venue Feedback" : "General Questions"
    end
  end

  def retrieve_slots
    # SELECT-level EXISTS is idiomatic for computed columns in ActiveRecord
    Slot.select("slot.id, slot.begins, slot.ends, slot.timezone, slot.description, slot.signed_up, EXISTS (SELECT 1 FROM survey_answer WHERE slot_id=slot.id LIMIT 1) AS has_responses")
        .where(begins_year: year, position_id: position_id)
        .order(:begins)
  end

  def self.retrieve_all_for_trainer(person_id)
    where(id: SurveyAnswer.where(trainer_id: person_id).select(:survey_id))
      .includes(:position)
      .map do |s|
      {
        id: s.id,
        year: s.year,
        type: s.type,
        position_id: s.position_id,
        position_title: s.position&.title,
        title: s.title
      }
    end
      .sort_by { |s| s[:year] }
      .group_by { |s| s[:year] }
  end

  def self.find_all_for_trainer_year(person_id, year, type = nil)
    scope = where(id: SurveyAnswer.where(trainer_id: person_id).select(:survey_id))
              .includes(:position)
              .where(year: year)

    scope = if type.present?
              scope.where(type: type)
            else
              scope.where.not(type: ALPHA)
            end

    scope
  end

  def self.has_trainer_survey_for_position?(position_id)
    where(type: TRAINER, year: Current.year, position_id: position_id).exists?
  end

  def self.retrieve_unanswered_for_person_year(person_id, year, status)
    SurveyUnansweredFinder.new(person_id, year, status).call
  end

  def target_label
    TARGET_LABELS[type] || type
  end
end
