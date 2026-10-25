# frozen_string_literal: true

require "test_helper"

class PersonTeamTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper # ensure_role

  # The roles a membership grants are the team's, so ending the membership
  # leaves them: a has_many through a column team_role never had made this
  # raise CompositePrimaryKeyMismatchError instead.
  test "destroying a membership leaves the team's roles alone" do
    team = teams(:council_cadre)
    membership = PersonTeam.create!(person: person(:ranger_with_custom_gender), team:)
    ensure_role(Role::MENTOR, "Mentor")
    TeamRole.create!(team:, role_id: Role::MENTOR)

    assert_difference -> { PersonTeam.count }, -1 do
      assert_no_difference -> { TeamRole.where(team:).count } do
        membership.destroy!
      end
    end
  end
end
