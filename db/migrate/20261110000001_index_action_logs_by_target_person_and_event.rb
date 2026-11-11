# frozen_string_literal: true

# Person › Schedule Audit Log reads one person's sign-up changes in a year:
# target_person_id, two events and a created_at range. Through the
# (target_person_id, created_at) index that means reading every row aimed at
# the person that year, mostly page visits, since the request logger names the
# person of every /person/:id page: 1,887 rows to return 31 for the busiest
# person of 2025. Led by the event as well, the index reads only the matches.
class IndexActionLogsByTargetPersonAndEvent < ActiveRecord::Migration[8.1]
  def change
    add_index :action_logs, [:target_person_id, :event, :created_at],
              name: "action_logs_target_person_id_event_created_at_index"
  end
end
