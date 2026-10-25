# frozen_string_literal: true

# Person now saves phone numbers in E.164 ("+17755550199"); this brings the
# numbers already stored into line, read the way Person reads them. A value
# with no digits at all ("none", "N/A", "same") is emptied. Anything else that
# is not a number is left as typed, and whose it is printed for someone to fix
# by hand.
#
# Nothing goes to the action log and updated_at is left alone: these are the
# same numbers, written differently. The pre-deploy dump keeps what was typed.
class NormalizePersonPhones < ActiveRecord::Migration[8.1]
  # The table as it is today (the 20260408120000 precedent). The reader is
  # PhoneFormatter on purpose, so a stored number matches what a save stores.
  class MigrationPerson < ActiveRecord::Base
    self.table_name = "person"
  end

  PHONES = %w[home_phone alt_phone].freeze

  def up
    counts = Hash.new(0)
    left_as_typed = []
    changed_meanwhile = []

    say_with_time "Storing person.home_phone and person.alt_phone in E.164" do
      MigrationPerson.select(:id, :country, *PHONES).find_each do |person|
        outcomes = {}
        changes = {}
        PHONES.each do |column|
          typed = person[column].to_s
          next if typed.empty?

          e164 = PhoneFormatter.e164(typed, person.country)
          outcomes[column] = if e164 == typed then :already_e164
                             elsif e164 then :converted
                             elsif typed.match?(/\d/) then :left_as_typed
                             else :emptied
                             end
          changes[column] = e164 || "" if %i[converted emptied].include?(outcomes[column])
        end

        # Only where the row still holds what was read: the old code may be
        # serving while this runs, and a number saved meanwhile must not be
        # replaced by the conversion of the one before it. That person's next
        # save reads it instead.
        if changes.any? && MigrationPerson.where(id: person.id, **changes.keys.index_with { |column| person[column] })
                                          .update_all(changes).zero?
          changed_meanwhile << person.id
          next
        end

        outcomes.each_value { |outcome| counts[outcome] += 1 }
        left_as_typed << person.id if outcomes.value?(:left_as_typed)
      end
    end

    say "Converted #{counts[:converted]}, already E.164 #{counts[:already_e164]}, " \
        "emptied #{counts[:emptied]}, left as typed #{counts[:left_as_typed]}"
    say "Not a phone number, left as typed -- person ids: #{left_as_typed.join(", ")}" if left_as_typed.any?
    say "Changed while this ran, left for their next save -- person ids: #{changed_meanwhile.join(", ")}" if changed_meanwhile.any?
  end

  def down
    # Nothing to undo: E.164 is the same number, and the emptied values held none.
  end
end
