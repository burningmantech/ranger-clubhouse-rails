# frozen_string_literal: true

class PersonStatus < ApplicationRecord
  self.table_name = "person_status"

  belongs_to :person
  belongs_to :person_source, class_name: "Person", optional: true

  class << self
    # Record the change in a person's status.
    def record(person_id, old_status, new_status, reason, person_source_id)
      create!(
        person_id:,
        person_source_id:,
        old_status:,
        new_status:,
        reason:
      )
    end

    # Retrieve the status history for a person
    def retrieve_all_for_id(person_id)
      where(person_id:)
        .includes(:person_source)
        .order(:created_at)
    end

    # Find the PersonStatus record that exists on or before the time given.
    # Used to determine a person's status at a given point in time.
    def find_for_time(person_id, time)
      where(person_id:)
        .where("created_at <= ?", time)
        .order(created_at: :desc)
        .first
    end

    # Find the PersonStatus records that exist on or before the time given for multiple people.
    # Used to determine persons' statuses at a given point in time.
    #
    # Uses a correlated subquery to find the latest record per person before the given time.
    # MariaDB does not support DISTINCT ON, so this pattern is necessary.
    def find_status_for_ids_time(person_ids, time)
      where(person_id: person_ids)
        .where("created_at <= ?", time)
        .where(latest_before_time_sql, time)
        .index_by(&:person_id)
    end

    private

    # Correlated subquery to find the latest person_status record before a given time.
    # Returns SQL string with one placeholder for the time parameter.
    def latest_before_time_sql
      "created_at = (SELECT ps.created_at FROM person_status ps " \
        "WHERE ps.person_id = person_status.person_id " \
        "AND ps.created_at <= ? ORDER BY ps.created_at DESC LIMIT 1)"
    end
  end
end
