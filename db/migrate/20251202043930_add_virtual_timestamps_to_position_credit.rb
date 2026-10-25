class AddVirtualTimestampsToPositionCredit < ActiveRecord::Migration[8.0]
  def change
    add_column :position_credit, :start_timestamp, :virtual,
               type: :bigint,
               as: "UNIX_TIMESTAMP(start_time)",
               stored: true
    add_column :position_credit, :end_timestamp, :virtual,
               type: :bigint,
               as: "UNIX_TIMESTAMP(end_time)",
               stored: true
  end
end
