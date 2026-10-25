# frozen_string_literal: true

# Everyone signed up in a year for a shift on a position with a Paycom employee
# code, whose own Paycom Employee ID cannot be paid against: never set, blank,
# or the "0" placeholder.
#
# The two are kept apart. No id means payroll cannot pay the shift until
# someone sets one. "0" is set on purpose -- it clears someone to take paid
# shifts without pay, and Payroll Export leaves them out -- so that half is a
# list to confirm rather than a list to fix.
#
# Today's ids and today's paycodes are read against the year's sign-ups: an
# earlier year answers "who from then still has no id", not "who had none at
# the time".
class PayrollMissingIdReport
  # One person and their paid sign-ups for the year, earliest first.
  Row = Data.define(:person, :sign_ups) do
    def first_slot = sign_ups.first.slot

    # Spelled once, so the table and the CSV cannot come to disagree.
    def positions_text
      sign_ups.map { |sign_up| sign_up.slot.position }.uniq
              .map { |position| "#{position.title} (#{position.paycode})" }
              .join(", ")
    end
  end

  # anyone_signed_up counts everyone, ids or not, so an empty report can say
  # whether nobody is missing an id or nobody has signed up yet.
  Result = Data.define(:missing, :unpaid, :anyone_signed_up) do
    def empty? = missing.empty? && unpaid.empty?
  end

  class << self
    # @return [Result] both halves in callsign order
    def execute(year)
      paid = PersonSlot.joins(:person, slot: :position)
                       .merge(Slot.for_year(year))
                       .merge(Position.with_paycode)

      # The database splits the halves, not Ruby. Its collation decides which
      # ids count as blank or as "0" -- trailing spaces, and characters Ruby
      # would not strip -- so asking it once per half holds both to one rule.
      missing = rows(paid.where(person: { employee_id: [nil, ""] }))
      unpaid = rows(paid.where(person: { employee_id: Person::UNPAID_EMPLOYEE_ID }))

      Result.new(missing:, unpaid:, anyone_signed_up: missing.any? || unpaid.any? || paid.exists?)
    end

    private

    # Sorted here rather than in SQL: an ORDER BY on slot.begins turns MariaDB
    # around to read every sign-up in the year before it filters on paycode.
    # slot_id breaks ties, so two shifts starting together keep one order.
    def rows(sign_ups)
      sign_ups.preload(:person, slot: :position)
              .group_by(&:person)
              .map { |person, list|
                Row.new(person:, sign_ups: list.sort_by { |sign_up| [sign_up.slot.begins, sign_up.slot_id] })
              }
              .sort_by { |row| row.person.callsign.downcase }
    end
  end
end
