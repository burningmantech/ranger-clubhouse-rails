# frozen_string_literal: true

# Positions grouped by team for a picker: [[group title, positions], ...].
#
# Which positions to offer -- active only, a team manager's teams -- is the
# caller's choice, so they arrive already chosen and ordered. Grouped by the
# team itself rather than its title, so two teams never merge because they
# share a name.
module PositionGroups
  module_function

  # The positions no team owns come first, together with any whose team no
  # longer exists, then each team's by title. Positions keep the order given.
  # The teams load in one query, skipping any the caller already loaded.
  def by_team(positions)
    ActiveRecord::Associations::Preloader.new(records: positions.to_a, associations: :team).call
    groups = positions.group_by(&:team)
    general = groups.delete(nil)
    teams = groups.sort_by { |team, _| team.title.downcase }.map { |team, list| [team.title, list] }
    general ? [["General Positions", general], *teams] : teams
  end
end
