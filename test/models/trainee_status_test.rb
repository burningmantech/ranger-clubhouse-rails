# frozen_string_literal: true

require "test_helper"

# The verdict and the two pass checks the training gates ask.
class TraineeStatusTest < ActiveSupport::TestCase
  include TrainingSlotTestHelper

  YEAR = 2026

  setup do
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    @slot = create_slot(training, begins: Time.zone.local(YEAR, 5, 2, 9, 0, 0))
    @person = person(:active_ranger)
  end

  test "a new row is pending, and only a known status is valid" do
    row = TraineeStatus.new(person: @person, slot: @slot)
    assert_equal TraineeStatus::STATUS_PENDING, row.status
    assert_not row.passed?

    row.status = "maybe"
    assert_not row.valid?

    TraineeStatus::STATUSES.each do |status|
      row.status = status
      assert row.valid?, "#{status} should be valid"
    end
  end

  test "only a pass counts as passing the session and the year" do
    row = TraineeStatus.create!(person: @person, slot: @slot)

    TraineeStatus::STATUSES.each do |status|
      row.update!(status:)
      passed = status == TraineeStatus::STATUS_PASSED

      assert_equal passed, TraineeStatus.did_person_pass_for_year?(@person.id, Position::TRAINING, YEAR), status
      assert_equal passed, TraineeStatus.did_person_pass_session?(@person.id, @slot.id), status
    end
  end
end
