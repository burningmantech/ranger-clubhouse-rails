# Additive index on the Laravel-shared trainer_status table (same precedent
# as the 2026-07-25 report indexes): the training landing page looks up lead
# flags by session slot id on every render, and the table's only index leads
# with person_id.
class AddSlotIdIndexToTrainerStatus < ActiveRecord::Migration[8.1]
  def change
    add_index :trainer_status, :slot_id
  end
end
