# frozen_string_literal: true

module Scheduling::Query
  class ScheduleEntry
    # Schedule entry attributes
    attr_accessor :slot,
                  :is_overlapping,
                  :credits,
                  :has_training_overlap,
                  :max_base,
                  :max_effective,
                  :overlapping_slots,
                  :person_assigned,
                  :position,
                  :position_id,
                  :signup_conflicts,
                  :year
  end

  # Result class for starting slots retrieval
  class StartingSlots
    attr_accessor :upcoming, :imminent, :locate_start_minutes

    def initialize(upcoming: [], imminent: [], locate_start_minutes: Scheduling::LOCATE_SHIFT_START_WITHIN)
      @upcoming = upcoming
      @imminent = imminent
      @locate_start_minutes = locate_start_minutes
    end
  end

  module_function
  # Find slots in the given year the person may potentially sign up for and/or
  # what slots the person is already signed up for.
  #
  # NOTE: A slot may be returned where the person no longer holds the position
  # yet still has the shift signup.
  #
  # @param person_id [Integer]
  # @param year [Integer]
  # @param query [Hash] options including :only_signups, :remaining, :positions_by_id
  # @return [Array] [slots, positions]
  def find_for_query(person_id, year, query = {})
    only_signups = query[:only_signups] || false
    remaining = query[:remaining] || false
    keep_positions_by_id = query[:positions_by_id] || false
    position_id = query[:position_id]
    no_credits = query[:no_credits] || false

    sql = Slot.select("slot.*, trainer_slot.signed_up as trainer_count")
              .joins("LEFT JOIN slot as trainer_slot ON trainer_slot.id = slot.trainer_slot_id")
              .where(begins_year: year)
              .order(:begins)
              .includes(:position, :parent_signup_slot, :child_signup_slot)

    if position_id
      sql = sql.where("slot.position_id" => position_id)
    end

    rows = if only_signups
             sql.joins(:person_slot).where(person_slot: { person_id: })
           else
             build_non_signup_query(sql, person_id)
           end

    positions_by_id = rows.each_with_object({}) do |row, hash|
      hash[row.position.id] = row.position
      row.position.slot_count = 0 if row.position.slot_count.nil?
      row.position.slot_count += 1
    end

    positions_by_id.each do |id, position|
      position.sign_ups = 0
    end

    adjust_parent_child_signups(rows)
    slots = build_schedule_entries(rows, year, only_signups, remaining)

    unless no_credits
      PositionCredit.warm_year_cache(year, positions_by_id.keys) if positions_by_id.any?
      # The entries' own rows, not `rows`: in remaining mode an ended row has no
      # entry, and the two lists are matched by index.
      PositionCredit.bulk_compute_credits(slots, slots.map(&:slot), year, :begins_time, :ends_time)
    end

    if only_signups
      scan_for_conflicts(slots)
      sign_ups_by_position = slots.group_by(&:position_id)
    elsif slots.any? && position_id
      sign_ups_by_position = scan_cross_position_overlaps(slots, person_id, year, position_id)
    elsif slots.any?
      sign_ups, _ = find_for_query(person_id, year, only_signups: true, no_credits: true)
      sign_ups_by_position = sign_ups.group_by(&:position_id)
      sign_ups.each do |sign_up|
        next unless sign_up.overlapping_slots
        slot = slots.find { |s| s.slot.id == sign_up.slot.id }
        if slot
          slot.overlapping_slots = sign_up.overlapping_slots
        end

        sign_up.overlapping_slots.each do |conflict|
          slot = slots.find { |s| s.slot.id == conflict.slot.id }
          next unless slot && !slot.overlapping_slots
          slot.overlapping_slots = [sign_up, *sign_up.signup_conflicts&.filter { |s| s.slot.id != slot.slot.id } || []]
          slot.overlapping_slots.sort_by! { |s| s.slot.begins_time }
        end
      end
    else
      sign_ups_by_position = nil
    end

    if position_id
      if sign_ups_by_position && sign_ups_by_position[position_id]
        positions_by_id[position_id].sign_ups = sign_ups_by_position[position_id].size
      end
    else
      sign_ups_by_position&.each do |slot_position_id, sign_up_slots|
        positions_by_id[slot_position_id].sign_ups = sign_up_slots.size
      end
    end

    positions = keep_positions_by_id ? positions_by_id : positions_by_id.values.sort_by!(&:title)
    [slots, positions]
  end

  # Partition schedule entries into [upcoming, past] using an explicit, named time cutoff.
  #
  # The cutoff is the deliberate decision point and differs by view intent:
  #   :start_time  -> an entry is "past" once its slot has_started (used by the
  #                   Available Sign-Ups view, because sign-up closes at slot start).
  #   :end_time    -> an entry is "past" once its slot has_ended (used by the My
  #                   Schedule view, because an in-progress shift is still a current commitment).
  #
  # An in-progress shift (has_started && !has_ended) is upcoming under :end_time and
  # past under :start_time. This divergence is intentional and is the whole reason
  # cutoff is a required keyword with no default.
  #
  # Order-preserving within each bucket and total-preserving:
  # upcoming.size + past.size == entries.size.
  #
  # @param entries [Array<ScheduleEntry>] pre-sorted by begins
  # @param cutoff  [Symbol] :start_time or :end_time
  # @return [Array(Array<ScheduleEntry>, Array<ScheduleEntry>)] [upcoming, past]
  def partition_by_time(entries, cutoff:)
    case cutoff
    when :start_time
      entries.partition { |entry| !entry.slot.has_started }
    when :end_time
      entries.partition { |entry| !entry.slot.has_ended }
    else
      raise ArgumentError, "unknown cutoff #{cutoff.inspect} (expected :start_time or :end_time)"
    end
  end

  # Find the next shift for a person
  #
  # @param person_id [Integer]
  # @return [PersonSlot, nil]
  def find_next_shift(person_id)
    PersonSlot.select("position.title, slot.description, slot.begins")
              .joins(slot: :position)
              .where(person_id:)
              .where("slot.begins > ?", Current.time)
              .order("slot.begins")
              .first
  end

  # Find the slots where the person signed up beginning within +/- minutes of now.
  #
  # @param person_id [Integer]
  # @return [StartingSlots]
  def retrieve_starting_slots_for_person(person_id)
    now = Current.time
    rows = PersonSlot.joins(:slot)
                     .where("slot.begins_year = ?", now.year)
                     .where("slot.begins >= ?", now - Scheduling::LOCATE_SHIFT_START_WITHIN)
                     .where(person_id: person_id)
                     .includes(slot: :position)
                     .order("slot.begins")

    upcoming = []
    imminent = []

    early_time = Setting.get_value(Setting::SHIFT_CHECK_IN_EARLY_PERIOD).to_i

    rows.each do |row|
      slot = row.slot
      start = slot.begins - early_time.minutes
      within_start = start <= now

      shift = Scheduling::Summaries.build_shift_info(row, slot, early_time, within_start, now, start)

      if (slot.begins - Scheduling::LOCATE_SHIFT_START_WITHIN) >= now
        upcoming << shift
      else
        imminent << shift
      end
    end

    StartingSlots.new(upcoming: upcoming, imminent: imminent)
  end

  # Does a person have multiple enrollments for the same position?
  #
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @param year [Integer]
  # @return [Array] [has_multiple, enrollments]
  def multiple_enrollments?(person_id, position_id, year)
    slot_ids = find_enrolled_slot_ids(person_id, year, position_id)

    return [false, nil] if slot_ids.empty?

    enrollments = Slot.where(id: slot_ids).includes(:position)
    [true, enrollments]
  end

  # Can the person join the training session?
  #
  # @param person_id [Integer]
  # @param slot [Slot]
  # @return [Array] [can_join, enrollments]
  def can_join_training_slot?(person_id, slot)
    year = slot.begins_year
    position_id = slot.position_id

    slot_ids = find_enrolled_slot_ids(person_id, year, position_id)
    return [true, nil] if slot_ids.empty?

    slots = Slot.where(id: slot_ids).includes(:position)
    return [false, slots] if slots.count >= 2

    slots.each do |row|
      return [true, nil] if Slot.part_of_session_group?(row.description, slot.description)
    end

    [false, slots]
  end

  # Find all slot ids the person is signed up for a given year and position
  #
  # @param person_id [Integer]
  # @param year [Integer]
  # @param position_id [Integer]
  # @return [Array<Integer>]
  def find_enrolled_slot_ids(person_id, year, position_id)
    find_enrolled_slots(person_id, year, position_id).pluck(:slot_id)
  end

  # Find all slot rows the person is signed up for a given year and position
  #
  # @param person_id [Integer]
  # @param year [Integer]
  # @param position_id [Integer]
  # @return [ActiveRecord::Relation]
  def find_enrolled_slots(person_id, year, position_id)
    PersonSlot.where(person_id: person_id)
              .joins(:slot)
              .where(slot: { position_id: position_id, begins_year: year })
              .order("slot.begins")
  end

  # Find the (probable) slot sign up for a person based on the position and time
  #
  # @param person_id [Integer]
  # @param position_id [Integer]
  # @param begins [Time, String]
  # @return [Integer, nil]
  def find_slot_id_sign_up_by_position_time(person_id, position_id, begins)
    time = begins.is_a?(String) ? Time.zone.parse(begins) : begins
    start_time = time - Scheduling::LOCATE_SHIFT_START_WITHIN
    end_time = time + Scheduling::LOCATE_SHIFT_START_WITHIN

    PersonSlot.joins(:slot)
              .where(person_id: person_id)
              .where(slot: { begins: start_time..end_time, position_id: position_id })
              .pluck(:slot_id)
              .first
  end

  # Does the person have a sign-up occurring in the Burn Weekend?
  #
  # @param person [Person]
  # @return [Boolean]
  def burn_weekend_signup?(person)
    start_date, end_date = EventDate.retrieve_burn_weekend_period
    signup_in_period?(person.id, start_date, end_date)
  end

  # Have dirt shifts opened up?
  #
  # @return [Boolean]
  def dirt_shifts_available?
    Slot.where(active: true, begins_year: Current.year, position_id: Position::DIRT).exists?
  end

  # Determine if a person is signed up for a shift within a certain date range
  #
  # @param person_id [Integer]
  # @param start_date [Time]
  # @param end_date [Time]
  # @return [Boolean]
  def signup_in_period?(person_id, start_date, end_date)
    PersonSlot.joins(:slot)
              .where(person_id:)
              .where(slot: { begins_year: start_date.year })
              .merge(Slot.where(begins: start_date..end_date).or(Slot.where(ends: start_date..end_date)))
              .exists?
  end

  # Build query for non-signup-only queries
  def build_non_signup_query(sql, person_id)
    person_positions = PersonPosition.where(person_id:).pluck(:position_id)
    quoted_person_id = ActiveRecord::Base.connection.quote(person_id.to_i)
    sql = sql.joins("LEFT JOIN person_slot ON person_slot.person_id = #{quoted_person_id} " \
                      "AND slot.id = person_slot.slot_id")
             .select("IF(person_slot.person_id IS NULL, FALSE, TRUE) as person_assigned")

    if person_positions.any?
      sql.where("person_slot.person_id IS NOT NULL OR slot.position_id IN (?)", person_positions)
    else
      sql.where("person_slot.person_id IS NOT NULL")
    end
  end

  # Adjust signup counts for parent/child slots
  def adjust_parent_child_signups(rows)
    rows.each do |row|
      child = row.child_signup_slot
      next unless child

      found = rows.find { |r| r.id == child.id }
      next unless found

      row.signed_up, found.signed_up = Scheduling::SlotCapacity.fold(
        row.signed_up, found.signed_up, row.max, found.max
      )
    end
  end

  # Build schedule entries from slot rows
  def build_schedule_entries(rows, year, only_signups, remaining)
    slots = []

    rows.each do |row|
      next if remaining && row.has_ended

      entry = ScheduleEntry.new
      slots << entry

      entry.slot = row
      entry.is_overlapping = false
      entry.person_assigned = only_signups || (row.person_assigned == true || row.person_assigned == 1)
      entry.position = row.position
      entry.position_id = row.position.id
      entry.max_base = row.max
      # Freshness contract for the query/display path: the trainer count rides along
      # as a joined trainer_count column. The guard + multiply live in SlotCapacity.
      entry.max_effective = Scheduling::SlotCapacity.new(row).effective_max(trainer_signed_up: row.trainer_count)
      entry.year = year
    end

    slots
  end

  # Detect cross-position overlaps for position_id mode.
  # For each slot in the selected position, check if the person has signups
  # in other held positions that overlap in time.
  #
  # @param slots [Array<ScheduleEntry>] entries for the selected position
  # @param person_id [Integer]
  # @param year [Integer]
  # @param selected_position_id [Integer]
  # @return [Hash, nil] sign_ups_by_position keyed by position_id
  def scan_cross_position_overlaps(slots, person_id, year, selected_position_id)
    authorized_position_ids = PersonPosition.where(person_id:).pluck(:position_id)
    other_position_ids = authorized_position_ids - [selected_position_id]

    # Detect same-position overlaps among signed-up entries and propagate to all slots
    signed_up_entries = slots.select(&:person_assigned)
    scan_for_conflicts(signed_up_entries)

    signed_up_entries.each do |sign_up|
      next unless sign_up.overlapping_slots

      sign_up.overlapping_slots.each do |conflict|
        entry = slots.find { |s| s.slot.id == conflict.slot.id }
        next unless entry && !entry.overlapping_slots

        entry.overlapping_slots = [sign_up, *sign_up.overlapping_slots.filter { |s| s.slot.id != entry.slot.id }]
        entry.overlapping_slots.sort_by! { |s| s.slot.begins_time }
      end
    end

    sign_ups_by_position = signed_up_entries.group_by(&:position_id)
    return sign_ups_by_position if other_position_ids.empty?

    # Check ALL slots (not just signed-up ones) for cross-position overlaps,
    # so non-signed-up entries in the selected position can be flagged too.
    slots.each do |entry|
      conflicts = PersonSlot.joins(:slot)
                            .where(person_id:)
                            .where.not(slot_id: entry.slot.id)
                            .where(slot: { begins_year: year, position_id: other_position_ids })
                            .where("slot.begins_time < ? AND slot.ends_time > ?", entry.slot.ends_time, entry.slot.begins_time)
                            .order("slot.begins_time")
                            .includes(slot: :position)

      conflicts.each do |ps|
        conflict_slot = ps.slot
        conflict_position = conflict_slot.position

        if training_overlap?(entry.position, conflict_position)
          entry.has_training_overlap = true
        else
          entry.is_overlapping = true
          conflict_entry = ScheduleEntry.new
          conflict_entry.slot = conflict_slot
          conflict_entry.position = conflict_position
          conflict_entry.position_id = conflict_position.id
          (entry.overlapping_slots ||= []) << conflict_entry
        end
      end
    end

    sign_ups_by_position
  end

  # Check if two positions qualify for the training overlap exception
  # (Dirt Training + ART Training is considered acceptable)
  def training_overlap?(position_a, position_b)
    position_a.training? && position_b.training? &&
      ((position_a.id == Position::TRAINING && position_b.id != Position::TRAINING) ||
        (position_a.id != Position::TRAINING && position_b.id == Position::TRAINING))
  end

  def scan_for_conflicts(rows)
    # Sweep with an active set so all pairwise overlaps are detected when
    # three or more shifts overlap (a single previous-row pointer misses
    # A↔C when A, B, C all overlap).
    active = []

    rows.each do |row|
      row.is_overlapping = false
      row.has_training_overlap = false

      active.reject! { |r| r.slot.ends_time <= row.slot.begins_time }
      active.each { |prev| mark_conflict(prev, row) }
      active << row
    end
  end

  # Dirt Training + ART Training is an acceptable overlap; otherwise mark both
  # rows as conflicting and link them via overlapping_slots.
  def mark_conflict(prev_row, row)
    if row.position.training? && prev_row.position.training? &&
       ((row.position.id == Position::TRAINING && prev_row.position.id != Position::TRAINING) ||
         (row.position.id != Position::TRAINING && prev_row.position.id == Position::TRAINING))
      row.has_training_overlap = true
      prev_row.has_training_overlap = true
    else
      row.is_overlapping = true
      prev_row.is_overlapping = true
      (row.overlapping_slots ||= []) << prev_row
      (prev_row.overlapping_slots ||= []) << row
    end
  end
end
