# frozen_string_literal: true

class PersonRole < ApplicationRecord
  self.table_name = "person_role"
  self.primary_key = [:person_id, :role_id]

  belongs_to :person
  belongs_to :role

  class << self
    # Find all held roles for the given person
    def find_roles_for_person(person_id)
      Role.select(:id, :title)
          .joins(:person_roles)
          .where(person_role: { person_id: })
          .order(:title)
    end

    # Find all the role ids for the given person
    def find_role_ids_for_person(person_id)
      where(person_id: person_id).pluck(:role_id)
    end

    # Remove all roles from a person in response to status change, add back
    # the default roles if requested.
    def reset_roles(person_id, reason, action)
      remove_ids = find_role_ids_for_person(person_id)

      if action == Person::ADD_NEW_USER
        add_ids = []
        eligible_ids = Role.where(new_user_eligible: true).pluck(:id)

        eligible_ids.each do |role_id|
          if remove_ids.include?(role_id)
            remove_ids.delete(role_id)
          else
            add_ids << role_id
          end
        end

        add_ids_to_person(person_id, add_ids, reason)
      end

      remove_ids_from_person(person_id, remove_ids, reason)
    end

    # Remove roles from a person. Log the action.
    def remove_ids_from_person(person_id, ids, reason = nil)
      return if ids.blank?

      where(person_id: person_id, role_id: ids).delete_all
      ActionLog.record(Current.person, "person-role-remove", reason, { role_ids: ids }, person_id)
      clear_cache(person_id)
    end

    # Remove all roles from a person.
    def remove_all_from_person(person_id, reason = nil)
      ids = where(person_id: person_id).pluck(:role_id)
      remove_ids_from_person(person_id, ids, reason)
    end

    # Add roles to a person. Log the action.
    def add_ids_to_person(person_id, ids, reason)
      added_ids = []

      ids.each do |id|
        next if exists?(person_id: person_id, role_id: id)

        create!(person_id: person_id, role_id: id)
        added_ids << id
      end

      return if added_ids.empty?

      ActionLog.record(
        Current.person, "person-role-add", reason, { role_ids: added_ids }, person_id
      )
      clear_cache(person_id)
    end

    # Log changes to person_role
    def log(person_id, id, action, reason = nil)
      ActionLog.record(Current.person, "person-role-#{action}", reason, { role_id: id }, person_id)
    end

    # Clear the roles cache for the given person. RoleManager owns the key --
    # do not spell it out here, the two drifted apart once already.
    def clear_cache(person_id)
      RoleManager.purge_person(person_id)
    end
  end
end
