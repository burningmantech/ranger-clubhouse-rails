# frozen_string_literal: true

class Provision < ApplicationRecord
  self.table_name = "provision"
  self.inheritance_column = "none"
  self.audit_model = true

  # Package class for provision summaries
  class Package
    attr_accessor :have_allocated,
                  :have_meals,
                  :meals,
                  :radios,
                  :showers,
                  :meals_expire,
                  :showers_expire,
                  :radio_expire

    # Nested class for meal period flags
    class Meals
      attr_accessor :pre, :event, :post

      def initialize(pre: false, event: false, post: false)
        @pre = pre
        @event = event
        @post = post
      end

      def title
        matrix = []
        matrix << "pre" if @pre
        matrix << "event" if @event
        matrix << "post" if @post
        return "no meals" if matrix.empty?
        TYPE_LABELS[matrix.join("+")] || "Unknown Meals"
      end
    end

    def initialize(have_allocated: false, have_meals: false, meals: nil, radios: 0, showers: false)
      @have_allocated = have_allocated
      @have_meals = have_meals
      @meals = meals || Meals.new
      @radios = radios
      @showers = showers
      @meals_expire = nil
      @showers_expire = nil
      @radio_expire = nil
    end
  end

  # Statuses
  AVAILABLE = "available"
  CLAIMED = "claimed"
  BANKED = "banked"
  USED = "used"
  CANCELLED = "cancelled"
  EXPIRED = "expired"
  SUBMITTED = "submitted"

  # Types
  EVENT_RADIO = "event_radio"
  WET_SPOT = "wet_spot"
  MEALS = "meals"

  ACTIVE_STATUSES = [AVAILABLE, CLAIMED, BANKED].freeze
  CURRENT_STATUSES = [AVAILABLE, CLAIMED, BANKED, SUBMITTED].freeze
  CAN_USE_STATUSES = [AVAILABLE, CLAIMED, SUBMITTED].freeze
  INVALID_STATUSES = [USED, CANCELLED, EXPIRED].freeze

  # The comment stamps the BMID export writes when it consumes a provision and
  # when an un-submitted batch returns one. The consumed stamp doubles as the
  # marker EventreeBmidExport.unsubmit! matches to find what a batch took.
  BMID_EXPORT_COMMENT = "Consumed by BMID export"
  BMID_UNSUBMIT_COMMENT = "Returned by BMID export un-submit"

  TYPE_LABELS = {
    EVENT_RADIO => "Event Radio",
    WET_SPOT => "Wet Spot Access",
    # Pseudo meal types - key built from {pre_event,event_week,post_event}_meals fields
    "pre+event+post" => "All Eats Pass",
    "event" => "Event Week Eat Pass",
    "pre" => "Pre-Event Eat Pass",
    "post" => "Post-Event Eat Pass",
    "pre+event" => "Pre-Event & Event Week Eat Pass",
    "event+post" => "Event Week & Post Event Eat Pass",
    "pre+post" => "Pre-Event & Post Event Eat Pass"
  }.freeze

  ALL_TYPES = [MEALS, EVENT_RADIO, WET_SPOT].freeze

  # Associations
  belongs_to :person

  # Virtual attributes
  attr_accessor :additional_comments

  # Callbacks
  before_save :set_default_item_count_for_radio
  before_save :set_expires_on_for_allocated
  before_save :prepend_additional_comments

  # Validations
  validate :allocated_cannot_be_banked
  validate :meals_must_have_period

  # Scopes
  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :current, -> { where(status: CURRENT_STATUSES) }
  scope :valid, -> { where.not(status: INVALID_STATUSES) }
  scope :can_use, -> { where(status: CAN_USE_STATUSES) }

  class << self
    # Find records matching given criteria.
    #
    # Query parameters:
    #   status: 'all' for all documents, or specific status(es)
    #   person_id: find for a specific person
    #   year: for a specific source_year
    #   type: specific provision type(s)
    #   include_person: include person association
    #   exclude_radio: exclude event radio provisions
    #   is_allocated: true for allocated only, false for earned only
    #
    def find_for_query(query)
      scope = order(:type, :source_year)

      status = query[:status]
      person_id = query[:person_id]
      year = query[:year]
      type = query[:type]
      include_person = query[:include_person]
      exclude_radio = query[:exclude_radio]
      is_allocated = query[:is_allocated]

      if status != "all"
        scope = if status.blank?
                  scope.where.not(status: INVALID_STATUSES)
                else
                  statuses = status.is_a?(Array) ? status : status.to_s.split(",")
                  scope.where(status: statuses)
                end
      end

      scope = scope.where(person_id: person_id) if person_id.present?

      if include_person
        scope = scope.includes(:person)
      end

      if type.present?
        types = type.is_a?(Array) ? type : type.to_s.split(",")
        scope = scope.where(type: types)
      end

      scope = scope.where(source_year: year) if year.present?
      scope = scope.where.not(type: EVENT_RADIO) if exclude_radio
      scope = scope.where(is_allocated: is_allocated) unless is_allocated.nil?

      if include_person
        scope.sort_by { |row| row.person&.callsign&.downcase || "" }
      else
        scope
      end
    end

    # Find provisions (available, claimed, banked, submitted) for the given person & type
    #
    # @param person_id [Integer]
    # @param type [String]
    # @param is_allocated [Boolean, nil]
    # @return [Provision, nil]
    def find_available_type_for_person(person_id, type, is_allocated: nil)
      scope = where(person_id:).where(type:).where(status: CURRENT_STATUSES)
      scope = scope.where(is_allocated:) unless is_allocated.nil?
      scope.first
    end

    # Find available meals provision for a person with specific meal periods
    def find_available_meals_for_person(person_id, is_allocated:, pre_meals:, event_meals:, post_meals:)
      where(person_id:)
        .where(type: MEALS)
        .where(status: CURRENT_STATUSES)
        .where(is_allocated:)
        .where(pre_event_meals: pre_meals)
        .where(event_week_meals: event_meals)
        .where(post_event_meals: post_meals)
        .first
    end

    # Retrieve all active records for a given type and list of people
    def retrieve_type_for_person_ids(type, person_ids)
      where(person_id: person_ids)
        .where(type:)
        .where(status: CAN_USE_STATUSES)
        .group_by(&:person_id)
    end

    # Retrieve the wellness provisions for a given set of people.
    #
    # Banked earned provisions are included if the person has allocated provisions.
    # (You get an allocated cookie, then all the cookies have to be used that year.)
    def retrieve_usable_for_person_ids(person_ids)
      allocated_person_ids = where(person_id: person_ids, is_allocated: true, status: CAN_USE_STATUSES)
                               .distinct
                               .pluck(:person_id)

      where(person_id: person_ids)
        .where(status: CAN_USE_STATUSES)
        .or(
          where(person_id: allocated_person_ids, status: BANKED)
        )
    end

    # Build a package summary from provisions
    #
    # @param provisions [Array<Provision>] The provisions to summarize
    # @return [Provision::Package] The package summary
    def build_package(provisions)
      showers = false
      have_allocated = false
      radios = 0
      pre_meals = false
      post_meals = false
      event_meals = false

      provisions.each do |provision|
        have_allocated = true if provision.is_allocated

        case provision.type
        when EVENT_RADIO
          count = provision.item_count.presence || 1
          radios = count if count > radios
        when WET_SPOT
          showers = true
        when MEALS
          pre_meals = true if provision.pre_event_meals
          post_meals = true if provision.post_event_meals
          event_meals = true if provision.event_week_meals
        end
      end

      Package.new(
        have_allocated: have_allocated,
        have_meals: pre_meals || event_meals || post_meals,
        meals: Package::Meals.new(pre: pre_meals, event: event_meals, post: post_meals),
        radios: radios,
        showers: showers
      )
    end

    # Does the person have allocated provisions?
    def have_allocated?(person_id)
      where(person_id: person_id)
        .where(status: [AVAILABLE, CLAIMED, SUBMITTED])
        .where(is_allocated: true)
        .exists?
    end

    # Retrieve all un-submitted earned provisions
    def retrieve_earned(person_id)
      where(person_id: person_id)
        .where(status: [AVAILABLE, CLAIMED, BANKED])
        .where(is_allocated: false)
    end

    # Find all item types for a given person, and mark as submitted (consumed).
    def mark_submitted_for_bmid(provisions)
      provisions.each do |row|
        row.status = SUBMITTED
        row.additional_comments = BMID_EXPORT_COMMENT
        row.audit_reason = BMID_EXPORT_COMMENT
        row.save(validate: false)
      end
    end

    # Inverse of mark_submitted_for_bmid, for un-submitting an export batch.
    # Everything goes back to available -- same landing status as the
    # un-submit maintenance function, whatever the provision was beforehand.
    def mark_unsubmitted_for_bmid(provisions)
      provisions.each do |row|
        row.status = AVAILABLE
        row.additional_comments = BMID_UNSUBMIT_COMMENT
        row.audit_reason = BMID_UNSUBMIT_COMMENT
        row.save(validate: false)
      end
    end

    # Find a record belonging to a person.
    def find_for_person(person_id, id)
      where(person_id: person_id).find(id)
    end

    # Populate meal matrix from a provision
    def populate_meal_matrix(provision, matrix)
      matrix[:pre] = true if provision.pre_event_meals
      matrix[:event] = true if provision.event_week_meals
      matrix[:post] = true if provision.post_event_meals
    end

    # Sort meals matrix into a string representation
    def sort_meals_matrix(matrix)
      return "all" if matrix.size == 3

      periods = []
      periods << "pre" if matrix[:pre]
      periods << "event" if matrix[:event]
      periods << "post" if matrix[:post]

      periods.join("+")
    end
  end

  # Add a comment to the comments column.
  def add_comment(comment, user)
    callsign = user.is_a?(Person) ? user.callsign : user
    timestamp = Current.time.strftime("%-m/%-d/%y %-H:%M:%S")
    self.comments = "#{timestamp} #{callsign}: #{comment}\n#{comments}"
  end

  # Setter for expires_on. Fix the date if it's only a year.
  def expires_on=(value)
    if value.present?
      value = value.to_s
      value = "#{value}-09-15" if value.length == 4
    end
    super
  end

  # Return true if the provision expired
  def past_expire_date?
    expires_on.present? && expires_on.year < Current.year
  end

  # Get the human-readable type label
  def type_label
    return TYPE_LABELS[type] || type unless type == MEALS

    periods = []
    periods << "pre" if pre_event_meals
    periods << "event" if event_week_meals
    periods << "post" if post_event_meals

    meal_type = periods.join("+")
    TYPE_LABELS[meal_type] || meal_type
  end

  # Is this a shower/wet spot type provision?
  def shower_type?
    type == WET_SPOT
  end

  # Display reference shown to admins and ticketing staff (e.g. "RP-1234")
  def display_ref
    "RP-#{id}"
  end

  private

  def set_default_item_count_for_radio
    return unless type == EVENT_RADIO && item_count.blank?

    self.item_count = 1
  end

  def set_expires_on_for_allocated
    return unless is_allocated && new_record?

    self.expires_on = Current.year
  end

  def prepend_additional_comments
    return if additional_comments.blank?

    timestamp = Current.time.strftime("%-m/%-d/%y %-H:%M:%S")
    callsign = Current.person&.callsign || "(unknown)"
    self.comments = "#{timestamp} #{callsign}: #{additional_comments}\n#{comments}"
  end

  def allocated_cannot_be_banked
    return unless is_allocated && status == BANKED

    errors.add(:status, "An allocated provision cannot be banked")
  end

  def meals_must_have_period
    return unless type == MEALS
    return if pre_event_meals || event_week_meals || post_event_meals

    errors.add(:status, "A meal provision must have at least one meal period selected.")
  end
end
