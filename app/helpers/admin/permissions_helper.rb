# frozen_string_literal: true

module Admin::PermissionsHelper
  # The label on the control that opens a permission's grant list: "3 teams",
  # "1 team · 2 positions". Only the halves that have something to report.
  def permission_grant_summary(team_count, position_count)
    parts = []
    parts << pluralize(team_count, "team") if team_count.positive?
    parts << pluralize(position_count, "position") if position_count.positive?
    parts.join(" · ")
  end

  # The delete confirmation names every grant that goes with the permission.
  # "Cannot be undone" alone does not say that people, teams, and positions all
  # lose it at the same time.
  def permission_delete_warning(permission, held_by_people)
    losing = [
      (pluralize(permission.teams.size, "team") if permission.teams.size.positive?),
      (pluralize(permission.positions.size, "position") if permission.positions.size.positive?),
      (pluralize(held_by_people, "person") if held_by_people.positive?)
    ].compact

    warning = "Delete \"#{permission.title}\"? "
    warning += if losing.any?
                 "It will be removed from #{losing.to_sentence} at the same time. "
               else
                 "Nothing holds it right now. "
               end
    warning + "This cannot be undone."
  end
end
