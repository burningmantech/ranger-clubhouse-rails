# frozen_string_literal: true

class Timesheet < ApplicationRecord
  self.table_name = "timesheet"

  # Review statuses
  STATUS_PENDING = "pending"
  STATUS_APPROVED = "approved"
  STATUS_REJECTED = "rejected"
  STATUS_VERIFIED = "verified"
  STATUS_UNVERIFIED = "unverified"

  REVIEW_STATUSES = [
    STATUS_PENDING,
    STATUS_APPROVED,
    STATUS_REJECTED,
    STATUS_VERIFIED,
    STATUS_UNVERIFIED
  ].freeze

  # Types for compute_years_for_person
  YEARS_AS_RANGER = "as-ranger" # All the years worked as a ranger
  YEARS_AS_CONTRIBUTOR = "as-contributor" # All the years worked as a contributor / non-ranger
  YEARS_ALL = "all"

  # Blocker codes
  BLOCKED_NOT_CHEETAH_CUB = "not-cheetah-cub" # Person is retired or inactive extension trying to sign into a non-Cheetah Cub shift
  BLOCKED_NOT_TRAINED = "not-trained" # Person is not trained (In-Person or ART)
  BLOCKED_NO_BURN_PERIMETER_EXP = "no-burn-perimeter-exp" # Person has no burn perimeter experience
  BLOCKED_NO_EMPLOYEE_ID = "no-employee-id" # Position is paid -- person has no employee id
  BLOCKED_TOO_EARLY = "too-early" # Person trying to sign in too early
  BLOCKED_TOO_LATE = "too-late" # Person trying to sign in too late
  BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT = "unsigned-sandman-affidavit"
  BLOCKED_IS_RETIRED = "is-retired" # Old blocker - retained for pre-2025 audit logs

  OLD_BLOCKERS = {
    "unsigned-sandman-affidavit" => BLOCKED_UNSIGNED_SANDMAN_AFFIDAVIT,
    "no-burn-perimeter-exp" => BLOCKED_NO_BURN_PERIMETER_EXP,
    "untrained" => BLOCKED_NOT_TRAINED,
    "is-retired" => BLOCKED_IS_RETIRED
  }.freeze

  EXCLUDE_POSITIONS_FOR_YEARS = [
    Position::ALPHA,
    Position::TRAINING
  ].freeze

  TOO_SHORT_LENGTH = 15 * 60 # 15 minutes in seconds

  # Associations
  belongs_to :person
  belongs_to :reviewer_person, class_name: "Person", optional: true
  belongs_to :verified_person, class_name: "Person", optional: true
  belongs_to :position
  belongs_to :desired_position, class_name: "Position", optional: true
  belongs_to :slot, optional: true

  has_many :timesheet_notes, dependent: :destroy
  has_many :timesheet_logs, dependent: :destroy
  has_one :created_log, -> { where(action: TimesheetLog::CREATED) }, class_name: "TimesheetLog"

  has_many :notes, -> { where.not(type: TimesheetNote::TYPE_ADMIN) }, class_name: "TimesheetNote"
  has_many :admin_notes, -> { where(type: TimesheetNote::TYPE_ADMIN) }, class_name: "TimesheetNote"
  has_many :user_notes, -> { where(type: TimesheetNote::TYPE_USER) }, class_name: "TimesheetNote"

  # Validations
  validates :person_id, presence: true
  validates :position_id, presence: true

  validates_datetime :on_duty
  validates :on_duty, presence: true

  validates_datetime :off_duty, allow_blank: true
  validates :off_duty, comparison: { greater_than_or_equal_to: :on_duty }, allow_nil: true, if: -> { on_duty.present? }

  validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true

  validates_datetime :desired_on_duty, allow_blank: true
  validates_datetime :desired_off_duty, allow_blank: true
  validates :desired_off_duty,
            comparison: {
              greater_than: :desired_on_duty,
              message: "The requested end time cannot be before the requested start time."
            }, if: -> { desired_off_duty.present? && desired_on_duty.present? }

  validate :is_reason_provided?

  # Virtual attributes for notes

  attribute :additional_notes, :string
  attribute :additional_wrangler_notes, :string
  attribute :additional_admin_notes, :string

  attr_accessor :photo_url, :time_warnings, :desired_warnings

  before_create :mark_echelon_status

  before_save :associate_slot, if: :should_associate_slot?
  before_save :clear_redundant_desired_values
  before_save :set_verification_fields

  after_save :adjust_roles
  after_save :handle_shift_end
  after_save :record_notes
  after_save :rebuild_awards_and_years, if: :off_duty_present?
  # after_update, not after_save: creation is logged by the call sites
  # (SIGNON, CREATED, back fill) — only corrections belong in the audit trail.
  after_update :log_updates

  after_destroy :adjust_roles
  after_destroy :log_deletion
  after_destroy :rebuild_awards_and_years

  # Scopes
  scope :for_year, ->(year) { where_year("on_duty", year) }
  scope :on_duty_now, -> { where(off_duty: nil) }
  # Entries that are open AND recent enough to describe somebody really out
  # there. An entry no one ever closed stands in for a person still on duty
  # forever; one whose start was mistyped into a future year does the same from
  # the other side, and being above the floor rather than below it, never ages
  # off. Both ends are built from one instant, so they cannot disagree about
  # the zone they are in. How far back is far enough differs by page, so the
  # caller says.
  scope :open_within, ->(window, as_of = Current.time) {
    on_duty_now.where(on_duty: (as_of - window)..as_of)
  }
  scope :for_person, ->(person_id) { where(person_id: person_id) }
  scope :for_position, ->(position_id) { where(position_id: position_id) }
  scope :ordered_by_on_duty, -> { order(:on_duty) }
  scope :with_off_duty, -> { where.not(off_duty: nil) }

  class << self
    # Find timesheet entries based on the given criteria
    def find_for_query(query)
      sql = all

      year = query[:year]
      person_id = query[:person_id]
      is_on_duty = query[:is_on_duty]
      duty_date = query[:duty_date]
      over_hours = query[:over_hours].to_i
      on_duty_start = query[:on_duty_start]
      on_duty_end = query[:on_duty_end]
      position_id = query[:position_id]
      position_ids = query[:position_ids]
      check_times = query[:check_times]

      sql = sql.for_year(year) if year.present?
      sql = sql.for_person(person_id) if person_id.present?

      if is_on_duty
        sql = sql.on_duty_now
        sql = sql.where("TIMESTAMPDIFF(HOUR, on_duty, ?) >= ?", Current.time, over_hours) if over_hours.positive?
      end

      if duty_date.present?
        sql = sql.where("on_duty <= ?", duty_date)
        sql = sql.where("COALESCE(off_duty, ?) >= ?", Current.time, duty_date)
      end

      sql = sql.where("on_duty >= ?", on_duty_start) if on_duty_start.present?
      sql = sql.where("on_duty <= ?", on_duty_end) if on_duty_end.present?
      sql = sql.for_position(position_id) if position_id.present?
      sql = sql.where(position_id: position_ids) if position_ids.present?

      sql = sql.includes(:position, :slot, :reviewer_person, :verified_person, :notes)
      sql = sql.includes(:person) unless person_id.present?

      # to_a, because the callsign re-sort below is destructive and a Relation
      # has no sort_by! — every caller until now passed person_id, which skips
      # that line, so the whole-position form of this query used to raise.
      rows = sql.ordered_by_on_duty.to_a
      rows.each(&:check_times) if check_times
      rows.sort_by! { |r| r.person.callsign.downcase } if person_id.blank?

      rows
    end

    # Find the (still) on duty timesheet for a person.
    #
    # Year-scoped, and the year is an argument only so a caller working on a
    # past event -- forming a pod on an old shift -- can ask about that year
    # instead. Everything asking about now leaves it alone.
    # Newest first. Someone holding two open entries is a data fault -- the one
    # the Mass Sign-Out page exists to clear -- but an unordered `first` answers
    # it with whatever the database returns, which for a year-wide scope is
    # usually the oldest. Pod#add_person! stamps the answer onto a membership
    # that Pod.shift_ended later looks up by that id, so picking the stale
    # entry means a sign-out that never stamps the member as having left.
    def find_person_on_duty(person_id, year = Current.year)
      for_year(year)
        .for_person(person_id)
        .on_duty_now
        .order(on_duty: :desc)
        .includes(:position)
        .first
    end

    # Check to see if a person is signed in to position(s)
    def person_signed_in?(person_id, position_ids)
      for_person(person_id)
        .on_duty_now
        .where(position_id: position_ids)
        .exists?
    end

    # Find everyone signed in to a given position
    def retrieve_signed_in_people(position_id)
      left_joins(:slot)
        .select("timesheet.person_id, timesheet.on_duty, slot.begins, timesheet.slot_id")
        .for_position(position_id)
        .on_duty_now
        .index_by(&:person_id)
    end

    # Find an existing overlapping timesheet entry for a date range
    def find_overlap_for_person(person_id, on_duty, off_duty)
      for_person(person_id)
        .where(
          "on_duty BETWEEN ? AND ? OR off_duty BETWEEN ? AND ? OR ? BETWEEN on_duty AND off_duty OR ? BETWEEN on_duty AND off_duty",
          on_duty, off_duty, on_duty, off_duty, on_duty, off_duty
        )
        .first
    end

    # Find all overlapping timesheets
    def find_all_overlaps_for_person(person_id, on_duty, off_duty, timesheet_id = nil)
      sql = for_person(person_id)
              .where(
                "on_duty BETWEEN ? AND ? OR off_duty BETWEEN ? AND ? OR ? BETWEEN on_duty AND off_duty OR ? BETWEEN on_duty AND off_duty",
                on_duty, off_duty, on_duty, off_duty, on_duty, off_duty
              )
              .includes(:position)
              .ordered_by_on_duty

      sql = sql.where.not(id: timesheet_id) if timesheet_id.present?

      sql
    end

    # Find an entry for a given person at a time within the given +/- minutes
    def find_shift_within_minutes(person_id, start_time, within_minutes)
      range_start = start_time - within_minutes.minutes
      range_end = start_time + within_minutes.minutes
      for_person(person_id)
        .where(on_duty: range_start..range_end)
        .includes(:position)
        .first
    end

    # Compute the years a person has worked
    def compute_years_for_person(person_id, type)
      if type == YEARS_ALL
        where(person_id: person_id)
          .with_off_duty
          .group("YEAR(on_duty)")
          .order(:year)
          .pluck("YEAR(on_duty) as year")
      else
        subquery = where(person_id: person_id)
                     .select("YEAR(on_duty) as year, SUM(TIMESTAMPDIFF(SECOND, on_duty, off_duty)) AS total_seconds")
                     .where.not(position_id: Position::TRAINING)
                     .where(
                       "position_id != ? OR EXISTS (
              SELECT 1 FROM person_mentor
              WHERE person_mentor.person_id = timesheet.person_id
              AND mentor_year = YEAR(on_duty)
              AND mentor_year >= 2025
              AND person_mentor.position_id = timesheet.position_id
              AND person_mentor.status = ?
              LIMIT 1
            )", Position::ALPHA, PersonMentor::STATUS_PASS)
                     .group("YEAR(on_duty)")

        subquery = subquery.where(is_echelon: true) if type == YEARS_AS_CONTRIBUTOR
        subquery = subquery.where(is_echelon: false) if type == YEARS_AS_RANGER

        from(subquery.arel.as("year_summary"))
          .where("year < 2025 OR total_seconds >= 21600")
          .order(:year)
          .pluck(:year)
      end
    end

    # Is the person a binary Ranger (0 or 1 years experience)?
    def person_binary?(person)
      return false unless person.status == Person::ACTIVE

      years = for_person(person.id)
                .where.not("YEAR(on_duty) = ?", Current.year)
                .where.not(position_id: EXCLUDE_POSITIONS_FOR_YEARS)
                .select("DISTINCT YEAR(on_duty)")

      years.count <= 1
    end

    # Find the latest timesheet entry for a person in a position and given year
    def find_latest_for_person_position(person_id, position_id, year)
      for_person(person_id)
        .for_position(position_id)
        .for_year(year)
        .order(on_duty: :desc)
        .first
    end

    # Find out how many years list of people have rangered
    def years_rangered_count_for_ids(person_ids)
      valid_ids = person_ids.select { |id| id.to_i.positive? }
      return {} if valid_ids.empty?

      Person.where(id: valid_ids)
            .pluck(:id, :years_as_ranger)
            .to_h { |id, years| [id, years.is_a?(Array) ? years.count : 0] }
    end

    # Does the given person have an Alpha entry for the given or current year?
    def alpha_entry?(person_id, year = nil)
      for_person(person_id)
        .for_year(year || Current.year)
        .for_position(Position::ALPHA)
        .exists?
    end

    # Retrieve all timesheets for the given people and position
    def retrieve_all_for_position_ids(person_ids, position_id)
      where(person_id: person_ids)
        .for_position(position_id)
        .ordered_by_on_duty
        .group_by(&:person_id)
        .transform_values { |rows| rows.group_by { |r| r.on_duty.year } }
    end

    # Count unverified timesheet entries for a person and year
    def count_unverified_for_person_year(person_id, year)
      for_person(person_id)
        .for_year(year)
        .where.not(review_status: STATUS_VERIFIED)
        .with_off_duty
        .count
    end

    # Did the person work one or more positions in the last X years?
    def did_person_work_position?(person_id, years, position_ids)
      cutoff = Current.year - years
      where(person_id: person_id)
        .where("on_duty >= ?", Time.local(cutoff))
        .where(position_id: position_ids)
        .limit(1)
        .exists?
    end

    # Find last worked positions
    def person_last_worked_any_position(person_id, position_ids)
      row = joins(:position)
              .select("position_id, YEAR(on_duty) as year, position.title")
              .for_person(person_id)
              .where(position_id: position_ids)
              .order(on_duty: :desc)
              .first

      return nil unless row

      { id: row.position_id, title: row.title, year: row.year }
    end

    # Did the given person work in a given year?
    def did_person_work?(person_id, year)
      for_person(person_id)
        .for_year(year)
        .where.not(position_id: Position::TRAINING)
        .limit(1)
        .exists?
    end

    # Did the person work a position in a specific year?
    def did_work_position_in_year?(person_id, position_id, year)
      for_person(person_id)
        .for_year(year)
        .for_position(position_id)
        .exists?
    end

    # Calculate credits earned for a year
    def earned_credits_for_year(person_id, year)
      rows = find_for_query(person_id: person_id, year: year)
      rows.sum(&:credits)
    end
  end

  # Instance methods

  # Calculate duration in seconds
  def duration
    return @duration if defined?(@duration)

    end_time = off_duty || Current.time
    @duration = (end_time - on_duty).to_i
  end

  # Calculate credits earned
  def credits
    return @credits if defined?(@credits)
    return 0.0 unless on_duty.present?

    end_time = off_duty || Current.time
    @credits = PositionCredit.compute_credits(
      position_id,
      on_duty.to_i,
      end_time.to_i,
      on_duty.year
    )
  end

  # Run a check on the on & off duty times
  def check_times
    return unless off_duty.present?

    self.time_warnings = Slot.check_date_time_for_position(position_id, on_duty, off_duty)

    return unless desired_position_id.present? || desired_on_duty.present? || desired_off_duty.present?

    self.desired_warnings = Slot.check_date_time_for_position(
      desired_position_id || position_id,
      desired_on_duty || on_duty,
      desired_off_duty || off_duty
    )
  end

  # Create a Timesheet audit log
  def log(action, data = nil)
    TimesheetLog.record(action, person_id, Current.person_id, id, data, on_duty.year)
  end

  # Build on duty info hash
  def build_on_duty_info
    {
      id: position_id,
      title: position.title,
      type: position.type,
      subtype: position.subtype
    }
  end

  # Get the created via information from the log
  def created_via
    created_log&.data&.dig("via")
  end

  def status_verified?
    review_status == STATUS_VERIFIED
  end

  def not_verified?
    review_status != STATUS_VERIFIED
  end

  def verification_required?
    [STATUS_UNVERIFIED, STATUS_APPROVED, STATUS_REJECTED].include?(review_status)
  end

  def corrections?
    review_status == STATUS_PENDING || review_status == STATUS_REJECTED
  end

  def status_rejected?
    review_status == STATUS_REJECTED
  end

  def status_pending?
    review_status == STATUS_PENDING
  end

  def status_approved?
    review_status == STATUS_APPROVED
  end

  # Suspiciously short shift — likely an accidental or mistimed check-in.
  def too_short?
    duration < TOO_SHORT_LENGTH
  end

  private

  def mark_echelon_status
    self.is_echelon = true if person&.status == Person::ECHELON
  end

  def should_associate_slot?
    !slot_id_changed? && on_duty.present? && position_id.present? &&
      (position_id_changed? || on_duty_changed?)
  end

  def associate_slot
    # Find sign up to associate with
    self.slot_id = Scheduling::Query.find_slot_id_sign_up_by_position_time(person_id, position_id, on_duty)

    return if slot_id.present?

    # Find matching slot from schedule
    start_time = on_duty - Scheduling::LOCATE_SHIFT_START_WITHIN
    end_time = on_duty + Scheduling::LOCATE_SHIFT_START_WITHIN

    slot = Slot.where(begins: (start_time..end_time)).where(position_id:).first

    self.slot_id = slot&.id
  end

  def clear_redundant_desired_values
    if desired_position_id_changed? && desired_position_id == position_id
      self.desired_position_id = nil
    end

    if desired_on_duty_changed? && on_duty.present? && desired_on_duty.present? && on_duty == desired_on_duty
      self.desired_on_duty = nil
    end

    if desired_off_duty_changed? && off_duty.present? && desired_off_duty.present? && off_duty == desired_off_duty
      self.desired_off_duty = nil
    end
  end

  def handle_shift_end
    return unless saved_change_to_off_duty?

    old_off_duty, new_off_duty = saved_changes["off_duty"]
    return unless old_off_duty.nil? && new_off_duty.present?

    # Shift ended - notify pod system
    Pod.shift_ended(person_id, id) if defined?(Pod)
  end

  def adjust_roles
    RoleManager.purge_person(person_id)
  end

  def record_notes
    user_id = Current.person_id
    entry_id = id

    if additional_notes.present?
      note_type = user_id == person_id ? TimesheetNote::TYPE_USER : TimesheetNote::TYPE_HQ_WORKER
      TimesheetNote.record(entry_id, user_id, additional_notes.strip, note_type)
    end

    if additional_admin_notes.present?
      TimesheetNote.record(entry_id, user_id, additional_admin_notes.strip, TimesheetNote::TYPE_ADMIN)
    end

    if additional_wrangler_notes.present?
      TimesheetNote.record(entry_id, user_id, additional_wrangler_notes.strip, TimesheetNote::TYPE_WRANGLER)
    end
  end

  def off_duty_present?
    off_duty.present?
  end

  def rebuild_awards_and_years
    return unless destroyed? || saved_change_to_on_duty? || saved_change_to_off_duty?

    AwardManagement.rebuild_for_person_id(person_id)
    YearsManagement.update_timesheet_years(person_id) if defined?(YearsManagement)
  end

  def log_deletion
    log(TimesheetLog::DELETE, {
      position_id: position_id,
      on_duty: on_duty.to_s,
      off_duty: off_duty.to_s
    })
  end

  def set_verification_fields
    if review_status_changed? && review_status == STATUS_VERIFIED
      self.verified_at = Current.time
      self.verified_person_id = Current.person_id
    end
  end

  # The PHP TimesheetController#update audit trail: record the old & new
  # values of the columns that changed, note verification flips, and keep the
  # existing logs findable under the entry's (possibly new) year.
  def log_updates
    audit_columns = {}
    %w[on_duty off_duty position_id review_status].each do |column|
      next unless saved_change_to_attribute?(column)

      old_value, new_value = saved_change_to_attribute(column)
      if column == "on_duty" || column == "off_duty"
        old_value = old_value.to_s
        new_value = new_value.to_s
      end
      audit_columns[column] = [old_value, new_value]
    end

    return if audit_columns.empty?

    did_verify = audit_columns.key?("review_status") && review_status == STATUS_VERIFIED
    did_unverify = audit_columns.key?("review_status") && review_status == STATUS_UNVERIFIED

    # Don't record a log that is only the verification flip.
    if audit_columns.size != 1 || (!did_verify && !did_unverify)
      log(TimesheetLog::UPDATE, audit_columns)
    end

    log(TimesheetLog::VERIFY) if did_verify
    log(TimesheetLog::UNVERIFIED) if did_unverify

    if saved_change_to_on_duty? && on_duty_before_last_save &&
       on_duty_before_last_save.year != on_duty.year
      TimesheetLog.update_year(id, on_duty.year)
    end
  end

  def is_reason_provided?
    unless notes.any? { |note| note.type == TimesheetNote::TYPE_USER } || additional_notes.present?
      errors.add(:additional_notes, "Give a reason for the correction.")
    end
  end
end
