# frozen_string_literal: true

require "test_helper"

# Convert Alphas mints or bonks from these verdicts, so they must come from the
# Alpha walk alone: another mentee position's pass must not mint an Alpha, and
# its bonk, which outranks a pass, must not bonk one.
class AlphaConversionTest < ActiveSupport::TestCase
  include AlphaPositionTestHelper

  YEAR = 2026

  setup do
    setup_alpha_position
    setup_cheetah_cub_position
    @alpha = person(:alpha_ranger)
    @mentor = person(:active_ranger)
  end

  test "verdicts read only the Alpha walk, never another position's walk that year" do
    alpha = walk(PersonMentor::STATUS_PENDING)
    cub = walk(PersonMentor::STATUS_PASS, position_id: Position::CHEETAH_CUB)

    assert_empty AlphaConversion.verdicts_for_year(YEAR, among: [@alpha.id])

    alpha.update!(status: PersonMentor::STATUS_PASS)
    cub.update!(status: PersonMentor::STATUS_BONK)

    assert_equal({ @alpha.id => PersonMentor::STATUS_PASS }, AlphaConversion.verdicts_for_year(YEAR, among: [@alpha.id]))
  end

  private

  def walk(status, position_id: Position::ALPHA)
    PersonMentor.create!(person: @alpha, mentor: @mentor, mentor_year: YEAR, position_id:, status:)
  end
end
