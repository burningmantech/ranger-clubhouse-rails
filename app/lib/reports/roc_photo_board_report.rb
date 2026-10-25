# frozen_string_literal: true

# Who is on duty right now in the ROC positions, gathered for the
# wall display that runs in HQ.
#
# The same groups are always returned in the same order, even when a group
# has no one in it. A box that disappeared when it emptied would read as "that
# role is not being run tonight", when the truth is only "no one is signed in
# yet" -- and on a board people read from across the room, the difference
# matters.
class RocPhotoBoardReport
  # Each heading gathers several positions. Somebody appears under the heading
  # for the one position they are signed into.
  GROUPS = [
    ["Khakis", [Position::RSC_SHIFT_LEAD_PRE_EVENT,
                Position::RSC_SHIFT_LEAD,
                Position::RSCI]],
    ["Troubleshooters", [Position::TROUBLESHOOTER,
                         Position::TROUBLESHOOTER_LEAL,
                         Position::TROUBLESHOOTER_LEAL_PRE_EVENT,
                         Position::TROUBLESHOOTER_PRE_EVENT,
                         Position::TROUBLESHOOTER_MENTOR,
                         Position::TROUBLESHOOTER_TRAINER]],
    ["Operators", [Position::OPERATOR,
                   Position::OPERATOR_SMOOTH]],
    ["Green Dot Leads", [Position::GREEN_DOT_LEAD]],
    ["OODs", [Position::OOD,
              Position::DEPUTY_OOD]]
  ].freeze

  # Whoever is signed into this position is there to answer questions from the
  # rest of the room, so they are listed on their own rather than in a group.
  HOST_POSITION = Position::ROC_STAR

  # A card on the board. The host cards leave the position off when they draw:
  # what matters about a host is that they are the person to ask.
  Entry = Data.define(:person, :position_title)

  Group = Data.define(:title, :entries) do
    def size = entries.size
  end

  Result = Data.define(:loaded_at, :groups, :hosts)

  class << self
    def execute
      on_duty = open_entries.group_by(&:position_id)

      Result.new(loaded_at: Current.time,
                 groups: GROUPS.map { |title, position_ids|
                   Group.new(title:, entries: entries_for(on_duty, position_ids))
                 },
                 hosts: entries_for(on_duty, [HOST_POSITION]))
    end

    private

    def open_entries
      # Which open entries still describe somebody really out there is a rule
      # the on-duty pages all share, so it is asked for rather than spelled
      # again here. The board looks back as far as the on-duty page does.
      Timesheet.open_within(OnDutyReport::MAX_SHIFT_LOOKBACK)
               .where(position_id: board_position_ids)
               .includes(:position, person: :profile_photo_attachment)
    end

    def board_position_ids
      GROUPS.flat_map(&:last) + [HOST_POSITION]
    end

    # Callsign order, ignoring case, across every position in the group -- the
    # board is read as one list of names, not as one list per position.
    #
    # One card per person, however many open entries they have: somebody signed
    # in twice within the same group is one Ranger standing in the room, and two
    # photos of them says the group is bigger than it is.
    def entries_for(on_duty, position_ids)
      position_ids.flat_map { |position_id| on_duty[position_id] || [] }
                  .filter_map { |timesheet| build_entry(timesheet) }
                  .uniq { |entry| entry.person.id }
                  .sort_by { |entry| entry.person.callsign.to_s.downcase }
    end

    def build_entry(timesheet)
      person = timesheet.person
      # No callsign, no card: this schema is shared with another application
      # and carries no foreign keys, so a deleted person leaves the reference
      # behind. A nameless photo tells the room nothing.
      return nil if person.nil?

      Entry.new(person:,
                position_title: timesheet.position&.title || "Position ##{timesheet.position_id}")
    end
  end
end
