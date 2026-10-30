# frozen_string_literal: true

# bmid_export.person_ids is a JSON list like the two shift coverage lists, and
# now carries the same json_valid check they do.
class CheckBmidExportPersonIdsJson < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :bmid_export, "json_valid(`person_ids`)", name: "person_ids"
  end
end
