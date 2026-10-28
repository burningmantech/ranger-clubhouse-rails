# frozen_string_literal: true

require "test_helper"

# The form restates a year's verdict with update_all, which writes no audit row,
# so its Alpha-only scope is the one thing keeping another mentee position's
# walk for the same year out of the overwrite.
class PersonMentorStatusFormTest < ActiveSupport::TestCase
  YEAR = 2026

  test "a status change restates the Alpha walk and leaves another position's walk that year alone" do
    mentee = person(:alpha_ranger)
    mentor = person(:active_ranger)
    alpha = PersonMentor.create!(person: mentee, mentor:, mentor_year: YEAR, status: PersonMentor::STATUS_PENDING)
    cub = PersonMentor.create!(person: mentee, mentor:, mentor_year: YEAR, position_id: Position::CHEETAH_CUB,
                               status: PersonMentor::STATUS_PASS)

    form = PersonMentorStatusForm.new(person: mentee, mentor_year: YEAR, status: PersonMentor::STATUS_BONK)

    assert form.save(actor: mentor)
    assert_equal PersonMentor::STATUS_BONK, alpha.reload.status
    assert_equal PersonMentor::STATUS_PASS, cub.reload.status
  end

  # update_all skips PersonMentor's validations, so the form's own list is the
  # only thing keeping an ART-only verdict off an Alpha walk.
  test "an ART-only verdict is refused, and the Alpha walk keeps its status" do
    mentee = person(:alpha_ranger)
    mentor = person(:active_ranger)
    alpha = PersonMentor.create!(person: mentee, mentor:, mentor_year: YEAR, status: PersonMentor::STATUS_PENDING)

    form = PersonMentorStatusForm.new(person: mentee, mentor_year: YEAR, status: PersonMentor::STATUS_ABSTAIN)

    assert_not form.save(actor: mentor)
    assert_equal ["Status is not included in the list."], form.errors[:status]
    assert_equal PersonMentor::STATUS_PENDING, alpha.reload.status
  end
end
