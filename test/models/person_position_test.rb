# frozen_string_literal: true

require "test_helper"

class PersonPositionTest < ActiveSupport::TestCase
  # An ART is listed only when some position requires it; the base Training
  # position is always listed. The correlated EXISTS must reference the OUTER
  # position row -- un-aliased it compared each inner row to itself and never
  # matched, so every ART vanished from /person/:id/training.
  test "find_training_positions lists the base training plus ARTs some position requires" do
    ranger = person(:active_ranger)
    training = Position.create!(id: Position::TRAINING, title: "Training",
                                type: Position::TYPE_TRAINING, active: true)
    sandman_training = Position.create!(id: Position::SANDMAN_TRAINING, title: "Sandman Training",
                                        type: Position::TYPE_TRAINING, active: true)
    radio_practice = Position.create!(id: Position::TRAINING_RADIO_PRACTICE, title: "Training - Radio Practice",
                                      type: Position::TYPE_TRAINING, active: true)
    Position.create!(id: Position::SANDMAN, title: "Sandman", type: Position::TYPE_FRONTLINE, active: true,
                     training_position_id: sandman_training.id)
    [training, sandman_training, radio_practice].each { |position| PersonPosition.create!(person: ranger, position:) }

    # Radio Practice is type Training but nothing requires it, so it is not an ART.
    assert_equal [sandman_training, training], PersonPosition.find_training_positions(ranger.id)

    # exclude_potentials keeps only ARTs whose requiring position is already held.
    assert_equal [training], PersonPosition.find_training_positions(ranger.id, true)
    PersonPosition.create!(person: ranger, position_id: Position::SANDMAN)
    assert_equal [sandman_training, training], PersonPosition.find_training_positions(ranger.id, true)
  end
end
