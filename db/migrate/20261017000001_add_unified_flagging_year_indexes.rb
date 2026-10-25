# Year-leading indexes for /people/unified-flagging's roster
# (Intake.retrieve_recorded_for_year), which asks each of these tables who has
# a row for the viewed year. Every index they had led with person_id, and
# MariaDB has no skip scan, so each question read the whole table on every
# page load and export.
#
# Additive, on tables shared with the legacy Laravel Clubhouse (the same
# precedent as the 2026-07-25 report indexes), so if_not_exists in case that
# side adds one first.
class AddUnifiedFlaggingYearIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :person_intake_note, [:year, :is_log], if_not_exists: true
    add_index :person_intake, :year, if_not_exists: true
    add_index :person_mentor, [:mentor_year, :status], if_not_exists: true
    add_index :trainee_note, :slot_id, if_not_exists: true
  end
end
