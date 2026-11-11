# frozen_string_literal: true

# One person's sign-up changes in a year, one entry per shift: who signed them
# up and who removed them, when, and the rule each change set aside or the
# reason it gives. Read from the person-slot-add and person-slot-remove rows that
# Scheduling::Signup and its Bulk sweeps log. Deleting a shift logs no removal
# here (its sign-ups go with dependent: :destroy, as person-slot-delete rows);
# "slot deletion" rows are Clubhouse 2's. Person › Schedule Audit Log is its page;
# Person::SchedulingHelper puts what it returns into words.
class ScheduleLog
  # Clubhouse 2 began logging sign-ups to action_logs in 2019. legacy_log holds
  # Clubhouse 1's, but it is not a reliable record, so it is never read here.
  FIRST_YEAR = 2019

  EVENTS = %w[person-slot-add person-slot-remove].freeze

  # The rules a change can set aside, as the writers flag them in the row's
  # data (Scheduling::Signup), and the override each flag reports. A sign-up
  # after the shift began is flagged "started", a removal after it began "forced".
  OVERRIDE_FLAGS = {
    "overcapacity" => :overcapacity,
    "started" => :after_start,
    "forced" => :after_start,
    "multiple_enrollment" => :multiple_enrollment,
    "trainer_forced" => :trainer_forced,
    "unsigned_sandman_affidavit" => :unsigned_sandman_affidavit
  }.freeze

  # One sign-up (added) or removal. actor is nil once whoever made it is
  # deleted; actor_id stays. reason is a removal's stored message, when it says
  # more than "removed".
  Change = Data.define(:at, :added, :by_self, :actor_id, :actor, :overrides, :reason)

  # One shift. slot is nil once the shift is deleted; slot_id stays. signed_up
  # reads person_slot rather than the last change, so the roster has the last word.
  Entry = Data.define(:slot_id, :slot, :signed_up, :changes) do
    def deleted? = slot.nil?
    def sign_ups = changes.select(&:added)
    def removals = changes.reject(&:added)
    def overrides? = changes.any? { it.overrides.any? }
  end

  class << self
    # The changes made in +year+ to +person+'s sign-ups.
    #
    # @return [Array<Entry>] in shift order; a deleted shift sorts by its first change
    def retrieve(person, year)
      rows = ActionLog.where(target_person_id: person.id, event: EVENTS)
                      .where_year("created_at", year)
                      .order(:created_at, :id)
                      .includes(:person_summary)
      # Coerced, not read raw: some years' rows (2019's, 2021's) hold the slot id
      # as a String, which would split one shift in two. A row naming no shift (0)
      # has nowhere to go and is left out: Clubhouse 2 always named the shift, and
      # only an early delete_signup did not (see Scheduling::Signup::Bulk).
      by_slot = rows.group_by { ActionLog.slot_id_from_data(it.data) }.except(0)
      slots = Slot.where(id: by_slot.keys).includes(:position).index_by(&:id)
      held = PersonSlot.where(person_id: person.id, slot_id: by_slot.keys).pluck(:slot_id).to_set

      entries = by_slot.map do |slot_id, slot_rows|
        Entry.new(slot_id:, slot: slots[slot_id], signed_up: held.include?(slot_id),
                  changes: slot_rows.map { build_change(it, person) })
      end
      entries.sort_by { [it.slot&.begins || it.changes.first.at, it.slot_id] }
    end

    private

    # Every row that reaches here names a shift, so its data is a Hash.
    def build_change(row, person)
      added = row.event == "person-slot-add"
      Change.new(at: row.created_at, added:, by_self: row.person_id == person.id,
                 actor_id: row.person_id, actor: row.person_summary,
                 overrides: OVERRIDE_FLAGS.filter_map { |flag, override| override if row.data[flag] },
                 reason: (removal_reason(row.message) unless added))
    end

    # 2019's removals named the shift after "removed", which the page shows already.
    def removal_reason(message)
      message unless message.blank? || message.start_with?("removed")
    end
  end
end
