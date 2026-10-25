# frozen_string_literal: true

# Shared setup for the person timesheet admin controller tests.
module TimesheetAdminTestHelper
  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end

  def confirm_timesheet_for(person, year)
    event = PersonEvent.first_or_new_for_person_year(person.id, year)
    event.timesheet_confirmed = true
    event.timesheet_confirmed_at = Current.time
    event.save!(validate: false)
  end
end
