# frozen_string_literal: true

# A mentee shift a mentee did not complete because no mentor was available
# (owner, 2026-11-13): the roster's "No mentors available" box. A row names
# the mentee, the mentee's timesheet entry, and the shift's slot -- none for a
# sign-in that matched no shift. The entry is the key: a row follows it when it
# is corrected onto another shift, so the slot is not unique with the mentee.
#
# No timestamps: the audit log says who ticked the box and when. The charset is
# named, as the other mentoring tables name theirs: the server default is not
# a promise.
class CreatePersonMentoringShift < ActiveRecord::Migration[8.1]
  def change
    create_table :person_mentoring_shift, id: { type: :bigint, unsigned: true },
                                          charset: "utf8mb4", collation: "utf8mb4_unicode_ci" do |t|
      t.bigint :person_id, null: false
      t.bigint :slot_id, unsigned: true
      t.bigint :timesheet_id, unsigned: true
      t.boolean :incomplete, null: false, default: false
      t.index %i[person_id slot_id]
      t.index :timesheet_id, unique: true
      t.index :slot_id
      t.check_constraint "slot_id IS NOT NULL OR timesheet_id IS NOT NULL", name: "person_mentoring_shift_has_a_key"
    end
  end
end
