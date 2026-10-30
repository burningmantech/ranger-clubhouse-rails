# frozen_string_literal: true

# The mentee positions an Alpha test records person_mentor rows under. The
# column is keyed to position and positions.yml carries neither, so a test
# creates them; created rather than fixtured because the Alpha tests that
# build their own Alpha position (its slots, its mentors) would collide with
# a fixture of the same id.
module AlphaPositionTestHelper
  # Alpha, which a person_mentor row written without a position defaults to.
  def setup_alpha_position
    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha", type: Position::TYPE_FRONTLINE, active: true)
  end

  # Another mentee position, whose walks every Alpha reader must leave alone.
  def setup_cheetah_cub_position
    @cheetah_cub_position = Position.create!(id: Position::CHEETAH_CUB, title: "Cheetah Cub",
                                             type: Position::TYPE_MENTORING, active: true)
  end
end
