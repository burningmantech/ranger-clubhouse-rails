# frozen_string_literal: true

# Timesheet entries pointing at the wrong scheduled shift, and the repair that
# relinks them.
#
# An entry records the shift it belongs to when it is saved. Entries created
# before the schedule existed, or whose position or start time moved
# afterwards, can end up pointing at a shift that no longer fits, or at
# nothing at all. This finds those and offers to set them right.
#
# The matching rule is the model's own rule, in the same order: the person's
# own sign-up first, then any shift for that position starting close enough,
# then nothing.
class TimesheetSlotRepair
  # How far either side of a check-in a shift may start and still count as the
  # same shift. Deliberately the value the model uses when it links a shift on
  # save -- a repair measuring differently would undo links the model had just
  # made.
  MATCH_WINDOW = Scheduling::LOCATE_SHIFT_START_WITHIN

  # Why a shift was chosen, in the order the two are tried.
  SIGNED_UP = :signed_up
  ONLY_MATCH = :only_match

  # Recorded against every entry the repair touches.
  AUDIT_REASON = "slot assoc. repair"

  # The three groups, in the order the page shows them.
  KINDS = %i[add change remove].freeze

  # One shift, as a row needs to show it. position_title is the shift's own
  # position, which is the point of showing it: an entry can be linked to a
  # shift belonging to some other position entirely.
  Shift = Data.define(:id, :position_title, :begins, :description)

  # One entry that should be relinked, with both ends of the change and enough
  # about the person to render a row.
  #
  # The two ids are kept alongside the two shifts because they are not the same
  # question: a link can point at a shift row that has since been deleted, and
  # then the id is present while the shift is nil.
  Change = Data.define(:timesheet_id, :person_id, :callsign, :status,
                       :position_title, :on_duty,
                       :old_slot_id, :new_slot_id, :old_shift, :new_shift, :reason) do
    # What kind of change this is, which is also how the page groups them.
    # Asked of the ids, so an entry whose shift row is gone still counts as
    # having had a link.
    def kind
      return :add if old_slot_id.nil?
      return :remove if new_slot_id.nil?

      :change
    end

    def key = timesheet_id.to_s

    # Whether the entry starts ticked and "select all" arms it. Removals do
    # not: dropping a link loses the only record of which shift the entry
    # belonged to, while adding or moving one does not, so somebody has to
    # choose each removal deliberately.
    def offered? = kind != :remove
  end

  # What one applied change did, for the results list.
  Result = Data.define(:callsign, :message, :error)

  # An entry to relink, before the callsigns and shift details are filled in.
  Proposal = Struct.new(:timesheet_id, :person_id, :on_duty,
                        :old_slot_id, :new_slot_id, :reason)
  private_constant :Proposal

  class << self
    # How many entries were looked at, and every change the repair would make,
    # sorted by callsign then check-in. Reads only -- nothing is written until
    # .apply. Both halves come from one read of the year, so the count always
    # describes the list beside it.
    def scan(year)
      entries = entries_for(year)
      [entries.size, changes_in(entries, year)]
    end

    # Just the changes, for callers with no summary line to fill in.
    def preview(year) = scan(year).last

    # Apply the changes whose entry ids were submitted, and only those.
    #
    # The submitted ids select from a freshly computed preview; they never say
    # what to link to. A change that is no longer proposed -- settled by
    # somebody else, or from a page left open while the schedule moved -- is
    # counted as skipped rather than written.
    #
    # Returns [results, skipped].
    def apply(year, timesheet_ids)
      wanted = Array(timesheet_ids).map(&:to_s).to_set
      selected = preview(year).select { wanted.include?(_1.key) }

      [selected.map { write(_1) }, wanted.size - selected.size]
    end

    private

    def changes_in(entries, year)
      return [] if entries.empty?

      proposals = propose(entries, schedule_for(year), linked_slots(entries))
      return [] if proposals.empty?

      decorate(proposals)
    end

    def entries_for(year)
      Timesheet.for_year(year).order(:id)
               .pluck(:id, :person_id, :position_id, :on_duty, :slot_id)
    end

    # Every shift of the year that could match, grouped by position and sorted
    # by start time, plus who signed up for them. begins_year is indexed
    # alongside position_id.
    def schedule_for(year)
      rows = Slot.for_year(year).pluck(:id, :position_id, :begins)

      # Sorted by start then id, so two shifts opening at the same minute
      # always resolve the same way.
      by_position = rows.group_by { |_id, position_id, _begins| position_id }
                        .transform_values { |group| group.sort_by { |id, _pos, begins| [begins, id] } }

      signed_up = PersonSlot.joins(:slot).where(slot: { begins_year: year })
                            .pluck(:person_id, :slot_id)
                            .group_by(&:first)
                            .transform_values { |pairs| pairs.map(&:last).to_set }

      { by_position:, signed_up: }
    end

    # The shifts the entries already point at. Read separately from the year's
    # own schedule because a mislinked entry can point at a shift outside it.
    def linked_slots(entries)
      ids = entries.filter_map(&:last).uniq
      return {} if ids.empty?

      Slot.where(id: ids).pluck(:id, :position_id, :begins)
          .to_h { |id, position_id, begins| [id, [position_id, begins]] }
    end

    def propose(entries, schedule, linked)
      entries.filter_map do |id, person_id, position_id, on_duty, slot_id|
        from = on_duty - MATCH_WINDOW
        to = on_duty + MATCH_WINDOW

        next if still_correct?(linked[slot_id], position_id, from, to)

        new_slot_id, reason = best_match(schedule, person_id, position_id, from, to)
        next if new_slot_id == slot_id

        Proposal.new(id, person_id, on_duty, slot_id, new_slot_id, reason)
      end
    end

    # The linked shift still holds if it belongs to the entry's position and
    # starts inside the window. Both halves matter: a shift for the right
    # position days away from the check-in is as wrong as one for the wrong
    # position. The window is measured the same way here as when a new shift
    # is searched for, so a shift sitting exactly on the edge is never dropped
    # and re-found.
    def still_correct?(linked, position_id, from, to)
      return false if linked.nil?

      slot_position_id, begins = linked
      slot_position_id == position_id && begins >= from && begins <= to
    end

    # The person's own sign-up wins; failing that, the earliest shift for the
    # position inside the window.
    def best_match(schedule, person_id, position_id, from, to)
      candidates = schedule[:by_position].fetch(position_id, [])
                                         .select { |_id, _pos, begins| begins >= from && begins <= to }
      return [nil, nil] if candidates.empty?

      mine = schedule[:signed_up][person_id]
      signed_up = candidates.find { |id, _pos, _begins| mine&.include?(id) }
      return [signed_up.first, SIGNED_UP] if signed_up

      [candidates.first.first, ONLY_MATCH]
    end

    # Fill in the callsigns and shift details the page needs, then sort. Done
    # once for the whole set rather than per row.
    def decorate(proposals)
      people = Person.where(id: proposals.map(&:person_id).uniq)
                     .pluck(:id, :callsign, :status)
                     .to_h { |id, callsign, status| [id, [callsign, status]] }
      shifts = shift_details(proposals)
      positions = entry_positions(proposals)

      proposals.map { |proposal|
        callsign, status = people[proposal.person_id]

        Change.new(timesheet_id: proposal.timesheet_id,
                   person_id: proposal.person_id,
                   callsign: callsign || "Deleted ##{proposal.person_id}",
                   status:,
                   position_title: positions[proposal.timesheet_id],
                   on_duty: proposal.on_duty,
                   old_slot_id: proposal.old_slot_id,
                   new_slot_id: proposal.new_slot_id,
                   old_shift: shifts[proposal.old_slot_id],
                   new_shift: shifts[proposal.new_slot_id],
                   reason: proposal.reason)
      }.sort_by { |change| [change.callsign.downcase, change.on_duty] }
    end

    def shift_details(proposals)
      ids = proposals.flat_map { |p| [p.old_slot_id, p.new_slot_id] }.compact.uniq
      return {} if ids.empty?

      # left_joins, not joins: the schema carries no foreign keys, so a shift
      # whose position row is gone would drop out of an inner join entirely --
      # and a change that lost its old end would read as an addition.
      Slot.where(id: ids).left_joins(:position)
          .pluck("slot.id", "position.title", "slot.begins", "slot.description")
          .to_h { |id, title, begins, description|
            [id, Shift.new(id:, position_title: title, begins:, description:)]
          }
    end

    def entry_positions(proposals)
      Timesheet.where(id: proposals.map(&:timesheet_id)).left_joins(:position)
               .pluck("timesheet.id", "position.title").to_h
    end

    # One entry, with both log rows. slot_id changes nothing about the hours,
    # the credits, or the roles behind them, so the column is written directly
    # rather than through a save that would rebuild all three for every entry.
    def write(change)
      entry = Timesheet.find(change.timesheet_id)

      ActiveRecord::Base.transaction do
        entry.update_column(:slot_id, change.new_slot_id)
        log(entry, change.old_slot_id, change.new_slot_id)
      end

      Result.new(callsign: change.callsign, message: summary(change), error: nil)
    rescue StandardError => e
      Result.new(callsign: change.callsign, message: nil, error: e.message)
    end

    def log(entry, old_id, new_id)
      data = { "slot_id" => [old_id, new_id] }

      TimesheetLog.record(TimesheetLog::UPDATE, entry.person_id, Current.person_id,
                          entry.id, data, entry.on_duty.year)
      ActionLog.record(Current.person_id, "timesheet-update", AUDIT_REASON,
                       data.merge("timesheet_id" => entry.id), entry.person_id)
    end

    def summary(change)
      name = change.new_shift&.description.presence

      case change.kind
      when :remove then "no longer linked to a shift"
      when :add then "linked to #{name || 'a shift'}"
      else "moved to #{name || 'another shift'}"
      end
    end
  end
end
