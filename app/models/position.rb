# frozen_string_literal: true

class Position < ApplicationRecord
  self.table_name = "position"
  self.inheritance_column = "none"

  # Position Type Constants
  TYPE_COMMAND = "Command"
  TYPE_FRONTLINE = "Frontline"
  TYPE_HQ = "HQ"
  TYPE_LOGISTICS = "Logistics"
  TYPE_MENTORING = "Mentoring"
  TYPE_OTHER = "Other"
  TYPE_TRAINING = "Training"

  TYPES = [
    TYPE_COMMAND,
    TYPE_FRONTLINE,
    TYPE_HQ,
    TYPE_LOGISTICS,
    TYPE_MENTORING,
    TYPE_OTHER,
    TYPE_TRAINING
  ].freeze

  # Team Category Constants
  TEAM_CATEGORY_ALL_MEMBERS = "all_members"
  TEAM_CATEGORY_OPTIONAL = "optional"
  TEAM_CATEGORY_PUBLIC = "public"

  # Position ID Constants
  ALPHA = 1

  DIRT = 2
  DIRT_PRE_EVENT = 53
  DIRT_POST_EVENT = 120
  DIRT_SHINY_PENNY = 107

  MENTOR = 9
  MENTOR_LEAD = 15
  MENTOR_SHORT = 35
  MENTOR_APPRENTICE = 70
  MENTOR_MITTEN = 67
  MENTOR_KHAKI = 86
  MENTOR_RADIO_TRAINER = 72
  MENTOR_ALPHA_HOST = 193
  MENTOR_WHEEL_OF_MANY_WAYS = 172

  CHEETAH = 45
  CHEETAH_CUB = 46

  DIRT_GREEN_DOT = 4
  GREEN_DOT_LEAD = 14
  GREEN_DOT_LEAD_INTERN = 126
  GREEN_DOT_LONG = 28
  GREEN_DOT_MENTOR = 40
  GREEN_DOT_MENTEE = 50
  GREEN_DOT_TRAINING = 101
  GREEN_DOT_TRAINER = 100
  SANCTUARY = 54
  SANCTUARY_HOST = 68
  SANCTUARY_MENTEE = 123

  HQ_FULL_TRAINING = 31
  HQ_LEAD = 32
  HQ_LEADS_SHORTS_TRAINER = 233
  HQ_LEADS_SHORTS_TRAINING = 198
  HQ_LEAD_POST_EVENT = 227
  HQ_LEAD_PRE_EVENT = 118
  HQ_REFRESHER_TRAINING = 49
  HQ_RUNNER = 18
  HQ_SHORT = 33
  HQ_SUPERVISOR = 51
  HQ_TOD = 103
  HQ_TRAINER = 34
  HQ_WINDOW = 3
  HQ_WINDOW_POST_EVENT = 228
  HQ_WINDOW_PRE_EVENT = 117
  HQ_WINDOW_SANDMAN = 104

  DOUBLE_OH_7 = 21
  DOUBLE_OH_7_STANDBY = 110

  DPW_RANGER = 105
  NVO_RANGER = 168

  DEEP_FREEZE = 38

  OOD = 10
  DEPUTY_OOD = 87

  ART_SAFETY = 16
  ART_CAR_WRANGLER = 125

  BURN_COMMAND_TEAM = 99
  BURN_PERIMETER = 19
  BURN_QUAD_LEAD = 114
  BURN_JUMP_TEAM = 144
  FIRE_LANE = 143

  SANDMAN = 61
  SANDMAN_TRAINER = 108
  SANDMAN_TRAINING = 80
  SPECIAL_BURN = 27

  SITE_SETUP = 59
  SITE_SETUP_LEAD = 96
  SITE_TEARDOWN = 60
  SITE_TEARDOWN_LEAD = 97

  RSC_SHIFT_LEAD = 12
  RSC_SHIFT_LEAD_PRE_EVENT = 83
  ROC_STAR = 239

  OPERATIONS_MANAGER = 37

  DEPARTMENT_MANAGER = 106

  TROUBLESHOOTER = 91
  TROUBLESHOOTER_MENTEE = 127
  TROUBLESHOOTER_MENTOR = 128
  TROUBLESHOOTER_TRAINER = 129
  TROUBLESHOOTER_TRAINING = 94
  TROUBLESHOOTER_LEAL = 147
  TROUBLESHOOTER_LEAL_PRE_EVENT = 148
  TROUBLESHOOTER_PRE_EVENT = 149

  TRAINING = 13
  TRAINER = 23
  TRAINER_ASSOCIATE = 88
  TRAINER_UBER = 95

  TOW_TRUCK_DRIVER = 20
  TOW_TRUCK_MENTEE = 69
  TOW_TRUCK_TRAINING = 102
  TOW_TRUCK_TRAINER = 121

  TECH_ON_CALL = 113
  TECH_OPS = 24

  GERLACH_PATROL = 75
  GERLACH_PATROL_LEAD = 76
  GERLACH_PATROL_GREEN_DOT = 122
  GERLACH_PATROL_LONG = 145

  HOT_SPRINGS_PATROL_DRIVER = 39

  ECHELON_FIELD = 17
  ECHELON_FIELD_LEAD = 81
  ECHELON_FIELD_LEAD_TRAINING = 111

  LNT_OUTREACH = 73

  RSCI = 25
  RSCI_MENTOR = 92
  RSCI_MENTEE = 93
  RSC_DISPATCH = 71
  RSC_RESIDENT = 77
  RSC_SHIFT_COORD = 78
  RSC_WESL = 109
  RSCI_FB_CONSELOR = 64

  RNR = 11
  RNR_RIDE_ALONG = 115

  PERSONNEL_MANAGER = 63
  PERSONNEL_INVESTIGATOR = 82

  INTERCEPT = 5
  INTERCEPT_DISPATCH = 6
  INTERCEPT_OPERATOR = 66

  OPERATOR = 56
  OPERATOR_SMOOTH = 142

  LEAL = 7
  LEAL_MENTEE = 8
  LEAL_MENTOR = 85
  LEAL_PARTNER = 116
  LEAL_PRE_EVENT = 119

  QUARTERMASTER = 84
  QUARTERMASTER_LEAD = 146

  VEHICLE_MAINTENANCE_LEAD = 124
  VEHICLE_MAINTENANCE = 74

  VOLUNTEER_COORDINATOR = 112

  IMS_ADMIN = 89
  IMS_AUDIT = 90
  IMS_TRAINING = 62

  LOGISTICS_LEAD = 98
  LOGISTICS = 42
  LOGISTICS_MANAGER = 151

  REGIONAL_RANGER_NETWORK = 154

  SICK_TIME = 150

  TRAINER_RADIO_PRACTICE = 178
  TRAINING_RADIO_PRACTICE = 179

  # Training positions mapped to their associated trainers. A position missing
  # from here is invisible to every report that pairs a session with the people
  # who taught it, so a new trainer position belongs in this table on the day it
  # is created -- see PositionTest's guard on the trainer constants.
  #
  # Two entries deliberately diverge from upstream (clubhouse2 3766af48):
  # upstream teaches HQ Leads & Shorts with HQ_TRAINER alone and hands
  # HQ_LEADS_SHORTS_TRAINER to the Refresher, which has been inactive with no
  # slots since 2019. Both trainer positions staff the live Leads & Shorts
  # sessions, so both are listed against it here. Troubleshooter is absent
  # upstream altogether despite its trainer slots pairing 1:1 with its training
  # slots every year since 2019.
  TRAINERS = {
    TRAINING => [TRAINER, TRAINER_ASSOCIATE, TRAINER_UBER],
    GREEN_DOT_TRAINING => [GREEN_DOT_TRAINER],
    HQ_FULL_TRAINING => [HQ_TRAINER],
    HQ_LEADS_SHORTS_TRAINING => [HQ_TRAINER, HQ_LEADS_SHORTS_TRAINER],
    HQ_REFRESHER_TRAINING => [HQ_TRAINER],
    SANDMAN_TRAINING => [SANDMAN_TRAINER],
    TOW_TRUCK_TRAINING => [TOW_TRUCK_TRAINER],
    TROUBLESHOOTER_TRAINING => [TROUBLESHOOTER_TRAINER],
    TRAINING_RADIO_PRACTICE => [TRAINER_RADIO_PRACTICE]
  }.freeze

  # Maximum hours thresholds indicating potential issues for specific positions
  PROBLEM_HOURS = {
    OOD => 28,
    PERSONNEL_MANAGER => 28,
    GREEN_DOT_LEAD => 28,
    HQ_LEAD => 28,
    TOW_TRUCK_DRIVER => 28,
    MENTOR_SHORT => 17,
    GERLACH_PATROL => 15,
    GERLACH_PATROL_LEAD => 15,
    DEPUTY_OOD => 15,
    HOT_SPRINGS_PATROL_DRIVER => 15
  }.freeze

  SANDMAN_QUALIFIED_POSITIONS = [
    BURN_COMMAND_TEAM,
    BURN_PERIMETER,
    BURN_QUAD_LEAD,
    SANDMAN,
    SPECIAL_BURN
  ].freeze

  SURVEY_MANAGEMENT_POSITIONS = {
    ALPHA => [MENTOR],
    GREEN_DOT_TRAINING => [GREEN_DOT_TRAINER, GREEN_DOT_MENTOR, GREEN_DOT_MENTEE],
    HQ_FULL_TRAINING => [HQ_TRAINER],
    SANDMAN_TRAINING => [SANDMAN_TRAINER],
    TROUBLESHOOTER_TRAINING => [TROUBLESHOOTER_TRAINER, TROUBLESHOOTER_MENTOR, TROUBLESHOOTER_MENTEE]
  }.freeze

  SANDMAN_YEAR_CUTOFF = 5

  ART_GRADUATE_TO_POSITIONS = {
    TOW_TRUCK_TRAINING => {
      veteran: TOW_TRUCK_DRIVER,
      positions: [TOW_TRUCK_MENTEE],
      has_mentees: true
    },
    SANDMAN_TRAINING => {
      positions: [SANDMAN]
    },
    GREEN_DOT_TRAINING => {
      veteran: DIRT_GREEN_DOT,
      positions: [GREEN_DOT_MENTEE, SANCTUARY_MENTEE],
      has_mentees: true,
      # Minimum recent volunteering before a mentee may graduate (upstream
      # Position::ART_GRADUATE_TO_POSITIONS 'mentee_requirements').
      mentee_requirements: {
        shift_count: 3,
        hour_count: 18,
        event_count: 1,
        positions: [DIRT, DIRT_SHINY_PENNY, DIRT_PRE_EVENT, DIRT_POST_EVENT]
      }
    }
  }.freeze

  # Associations
  belongs_to :team, optional: true
  belongs_to :parent_position, class_name: "Position", optional: true
  belongs_to :training_position, class_name: "Position", optional: true

  has_many :position_roles, dependent: :destroy
  has_many :roles, through: :position_roles, class_name: "Role"

  has_many :person_position, dependent: :delete_all
  has_many :person_position_log, dependent: :delete_all
  has_many :members, -> { order(:callsign) }, through: :person_position, source: :person

  has_many :position_lineup_members, dependent: :destroy, class_name: "PositionLineupMember"
  # Through the join table: position_lineup carries no position_id, so a direct
  # has_many resolved to a column that does not exist and raised on every read.
  # :destroy would also take the whole lineup -- and its other members -- with
  # one position, so leaving the lineup standing is the dependent rule here.
  has_many :position_lineups, through: :position_lineup_members

  has_many :person_awards, dependent: :destroy

  has_many :child_positions, class_name: "Position", foreign_key: :parent_position_id, dependent: :nullify, inverse_of: :parent_position
  has_many :training_positions, class_name: "Position", foreign_key: :training_position_id, dependent: :nullify, inverse_of: :training_position

  has_many :slot, dependent: :destroy

  # Validations
  validates :title, presence: true, length: { maximum: 40 }
  validates :short_title, length: { maximum: 6 }, allow_nil: true
  validates :min, numericality: { only_integer: true }, allow_nil: true
  validates :max, numericality: { only_integer: true }, allow_nil: true
  validates :type, inclusion: { in: TYPES }, allow_nil: true
  validates :ranger_scheduling_header, :applicant_scheduling_header, length: { maximum: 65_535 }, allow_blank: true

  validate :validate_training_configuration
  validate :validate_parent_not_self
  validate :validate_art_mentoring

  # A header with no words is no header: an editor left as "<p></p>", or holding
  # only a divider, blanks (normalize_blank_attributes then stores nil), so the
  # sign-up page shows nothing. Stricter than BLANK_WHEN_EMPTY_RICH_TEXT, whose
  # divider-only and image-only cases are document pages.
  normalizes :ranger_scheduling_header, :applicant_scheduling_header,
             with: ->(html) { Nokogiri::HTML5.fragment(html).text.present? ? html : "" }

  # Callbacks
  before_validation :normalize_blank_attributes

  before_save :clear_awards_flags_unless_eligible

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered_by_title, -> { order(:title) }
  scope :with_team, -> { includes(:team) }
  scope :by_type, ->(type) { where(type: type) }
  scope :with_paycode, -> { where.not(paycode: [nil, ""]) }
  scope :mentor_positions, -> { where("title LIKE ?", "%mentor%") }
  scope :mentee_positions, -> { where("title LIKE ?", "%mentee%") }
  scope :awards_eligible, -> { where(awards_eligible: true) }
  scope :cruise_direction, ->(value) { where(cruise_direction: value) }

  # Attribute accessor for pseudo role_ids column
  attr_accessor :role_ids

  # Any blockers preventing the person from signing in to a shift.
  attr_accessor :blockers

  # For scheduling
  attr_accessor :sign_ups, :slot_count

  # For Team Management -- populated by find_for_query, never persisted.
  # Declared as a virtual attribute rather than attr_accessor so the SQL alias in
  # the non-admin branch is reachable (an attr_accessor reader shadows attribute
  # lookup) and boolean-cast (MariaDB returns 0/1, and 0 is truthy in Ruby).
  attribute :can_manage, :boolean

  # Class Methods

  # Find positions based on query criteria
  def self.find_for_query(query = {}, is_admin: false)
    scope = ordered_by_title

    scope = scope.where(type: query[:type]) if query[:type].present?
    scope = scope.active if query[:active] == true
    scope = scope.where(active: false) if query[:active] == false
    scope = scope.mentor_positions if query[:mentor]
    scope = scope.mentee_positions if query[:mentee]
    scope = scope.with_paycode if query[:has_paycode]
    scope = scope.cruise_direction(query[:cruise_direction]) if query.key?(:cruise_direction)
    scope = scope.awards_eligible if query[:awards_eligible]

    if query[:art_training]
      scope = scope.by_type(TYPE_TRAINING).where("title LIKE ?", "%Training%")
    end

    if query[:can_manage] && !is_admin
      # Include team manager check
      scope = scope
                .joins(sanitize_sql_array([
                  "LEFT JOIN team_manager ON team_manager.team_id = position.team_id AND team_manager.person_id = ?",
                  Current.person&.id
                ]))
                .select("position.*, (team_manager.team_id IS NOT NULL) AS can_manage")
    end

    positions = scope.load

    if query[:can_manage] && is_admin
      positions.each { |p| p.can_manage = true }
    end

    if query[:include_roles]
      positions.each(&:load_roles)
    end

    positions
  end

  # Find position by title
  def self.find_by_title(title)
    find_by(title: title)
  end

  # Retrieve title for a position ID, returns placeholder if not found
  def self.retrieve_title(position_id)
    where(id: position_id).pick(:title) || "Position ##{position_id}"
  end

  # Batch form of retrieve_title: one query, and ids with no row still
  # resolve to the same placeholder.
  def self.titles_by_id(position_ids)
    titles = where(id: position_ids).pluck(:id, :title).to_h
    titles.default_proc = ->(_hash, id) { "Position ##{id}" }
    titles
  end

  # Find all positions that reference the given training position
  def self.find_trained_positions(position_id)
    select(:id, :title).where(training_position_id: position_id)
  end

  # Find all positions with in-progress slots
  def self.find_all_with_in_progress_slots(ctm_only: true)
    now = Current.time

    # Subquery: slot is active, belongs to position, starts within 6 hours, and hasn't ended
    in_progress_slot = Slot.select("1")
                           .where(active: true)
                           .where("position_id = position.id")
                           .where(begins: ...(now + 6.hours))
                           .where("ends > ?", now)
                           .limit(1)

    scope = where.not(type: TYPE_TRAINING)
                 .where(active: true)
                 .where("EXISTS (:in_progress_slot)", in_progress_slot: in_progress_slot)
                 .includes(:team)
                 .order(:title)

    if ctm_only
      team_ids = TeamManager.where(person_id: Current.person&.id).pluck(:team_id)
      return [] if team_ids.empty?
      scope = scope.where(team_id: team_ids)
    end

    scope
  end

  # Retrieve all active positions, optionally filtered by CTM teams
  def self.retrieve_all_active(ctm_only: true)
    scope = active.includes(:team)

    if ctm_only
      team_ids = TeamManager.where(person_id: Current.person&.id).pluck(:team_id)
      return [] if team_ids.empty?
      scope = scope.where(team_id: team_ids)
    end

    scope.order(:title)
  end

  # Find all positions a person holds that are eligible for a vehicle type (mvr or pvr)
  def self.vehicle_eligible_for_person(vehicle_type, person_id)
    eligible_column = "#{vehicle_type}_eligible"

    joins(:person_position)
      .where(person_position: { person_id: person_id })
      .where(active: true)
      .where(eligible_column => true)
      .select(:id, :title)
      .order(:title)
      .load
  end

  # Check if person has any positions with vehicle eligibility
  def self.vehicle_potential?(vehicle_type, person_id)
    eligible_column = "#{vehicle_type}_eligible"

    joins(:person_position)
      .where(person_position: { person_id: person_id })
      .where(active: true)
      .where(eligible_column => true)
      .exists?
  end

  # Instance Methods

  # Load role IDs from position_roles association
  def load_roles
    self.role_ids = position_roles.pluck(:role_id)
  end

  # Returns the subtype based on position type and specific position IDs
  def subtype
    return type unless type == TYPE_MENTORING

    [ALPHA, CHEETAH_CUB].include?(id) ? "mentee" : "mentor"
  end

  def training?
    type == TYPE_TRAINING
  end

  # The note the sign-up page shows above this position's shifts, by the
  # reader's status: nil for anyone who is neither a Ranger, Echelon nor an
  # applicant (Prospective or Alpha), and for a position with nothing written.
  def scheduling_header_for(person)
    if person.is_ranger? || person.is_echelon?
      ranger_scheduling_header
    elsif person.is_applicant?
      applicant_scheduling_header
    end
  end

  # The description a newly created resource document carries.
  def build_resource_title
    "#{title} Position Document"
  end

  # The tag a newly created resource document is filed under. Reads always go
  # through the stored resource_tag, so this only names documents this app
  # mints -- which is why parameterize is used instead of a faithful port of
  # Laravel's Str::kebab. The two agree except on titles with adjacent
  # capitals ("HQ Full Training" -> "hq-full-training" here, "h-q-full-
  # training" upstream).
  def build_resource_tag
    "#{title.parameterize}-resource"
  end

  private

  # These messages name their own subject: config/locales/en.yml sets
  # `errors.format: "%{message}"`, so nothing prefixes the attribute name.
  def validate_training_configuration
    if require_training_for_roles && training_position_id.blank?
      errors.add(:require_training_for_roles,
                 "A training position is required while permissions wait on a training pass -- " \
                 "otherwise there is nothing to pass before they are granted")
    end

    if no_training_required && training_position_id.present?
      errors.add(:no_training_required,
                 "In-Person training cannot be marked unnecessary while a training position is set")
    end
  end

  def validate_parent_not_self
    if parent_position_id.present? && parent_position_id == id
      errors.add(:parent_position_id, "A position cannot be its own parent")
    end
  end

  # ART mentoring pairs a training with the mentor and mentee positions on its
  # own team (Training.mentor_position_id), so every flag needs a team, and a
  # team holds one of each: with two, the training could not tell which to pair.
  def validate_art_mentoring
    flags = { has_art_mentoring: "ART mentoring training", is_art_mentor: "ART mentor position",
              is_art_mentee: "ART mentee position" }.select { |flag, _name| self[flag] }
    return if flags.empty?

    if is_art_mentor && is_art_mentee
      errors.add(:is_art_mentee, "A position cannot be both the ART mentor and the ART mentee position")
    end

    # The app's own test for an ART: a training (not a trainer position) other
    # than In-Person Training, which has no graduate role to grant a pass.
    if has_art_mentoring && !(Training.training_position?(self) && Training.art?(self))
      errors.add(:has_art_mentoring, "Only an ART training position can have ART mentoring")
    end

    if team_id.blank?
      errors.add(:team_id, "A team is required for ART mentoring -- a training pairs the mentor and mentee " \
                           "positions on its own team")
      return
    end

    flags.each do |flag, name|
      holder = Position.where(team_id:, flag => true).where.not(id:).pick(:title)
      errors.add(flag, "#{holder} is already the #{name} for this team") if holder
    end
  end

  def normalize_blank_attributes
    self.paycode = nil if paycode.blank?
    self.resource_tag = nil if resource_tag.blank?
    self.short_title = nil if short_title.blank?
    self.contact_email = nil if contact_email.blank?
    # Nullable, like the four above: nil is "no header", and a form that posts
    # an empty editor must not turn NULL into "" and log a change no one made.
    self.ranger_scheduling_header = nil if ranger_scheduling_header.blank?
    self.applicant_scheduling_header = nil if applicant_scheduling_header.blank?
  end

  def clear_awards_flags_unless_eligible
    return if awards_eligible

    self.awards_auto_grant = false
    self.awards_grants_service_year = false
  end
end
