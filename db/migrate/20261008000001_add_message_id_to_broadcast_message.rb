# frozen_string_literal: true

# The id Amazon SES gave a broadcast email when it took it. The mail log keeps
# the same id, and SES's delivery and bounce reports name it, so a report can
# be traced back to the person and the broadcast it is about.
class AddMessageIdToBroadcastMessage < ActiveRecord::Migration[8.1]
  def change
    add_column :broadcast_message, :message_id, :string,
               comment: "the id SES gave this email; mail_log.message_id holds the same"
  end
end
