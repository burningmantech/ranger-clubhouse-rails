# frozen_string_literal: true

class Slot < ApplicationRecord
  self.table_name = "slot"

  # Related tables to be loaded with row
  WITH_POSITION_TRAINER = [
    :position,
    :trainer_slot
  ].freeze

  # Default timezone
  DEFAULT_TIMEZONE = "America/Los_Angeles"

  # Struct for sign-up results
  SignUpResults = Struct.new(
    :people, :max, :signed_up, :combined_max, :parent, :child, :assoc_signups,
    keyword_init: true
  )

  ParentChildInfo = Struct.new(
    :slot_id, :position_id, :position_title, :people, :signed_up, :max,
    keyword_init: true
  )

  AssociatedSignUp = Struct.new(
    :position_id, :position_title, :people,
    keyword_init: true
  )

  DateTimeCheckResult = Struct.new(
    :status, :begins, :ends, :start_status, :finished_status,
    keyword_init: true
  )

  DirtTimeSlot = Struct.new(
    :id, :position_id, :shift_start, :begins, :ends, :duration, :has_started, :has_ended,
    keyword_init: true
  )

  SignUpsInPeriodResult = Struct.new(:people, keyword_init: true)

  # Associations
  belongs_to :position
  belongs_to :trainer_slot, class_name: "Slot", optional: true
  belongs_to :parent_signup_slot, class_name: "Slot", optional: true

  has_one :child_signup_slot, class_name: "Slot", foreign_key: "parent_signup_slot_id"

  has_many :person_slot, dependent: :destroy
  has_many :trainer_status, foreign_key: "trainer_slot_id", dependent: :destroy
  has_many :trainee_statuses, class_name: "TraineeStatus", dependent: :destroy
  # A trainer's status names the session in slot_id and the trainer's own shift
  # in trainer_slot_id; both sides go with the slot, and so do the session's notes.
  has_many :session_trainer_statuses, class_name: "TrainerStatus", dependent: :destroy
  has_many :trainee_notes, dependent: :delete_all
  has_many :sign_ups, through: :person_slot, source: :person

  # Validations
  validates :begins, presence: true
  validates :ends, presence: true
  validates :description, length: { maximum: 40 }
  validates :url, length: { maximum: 512 }, allow_blank: true
  validates :max, presence: true, numericality: { only_integer: true }
  validates :position_id, presence: true, numericality: { only_integer: true }
  validates :trainer_slot_id, numericality: { only_integer: true }, allow_nil: true
  validates :parent_signup_slot_id, numericality: { only_integer: true }, allow_nil: true
  validate :begins_before_ends
  validate :no_circular_references
  validate :no_conflicting_slot_references

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_year, ->(year) { where(begins_year: year) }
  scope :for_position, ->(position_id) { where(position_id: position_id) }
  scope :ordered_by_begins, -> { order(:begins) }

  # Callbacks
  before_save :compute_time_fields
  after_destroy :cleanup_related_slots
  # A destroyed slot takes its statuses with it, and their own callbacks purge.
  after_commit :purge_training_role_caches, on: :update,
               if: -> { saved_change_to_active? || saved_change_to_begins_year? || saved_change_to_position_id? }

  # Training.did_person_pass_for_year? reads a session slot's position and year,
  # and whether a trainer's slot is active, and RoleManager caches its answer.
  # Purge everyone these slots scored or listed as a trainer.
  def self.purge_training_role_caches(slot_ids)
    person_ids = TraineeStatus.where(slot_id: slot_ids).distinct.pluck(:person_id) |
                 TrainerStatus.where(trainer_slot_id: slot_ids).distinct.pluck(:person_id)
    person_ids.each { |person_id| RoleManager.purge_person(person_id) }
  end

  #
  # Find slots based on the given criteria
  #
  # @param query [Hash] search criteria
  # @return [Array<Slot>]
  #
  def self.find_for_query(query)
    sql = includes(WITH_POSITION_TRAINER)

    year = query[:year]
    type = query[:type]
    position_id = query[:position_id]
    position_ids = query[:position_ids]
    for_rollcall = query[:for_rollcall]
    is_active = query[:active]

    sql = sql.for_year(year) if year
    sql = sql.where(type: type) if type
    sql = sql.for_position(position_id) if position_id
    sql = sql.where(position_id: position_ids) if position_ids
    sql = sql.where(active: is_active) unless is_active.nil?

    if for_rollcall
      now = Current.time
      sql = sql.where("begins < ?", now + 2.hours)
      sql = sql.where("begins > ?", now - 4.hours)
    end

    sql.ordered_by_begins
  end

  #
  # Find all the slots with sign-ups for a given year.
  #
  # @param year [Integer]
  # @param ctm_only [Boolean] filter by current user's teams
  # @return [Array<Slot>]
  #
  def self.find_with_signups_for_year(year, ctm_only: true)
    sql = for_year(year)
            .select("slot.*")
            .where("signed_up > 0")
            .includes(:position)
            .ordered_by_begins

    if ctm_only
      teams = TeamManager.find_for_person(Current.person&.id)
      return [] if teams.empty?

      sql = sql.joins(:position).where(position: { team_id: teams.pluck(:team_id) })
    end

    sql
  end

  #
  # Find all the signed up folks for a given slot.
  #
  # @param slot [Slot]
  # @param include_on_duty [Boolean]
  # @param include_photo [Boolean]
  # @return [SignUpResults]
  #
  def self.retrieve_sign_ups(slot, include_on_duty: false, include_photo: false)
    rows = Person.joins(:person_slot)
                 .where(person_slot: { slot_id: slot.id })
                 .select(:id, :callsign)
                 .order(:callsign)

    results = SignUpResults.new(people: rows, max: slot.max)

    signed_up = slot.signed_up
    combined_max = slot.max

    unless include_on_duty
      slot_with_relations = Slot.includes(
        :child_signup_slot, :parent_signup_slot,
        {
          parent_signup_slot: :position,
          child_signup_slot: :position
        }
      ).find(slot.id)

      parent_slot = slot_with_relations.parent_signup_slot
      if parent_slot
        combined_max = parent_slot.max
        parent_people = Person.joins(:person_slot)
                              .where(person_slot: { slot_id: parent_slot.id })
                              .select(:id, :callsign)
                              .order(:callsign)

        parent_count, signed_up = Scheduling::SlotCapacity.fold(
          parent_slot.signed_up, slot.signed_up, parent_slot.max, slot.max
        )

        results.parent = ParentChildInfo.new(
          slot_id: parent_slot.id,
          position_id: parent_slot.position_id,
          position_title: parent_slot.position&.title,
          people: parent_people,
          signed_up: parent_count,
          max: parent_slot.max
        )
      elsif slot_with_relations.child_signup_slot
        child_slot = slot_with_relations.child_signup_slot
        child_people = Person.joins(:person_slot)
                             .where(person_slot: { slot_id: child_slot.id })
                             .select(:id, :callsign)
                             .order(:callsign)

        signed_up, child_count = Scheduling::SlotCapacity.fold(
          signed_up, child_slot.signed_up, slot.max, child_slot.max
        )

        results.child = ParentChildInfo.new(
          slot_id: child_slot.id,
          position_id: child_slot.position_id,
          position_title: child_slot.position&.title,
          people: child_people,
          signed_up: child_count,
          max: child_slot.max
        )
      else
        results.max = Scheduling::SlotCapacity.new(slot).effective_max
      end

      results.signed_up = signed_up
      results.combined_max = combined_max

      positions = PositionLineup.retrieve_associated_positions(slot.position_id)
      return results unless positions

      assoc_signups = positions.map do |position|
        assoc_slot_id = Slot.where(position_id: position.id)
                            .where(active: true)
                            .where(begins: (slot.begins - 1.hour)..(slot.begins + 1.hour))
                            .pick(:id)

        signups = if assoc_slot_id
                    Person.joins(:person_slot)
                          .where(person_slot: { slot_id: assoc_slot_id })
                          .select(:id, :callsign)
                          .order(:callsign)
                  else
                    []
                  end

        AssociatedSignUp.new(
          position_id: position.id,
          position_title: position.title,
          people: signups
        )
      end

      results.assoc_signups = assoc_signups
      return results
    end

    results.signed_up = signed_up

    return results if rows.empty?

    ids = rows.pluck(:id)
    entries = Timesheet.where(person_id: ids)
                       .where(off_duty: nil)
                       .includes(:position)

    by_person = rows.index_by(&:id)
    entries.each do |entry|
      person = by_person[entry.person_id]
      next unless person

      person.define_singleton_method(:on_duty) do
        {
          id: entry.id,
          position: { id: entry.position.id, title: entry.position.title },
          on_duty: entry.on_duty,
          duration: entry.duration
        }
      end
    end

    if include_photo
      rows.each do |row|
        row.define_singleton_method(:photo_url) do
          PersonPhoto.retrieve_profile_url_for_person(row.id)
        end
      end
    end

    results
  end

  #
  # Find all people within a given period and interval.
  #
  # @param position_id [Integer]
  # @param period [String]
  # @param interval_minutes [Integer]
  # @return [SignUpsInPeriodResult]
  #
  def self.retrieve_sign_ups_in_a_period(position_id, period, interval_minutes)
    interval_seconds = interval_minutes * 60
    begins_time = period
    date = Time.zone.parse(period)
    ends_time = date + interval_seconds.seconds

    people = Slot.joins(person_slot: :person)
                 .where(position_id: position_id)
                 .for_year(date.year)
                 .where(
                   # Shift spans the entire period
                   "(slot.begins <= :begins AND slot.ends >= :ends) OR " +
                   "(slot.begins >= :begins AND slot.ends <= :ends) OR " +
                   "(slot.ends > :begins AND slot.ends <= :ends) OR " +
                   "(slot.begins >= :begins AND slot.begins < :ends)",
                   begins: begins_time, ends: ends_time)
                 .select("person.id", "person.callsign", "slot.begins")

    SignUpsInPeriodResult.new(people: people)
  end

  #
  # Find all the signs up for a given person, position, and year.
  #
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @param year [Integer]
  # @return [Slot, nil]
  #
  def self.find_first_sign_up(person_id, position_id, year)
    joins(:person_slot)
      .where(person_slot: { person_id: person_id })
      .for_position(position_id)
      .active
      .for_year(year)
      .ordered_by_begins
      .first
  end

  #
  # Find all the years we have slots for
  #
  # @return [Array<Integer>]
  #
  def self.find_years
    distinct.pluck(:begins_year).sort
  end

  #
  # Check to see if an activated slot exists for a given position in a given year.
  #
  # @param position_id [Integer|Array]
  # @param year [Integer] the year to check; defaults to the current year
  # @return [Boolean]
  #
  def self.have_active_for_position(position_id, year: Current.year)
    for_year(year)
      .for_position(position_id)
      .active
      .exists?
  end

  #
  # Retrieve all the dirt shifts for a given year
  #
  # @param year [Integer]
  # @return [Array<DirtTimeSlot>]
  #
  def self.retrieve_dirt_times(year)
    rows = for_year(year)
             .where(position_id: [Position::DIRT, Position::DIRT_PRE_EVENT, Position::DIRT_POST_EVENT])
             .active
             .ordered_by_begins

    rows.map do |row|
      DirtTimeSlot.new(
        id: row.id,
        position_id: row.position_id,
        shift_start: row.begins,
        begins: row.begins,
        ends: row.ends,
        duration: row.duration,
        has_started: row.has_started,
        has_ended: row.has_ended
      )
    end
  end

  #
  # Did the person sign up for an InPerson Training?
  #
  # @param person_id [Integer]
  # @param year [Integer]
  # @return [Boolean]
  #
  def self.have_training_sign_up(person_id, year)
    joins(:person_slot)
      .where(person_slot: { person_id: person_id })
      .active
      .for_year(year)
      .for_position(Position::TRAINING)
      .exists?
  end

  #
  # See if a given position and datetime is within the scheduled slot times.
  #
  # @param position_id [Integer]
  # @param start_time [Time]
  # @param finished_time [Time]
  # @param lenience_minutes [Integer]
  # @return [DateTimeCheckResult]
  #
  def self.check_date_time_for_position(position_id, start_time, finished_time, lenience_minutes: 15)
    sql = for_position(position_id).for_year(start_time.year).active

    return DateTimeCheckResult.new(status: "no-slots") unless sql.exists?

    first_slot = sql.ordered_by_begins.first
    last_slot = sql.order(ends: :desc).first

    begins_with_lenience = first_slot.begins - lenience_minutes.minutes
    ends_with_lenience = last_slot.ends + lenience_minutes.minutes

    start_status = if start_time.between?(begins_with_lenience, ends_with_lenience)
                     "success"
                   elsif start_time < begins_with_lenience
                     "before-begins"
                   else
                     "after-ends"
                   end

    finished_status = if finished_time.between?(begins_with_lenience, ends_with_lenience)
                        "success"
                      elsif finished_time < begins_with_lenience
                        "before-begins"
                      else
                        "after-ends"
                      end

    if start_status == "success" && finished_status == "success"
      return DateTimeCheckResult.new(status: "success")
    end

    DateTimeCheckResult.new(
      status: "out-of-range",
      begins: first_slot.begins,
      ends: last_slot.ends,
      start_status: start_status,
      finished_status: finished_status
    )
  end

  #
  # Is the slot part of a session group?
  #
  # @param our_description [String]
  # @param their_description [String]
  # @return [Boolean]
  #
  def self.part_of_session_group?(our_description, their_description)
    session_group_part(our_description).positive? &&
      session_group_part(their_description).positive? &&
      session_group_name(our_description) == session_group_name(their_description)
  end

  #
  # Find and return the session part number if it exists.
  #
  # @param description [String]
  # @return [Integer]
  #
  def self.session_group_part(description)
    match = description.match(/\bPart (\d)\b/i)
    match ? match[1].to_i : 0
  end

  #
  # Grab the session name minus any "- Part N" suffix.
  #
  # "Pre-Event - Part 1" becomes "Pre-Event"
  #
  # @param description [String]
  # @return [String, nil]
  #
  def self.session_group_name(description)
    match = description.match(/^(.*?)\s*-?\s*\bPart\s*\d\s*$/i)
    match ? match[1] : nil
  end

  # Instance Methods

  #
  # Retrieve the credits potential for the slot
  #
  # @return [Float]
  #
  def credits
    return 0.0 unless position_id

    PositionCredit.compute_credits(position_id, begins_time, ends_time, begins_year)
  end

  #
  # Retrieve the position title for the slot.
  #
  # @return [String]
  #
  def position_title
    position&.title || "Deleted ##{position_id}"
  end

  #
  # Is this slot an ART training slot?
  #
  # @return [Boolean]
  #
  def art?
    position_id != Position::TRAINING && position_id != Position::TRAINER
  end

  #
  # Humanized the begins datetime - for sending emails
  #
  # @return [String]
  #
  def begins_human_format
    begins.strftime("%A %b %d %Y @ %H:%M")
  end

  #
  # Humanized the ends datetime - for sending emails
  #
  # @return [String]
  #
  def ends_human_format
    ends.strftime("%A %b %d %Y @ %H:%M")
  end

  #
  # Has the shift started?
  #
  # @return [Boolean]
  #
  def has_started
    begins_adjusted < Current.time
  end

  #
  # Has the slot ended?
  #
  # @return [Boolean]
  #
  def has_ended
    ends_adjusted <= Current.time
  end

  #
  # Is the slot past the day it ends on?
  #
  # @return [Boolean]
  #
  def has_day_ended?
    adjusted = ends_adjusted
    return false unless adjusted
    return false if adjusted.future?

    !adjusted.to_date.eql?(Current.time.in_time_zone(effective_timezone).to_date)
  end

  #
  # How many seconds remaining in this shift?
  #
  # @return [Integer]
  #
  def remaining
    [ends_adjusted.to_i - Current.time.to_i, 0].max
  end

  #
  # Get the begins time adjusted for timezone
  #
  # @return [Time, nil]
  #
  def begins_adjusted
    adjust_timezone(begins)
  end

  #
  # Get the ends time adjusted for timezone
  #
  # @return [Time, nil]
  #
  def ends_adjusted
    adjust_timezone(ends)
  end

  #
  # Check to see if the slot begins within the pre-event period and is not a training slot
  #
  # @return [Boolean]
  #
  def pre_event_restricted?
    return false if begins.blank? || position_id.blank?

    event_date = EventDate.find_for_year(begins.year)
    return false unless event_date&.pre_event_slot_start && event_date&.pre_event_slot_end

    # Outside of Pre-Event period?
    return false if begins < event_date.pre_event_slot_start || begins >= event_date.pre_event_slot_end

    !training?
  end

  #
  # Is this a training slot? (either trainer or trainee)
  #
  # @return [Boolean]
  #
  def training?
    position&.type == Position::TYPE_TRAINING
  end

  # Computed column when slots are joined with the trainer_status table
  def trainer_status
    read_attribute(:trainer_status)
  end

  private

  def effective_timezone
    timezone.presence || DEFAULT_TIMEZONE
  end

  def adjust_timezone(time)
    return nil unless time

    time.in_time_zone(effective_timezone)
  end

  def begins_before_ends
    return unless begins && ends

    errors.add(:begins, "The start time must be before the end time.") if begins >= ends
  end

  def no_circular_references
    return unless persisted?

    if trainer_slot_id_changed? && trainer_slot_id
      if Slot.where(id: trainer_slot_id, trainer_slot_id: id).exists?
        errors.add(:trainer_slot_id, "This slot and the trainer slot cannot point to one another. On the trainer slot, the trainer multiplier slot should not be set.")
      end

      if id == trainer_slot_id
        errors.add(:trainer_slot_id, "The trainer multiplier slot cannot be set to itself.")
      end
    end

    if parent_signup_slot_id_changed? && parent_signup_slot_id
      if Slot.where(id: parent_signup_slot_id, parent_signup_slot_id: id).exists?
        errors.add(:parent_signup_slot_id, "This slot and the parent slot cannot point to one another. On the parent slot, the parent slot should be left blank.")
      end
    end
  end

  def no_conflicting_slot_references
    return unless parent_signup_slot_id && trainer_slot_id

    msg = "The parent sign-up slot and trainer sign-up slot cannot be set together."
    errors.add(:trainer_slot_id, msg)
    errors.add(:parent_signup_slot_id, msg)
  end

  # The derived columns, kept here rather than as generated columns because
  # timezone_abbr follows the zone's daylight-saving rule and begins_year the
  # app time zone: begins_time and ends_time are Unix epoch seconds of begins
  # and ends read in the slot's own zone (SignInBlocker compares them with a
  # timestamp), duration is ends_time minus begins_time in seconds, and
  # begins_year is the year of begins.
  def compute_time_fields
    if begins_changed? || timezone_changed?
      adjusted = begins_adjusted
      if adjusted
        tz_abbr = adjusted.strftime("%Z")
        tz_abbr = "UTC#{tz_abbr}" if tz_abbr.start_with?("+", "-")
        self.timezone_abbr = tz_abbr
      end
    end

    if begins_changed?
      self.begins_year = begins.year
      self.begins_time = begins_adjusted.to_i
    end

    if ends_changed?
      self.ends_time = ends_adjusted.to_i
    end

    if begins_changed? || ends_changed?
      self.duration = (ends_time || 0) - (begins_time || 0) if ends_time && begins_time
    end
  end

  def purge_training_role_caches
    Slot.purge_training_role_caches(id)
  end

  def cleanup_related_slots
    Slot.where(parent_signup_slot_id: id).update_all(parent_signup_slot_id: nil)
    Slot.where(trainer_slot_id: id).update_all(trainer_slot_id: nil)
  end
end
