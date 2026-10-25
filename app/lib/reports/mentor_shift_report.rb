# frozen_string_literal: true

# The Mentor Shift Report: who is signed up across every mentor-family
# position around one Alpha shift, or who is on duty right now. Alphas carry
# their prior bonk years; everyone else carries their rangering history.
# (Upstream Laravel app/Lib/Reports/MentorShiftReport.php.)
#
# Both modes return the same Result shape: the four GROUPS in a fixed order,
# each holding positions, each position holding SlotSignUps of Entry rows. In
# scheduled mode every group position appears, slotless ones included, so
# coverage gaps stay visible; on-duty mode lists only positions with someone
# on duty, in a single slotless SlotSignUps. On-duty mode always reads the
# current year, as upstream does -- the page banner says so.
class MentorShiftReport
  # The window around the Alpha shift's start that other mentor-family shifts
  # are gathered from.
  HOURS_PRIOR = 1
  HOURS_AFTER = 3

  MENTOR_TYPES = [Position::MENTOR, Position::MENTOR_MITTEN].freeze
  CHEETAH_PRIDE = [Position::CHEETAH, Position::CHEETAH_CUB].freeze
  MENTOR_OPERATIONS = [
    Position::MENTOR_LEAD,
    Position::MENTOR_SHORT,
    Position::MENTOR_ALPHA_HOST,
    Position::MENTOR_KHAKI,
    Position::MENTOR_RADIO_TRAINER,
    Position::MENTOR_WHEEL_OF_MANY_WAYS,
    Position::MENTOR_APPRENTICE
  ].freeze

  ALL_POSITIONS = [Position::ALPHA, *MENTOR_TYPES, *CHEETAH_PRIDE, *MENTOR_OPERATIONS].freeze

  GROUPS = [
    { key: :alphas, title: "Alphas", position_ids: [Position::ALPHA] },
    { key: :mentors, title: "Mentors & Mittens", position_ids: MENTOR_TYPES },
    { key: :cheetahs, title: "Cheetahs & Cheetah Cubs", position_ids: CHEETAH_PRIDE },
    { key: :operations, title: "Mentor Operations / Support", position_ids: MENTOR_OPERATIONS }
  ].freeze

  Entry = Data.define(:person, :began, :duration, :bonk_years)
  SlotSignUps = Data.define(:slot, :entries)
  PositionGroup = Data.define(:title, :alpha?, :slots)
  Group = Data.define(:key, :title, :positions)
  Result = Data.define(:on_duty?, :slot, :now, :groups, :group_counts, :unfilled_count)

  class << self
    def for_slot(alpha_slot)
      window = (alpha_slot.begins - HOURS_PRIOR.hours)..(alpha_slot.begins + HOURS_AFTER.hours)
      slots_by_position = Slot.for_year(alpha_slot.begins_year)
                              .active
                              .where(position_id: ALL_POSITIONS, begins: window)
                              .includes(:sign_ups)
                              .ordered_by_begins
                              .group_by(&:position_id)

      bonk_years = bonk_years_for(slots_by_position[Position::ALPHA]&.flat_map { |slot| slot.sign_ups.map(&:id) })
      titles = position_titles

      groups = GROUPS.map do |group|
        positions = group[:position_ids].map do |position_id|
          slots = (slots_by_position[position_id] || []).map do |slot|
            entries = slot.sign_ups.sort_by { |person| person.callsign.downcase }.map do |person|
              Entry.new(person:, began: slot.begins, duration: slot.duration,
                        bonk_years: bonk_years[person.id] || [])
            end
            SlotSignUps.new(slot:, entries:)
          end
          PositionGroup.new(title: titles[position_id], alpha?: position_id == Position::ALPHA, slots:)
        end
        Group.new(key: group[:key], title: group[:title], positions:)
      end

      Result.new(
        on_duty?: false,
        slot: alpha_slot,
        now: nil,
        groups:,
        group_counts: count_people(groups),
        # Every fetched slot lands in exactly one group, so counting at the
        # source equals counting the built tree.
        unfilled_count: slots_by_position.values.sum { |slots| slots.count { |slot| slot.sign_ups.empty? } }
      )
    end

    def on_duty
      timesheets_by_position = Timesheet.where(position_id: ALL_POSITIONS)
                                        .for_year(Current.year)
                                        .on_duty_now
                                        .includes(:person)
                                        .group_by(&:position_id)

      bonk_years = bonk_years_for(timesheets_by_position[Position::ALPHA]&.map(&:person_id))
      titles = position_titles

      groups = GROUPS.map do |group|
        positions = group[:position_ids].filter_map do |position_id|
          timesheets = timesheets_by_position[position_id]
          next unless timesheets

          entries = timesheets.sort_by { |timesheet| timesheet.person.callsign.downcase }.map do |timesheet|
            Entry.new(person: timesheet.person, began: timesheet.on_duty, duration: timesheet.duration,
                      bonk_years: bonk_years[timesheet.person_id] || [])
          end
          PositionGroup.new(title: titles[position_id], alpha?: position_id == Position::ALPHA,
                            slots: [SlotSignUps.new(slot: nil, entries:)])
        end
        Group.new(key: group[:key], title: group[:title], positions:)
      end

      Result.new(on_duty?: true, slot: nil, now: Current.time, groups:,
                 group_counts: count_people(groups), unfilled_count: nil)
    end

    private

    def bonk_years_for(person_ids)
      return {} if person_ids.blank?

      PersonMentor.bonk_years_by_person(person_ids, position_id: Position::ALPHA)
    end

    # One query covers both real slots and the placeholder rows scheduled mode
    # renders for positions with no shifts in the window.
    def position_titles
      titles = Position.where(id: ALL_POSITIONS).pluck(:id, :title).to_h
      titles.default_proc = ->(_hash, id) { "Position ##{id}" }
      titles
    end

    def count_people(groups)
      groups.to_h do |group|
        [group.key, group.positions.sum { |position| position.slots.sum { |slot| slot.entries.size } }]
      end
    end
  end
end
