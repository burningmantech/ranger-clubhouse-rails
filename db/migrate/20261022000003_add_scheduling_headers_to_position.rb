# frozen_string_literal: true

# Two rich-text notes a position shows at the top of its sign-up page, one to
# Rangers and Echelon, one to applicants. Nullable: no header means nothing is
# shown.
class AddSchedulingHeadersToPosition < ActiveRecord::Migration[8.1]
  def change
    add_column :position, :ranger_scheduling_header, :text
    add_column :position, :applicant_scheduling_header, :text
  end
end
