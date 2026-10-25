# frozen_string_literal: true

# Adds the Pog Management permission (Role::POG_MANAGEMENT), which opens the
# Pogs pages. Rows 131 and 132 were already in the database the Laravel side
# built; 133 never was, and Admin › Permissions can only create
# training-position permissions, so the row has to come from here.
#
# insert_all skips a row whose id already exists, so this is safe on a database
# where someone added it by hand. Plain table stand-ins rather than Role and its
# join models, so the migration keeps working whatever those models become.
class AddPogManagementRole < ActiveRecord::Migration[8.1]
  ROLE_ID = 133

  def up
    table("role").insert_all([{ id: ROLE_ID, title: "Pog Management", new_user_eligible: false }])
  end

  # Takes the permission away from everyone holding it and removes it, then
  # empties the role cache, as Admin › Permissions does when it deletes one:
  # RoleManager keeps each person's roles cached, so a holder would otherwise
  # keep the permission until their entry aged out.
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
