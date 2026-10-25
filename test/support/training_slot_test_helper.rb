# frozen_string_literal: true

# Shared slot factory for the training interface tests.
module TrainingSlotTestHelper
  TIMEZONE = "America/Los_Angeles"

  def create_slot(position, begins:, ends: begins + 8.hours, description: "Playa", **options)
    Slot.create!(position_id: position.id, begins:, ends:, description:,
                 active: true, max: 20, timezone: TIMEZONE, **options)
  end

  def sign_up(person, slot)
    PersonSlot.create!(person_id: person.id, slot_id: slot.id)
  end
end
