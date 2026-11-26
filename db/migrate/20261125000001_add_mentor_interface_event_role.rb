# frozen_string_literal: true

# Adds the Mentor Interface Event permission (Role::MENTOR_INTERFACE_EVENT),
# which opens the Mentoring pages while the EventManagementOnPlayaEnabled
# setting is on. Admin › Permissions can only create training-position
# permissions, so the row has to come from here.
#
# insert_all skips a row whose id already exists. Plain table stand-ins rather
# than Role and its join models, so the migration keeps working whatever those
# models become.
class AddMentorInterfaceEventRole < ActiveRecord::Migration[8.1]
  ROLE_ID = 134

  def up
    table("role").insert_all([{ id: ROLE_ID, title: "Mentor Interface Event", new_user_eligible: false }])
  end

  # Takes the permission away from everyone holding it and removes it, then
  # empties the role cache so no holder keeps it until their entry ages out.
  def down
    %w[person_role team_role position_role].each { |name| table(name).where(role_id: ROLE_ID).delete_all }
    table("role").where(id: ROLE_ID).delete_all
    RoleManager.purge_all
  end

  private

  def table(name)
    Class.new(ActiveRecord::Base) { self.table_name = name }
  end
end
