# frozen_string_literal: true

class PositionRole < ApplicationRecord
  self.table_name = "position_role"
  self.primary_key = [:position_id, :role_id]

  belongs_to :position
  belongs_to :role

  class << self
    # Find all rows for the given position
    def find_all_for_position(position_id)
      where(position_id:)
    end

    # Find all the positions with granted roles for a person
    def find_roles_for_person(person)
      rows = PersonPosition
             .select(
               "position.id",
               "position.title",
               "position_role.role_id",
               "position.require_training_for_roles",
               "position.training_position_id"
             )
             .where(person_id: person.id)
             .joins(position: :position_roles)

      year = Current.year
      rows.map do |row|
        position = {
          id: row.id,
          title: row.title,
          role_id: row.role_id
        }

        if row.require_training_for_roles
          position[:require_training_for_roles] = true
          position[:is_trained] = Training.did_person_pass_for_year?(
            person, row.training_position_id, year
          )
        end

        position
      end
    end

    # Add a role to a position
    def add(position_id, role_id, reason = nil)
      return if exists?(position_id:, role_id:)

      create!(position_id:, role_id:)
      Rails.cache.clear
      ActionLog.record(Current.person, "position-role-add", reason, { position_id:, role_id: })
    end

    # Remove a role from a position
    def remove(position_id, role_id, reason = nil)
      where(position_id:, role_id:).delete_all
      Rails.cache.clear
      ActionLog.record(Current.person, "position-role-remove", reason, { position_id:, role_id: })
    end
  end
end
