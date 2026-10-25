# frozen_string_literal: true

# Day-by-day counts of Prospectives (PNVs) reaching intake milestones in a given
# year: application imported, account created, first login, photo approved,
# online course completed, training signup, training passed, dropped, and Alpha
# shift signup.
class SpigotFlowReport
  # Prior to this year the system of record for PNV applications was Salesforce;
  # the Clubhouse only saw approved accounts, so the 'imported' and 'created'
  # counts are identical.
  SALESFORCE_CUTOVER_YEAR = 2025

  # Bucket key used for photo approvals dated outside the reporting year. Sorts
  # ahead of any "YYYY-MM-DD" day key.
  PREVIOUS_YEAR_KEY = "0"

  # Report column labels, in display order.
  STAGE_LABELS = {
    imported: "Imported",
    created: "Created",
    first_login: "First login",
    photo_approved: "Photo approved",
    online_trained: "Online course",
    training_signups: "Training signup",
    training_passed: "Trained",
    dropped: "Dropped",
    alpha_signups: "Alpha signup"
  }.freeze

  # Column order shared by the report table and the CSV export.
  STAGES = STAGE_LABELS.keys.freeze

  # @param year [Integer] the intake year to report on
  # @return [Array<Hash>] one hash per day: {day: "YYYY-MM-DD" | PREVIOUS_YEAR_KEY,
  #   <stage>: [{id:, callsign:}, ...]} sorted by day, people sorted by callsign
  def self.execute(year)
    new(year).build
  end

  def initialize(year)
    @year = year
    # Datetimes are stored as machine-local wall clock (default_timezone :local),
    # which is not Time.zone (America/Phoenix), so a Time.zone boundary would
    # serialize an hour early. Same bounds where_year builds — kept inline here
    # because these queries need the range object itself, not just a predicate.
    @year_range = Time.local(year)...Time.local(year + 1)
    @dates = Hash.new { |days, day| days[day] = Hash.new { |stages, stage| stages[stage] = [] } }
    @pnv_imported_at = {}
  end

  def build
    return [] unless load_prospectives

    @callsigns = Person.where(id: pnv_ids).pluck(:id, :callsign).to_h
    load_first_logins
    load_dropped_statuses
    load_approved_photos
    load_online_training
    load_training_activity
    load_alpha_signups

    format_days
  end

  private

  def pnv_ids
    @pnv_imported_at.keys
  end

  def load_prospectives
    if @year < SALESFORCE_CUTOVER_YEAR
      load_prospectives_from_person_status
    else
      load_prospectives_from_applications
    end
  end

  # Pre-2025: only approved accounts existed in the Clubhouse, so imported ==
  # created. The MIN() covers rare duplicate conversions in the same year.
  def load_prospectives_from_person_status
    PersonStatus.where(new_status: Person::PROSPECTIVE, created_at: @year_range)
                .group(:person_id)
                .minimum(:created_at)
                .each do |person_id, converted_at|
      record_date(:imported, converted_at, person_id)
      record_date(:created, converted_at, person_id)
      @pnv_imported_at[person_id] = converted_at
    end
    @pnv_imported_at.any?
  end

  # 2025+: every application is stored. 'imported' counts all submissions;
  # 'created' counts only those that actually became Clubhouse accounts
  # (rejected, duplicate, or returning applications are filtered out).
  def load_prospectives_from_applications
    applications = ProspectiveApplication.where(created_at: @year_range)
                                         .order(:created_at)
                                         .pluck(:person_id, :created_at, :status)

    applications.each do |person_id, submitted_at, status|
      record_date(:imported, submitted_at, person_id)
      next unless status == ProspectiveApplication::STATUS_CREATED

      record_date(:created, submitted_at, person_id)
      @pnv_imported_at[person_id] = submitted_at
    end
    applications.any?
  end

  # The common case is handled with a single MIN() aggregate. The fallback
  # covers the rare person whose earliest in-year login predates their
  # (re)import — for those, walk their ordered logins for the first one at or
  # after the import.
  def load_first_logins
    first_logins = ActionLog.where(person_id: pnv_ids, event: "auth-login", created_at: @year_range)
                            .group(:person_id)
                            .minimum(:created_at)

    fallback_ids = []
    first_logins.each do |person_id, logged_in_at|
      if logged_in_at >= @pnv_imported_at[person_id]
        record_date(:first_login, logged_in_at, person_id)
      else
        fallback_ids << person_id
      end
    end
    return if fallback_ids.empty?

    post_import = ActionLog.where(person_id: fallback_ids, event: "auth-login", created_at: @year_range)
                           .order(:created_at)
                           .pluck(:person_id, :created_at)
                           .select { |person_id, logged_in_at| logged_in_at >= @pnv_imported_at[person_id] }

    seen = Set.new
    post_import.each do |person_id, logged_in_at|
      record_date(:first_login, logged_in_at, person_id) if seen.add?(person_id)
    end
  end

  def load_dropped_statuses
    PersonStatus.where(person_id: pnv_ids, new_status: Person::PAST_PROSPECTIVE,
                       created_at: @year_range)
                .group(:person_id)
                .minimum(:created_at)
                .each { |person_id, dropped_at| record_date(:dropped, dropped_at, person_id) }
  end

  # The upstream report joined through person.person_photo_id, but this app no
  # longer maintains that pointer and PersonPhoto#cleanup_photos keeps at most
  # one approved photo per person, so the approved status alone is equivalent.
  def load_approved_photos
    photos = PersonPhoto.approved.where(person_id: pnv_ids)
                        .pluck(:person_id, :reviewed_at, :uploaded_at)

    photos.each do |person_id, reviewed_at, uploaded_at|
      # Photos prior to 2020 have no reviewed_at — Lambase didn't expose it.
      approved_at = reviewed_at || uploaded_at
      if approved_at && @year_range.cover?(approved_at)
        record_date(:photo_approved, approved_at, person_id)
      else
        @dates[PREVIOUS_YEAR_KEY][:photo_approved] << person_id
      end
    end
  end

  def load_online_training
    completions = PersonOnlineCourse.where(person_id: pnv_ids, year: @year, position_id: Position::TRAINING)
                                    .where.not(completed_at: nil)
                                    .pluck(:person_id, :completed_at)
    completions.each { |person_id, completed_at| record_date(:online_trained, completed_at, person_id) }
  end

  def load_training_activity
    slot_ids = slot_ids_for(Position::TRAINING)
    return if slot_ids.empty?

    record_first_signups(:training_signups, slot_ids)

    TraineeStatus.passed.joins(:slot)
                 .where(person_id: pnv_ids, slot_id: slot_ids)
                 .group(:person_id)
                 .minimum("slot.begins")
                 .each { |person_id, begins| record_date(:training_passed, begins, person_id) }
  end

  def load_alpha_signups
    slot_ids = slot_ids_for(Position::ALPHA)
    return if slot_ids.empty?

    record_first_signups(:alpha_signups, slot_ids)
  end

  def slot_ids_for(position_id)
    Slot.for_position(position_id).for_year(@year).pluck(:id)
  end

  def record_first_signups(stage, slot_ids)
    PersonSlot.where(person_id: pnv_ids, slot_id: slot_ids)
              .group(:person_id)
              .minimum(:created_at)
              .each { |person_id, signed_up_at| record_date(stage, signed_up_at, person_id) }
  end

  # Reads come back cast into Time.zone, an hour ahead of the stored wall clock
  # for half the year. getlocal returns to the storage clock so the day bucket
  # agrees with @year_range — otherwise a late Dec 31 record is inside the window
  # but buckets under the following January.
  def record_date(stage, date, person_id)
    @dates[date.getlocal.strftime("%Y-%m-%d")][stage] << person_id
  end

  def format_days
    @dates.sort_by { |day, _stages| day }.map do |day, stages|
      row = { day: }
      stages.each do |stage, person_ids|
        row[stage] = person_ids.map { |person_id| describe_person(person_id) }
                               .sort_by { |person| person[:callsign].downcase }
      end
      row
    end
  end

  # Deleted account, rejected application, or id outside the cohort — keep the
  # slot in the count but blank the identity.
  def describe_person(person_id)
    callsign = @callsigns[person_id]
    return { id: "", callsign: "" } unless callsign

    { id: person_id, callsign: }
  end
end
