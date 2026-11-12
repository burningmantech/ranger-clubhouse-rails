# frozen_string_literal: true

# Where a slot may take place. Every existing slot starts as event-season; the
# backfill below writes only the exceptions, in an order where a later rule wins:
# a training slot no position credit covers is off-season, a training slot whose
# description says zoom, online or virtual is virtual, and the DPW/NVO positions run
# across the playa and the area around it. update_all writes no audit rows and
# purges no caches, and none read the venue.
class AddVenueToSlot < ActiveRecord::Migration[8.1]
  class MigrationSlot < ActiveRecord::Base
    self.table_name = "slot"
  end

  class MigrationPosition < ActiveRecord::Base
    self.table_name = "position"
    self.inheritance_column = nil
  end

  class MigrationPositionCredit < ActiveRecord::Base
    self.table_name = "position_credit"
  end

  # DPW/NVO Ranger, NVO Ranger, DPW/NVO Ranger Long
  MULTISITE_POSITION_IDS = [105, 168, 250].freeze

  def up
    add_column :slot, :venue, "enum('event-season','non-event','multisite','virtual')",
               null: false, default: "event-season"
    MigrationSlot.reset_column_information

    # The ids, not a subquery on position.type: an id list uses the slot.position_id
    # index, so each UPDATE reads and locks only the training slots.
    training = MigrationSlot.where(position_id: MigrationPosition.where(type: "Training").pluck(:id))
    slot = MigrationSlot.arel_table
    credit = MigrationPositionCredit.arel_table
    covering_credit = MigrationPositionCredit.where(credit[:position_id].eq(slot[:position_id]))
                                             .where(credit[:start_time].lt(slot[:ends]))
                                             .where(credit[:end_time].gt(slot[:begins]))

    say_with_time "Training slots no position credit covers: non-event" do
      training.where.not(covering_credit.arel.exists).update_all(venue: "non-event")
    end
    say_with_time "Training slots described as zoom, online or virtual: virtual" do
      training.where(slot[:description].matches_regexp("\\b(zoom|online|virtual)\\b")).update_all(venue: "virtual")
    end
    say_with_time "DPW/NVO slots: multisite" do
      MigrationSlot.where(position_id: MULTISITE_POSITION_IDS).update_all(venue: "multisite")
    end
  end

  def down
    remove_column :slot, :venue
  end
end
