# frozen_string_literal: true

require "test_helper"

class AlertWhenSignUpsEmptyJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  YEAR = 2024

  setup do
    ActionMailer::Base.deliveries.clear
    @person = person(:active_ranger)
    @position = positions(:ood_position)
    @position.update!(contact_email: "ood@example.com")
    @slot = create_empty_slot
  end

  test "perform names the person who dropped so the team knows who to ask" do
    assert_emails 1 do
      AlertWhenSignUpsEmptyJob.perform_now(@position, @slot, @person.id)
    end

    body = ActionMailer::Base.deliveries.last.body.to_s

    assert_includes body, @person.callsign
  end

  # The wait before this job runs is there so a drop-and-rejoin stays quiet.
  test "perform sends nothing when someone signed up again while it waited" do
    PersonSlot.create!(person: @person, slot: @slot)
    @slot.update!(signed_up: 1)

    assert_emails 0 do
      AlertWhenSignUpsEmptyJob.perform_now(@position, @slot, @person.id)
    end
  end

  test "perform sends nothing when the position has nowhere to write to" do
    @position.update!(contact_email: "")

    assert_emails 0 do
      AlertWhenSignUpsEmptyJob.perform_now(@position, @slot, @person.id)
    end
  end

  # A trainer shift with no trainees left to teach is not worth an alert.
  test "perform sends nothing when the trainee slot emptied out too" do
    trainee_slot = create_empty_slot

    assert_emails 0 do
      AlertWhenSignUpsEmptyJob.perform_now(@position, @slot, @person.id, trainee_slot)
    end
  end

  test "perform still sends when the person who dropped is gone" do
    assert_emails 1 do
      AlertWhenSignUpsEmptyJob.perform_now(@position, @slot, nil)
    end

    assert_includes ActionMailer::Base.deliveries.last.body.to_s, "Unknown"
  end

  private

  def create_empty_slot
    Slot.create!(position: @position,
                 begins: Time.zone.local(YEAR, 6, 1, 9, 0, 0),
                 ends: Time.zone.local(YEAR, 6, 1, 17, 0, 0),
                 description: "Playa",
                 max: 10,
                 active: true)
  end
end
