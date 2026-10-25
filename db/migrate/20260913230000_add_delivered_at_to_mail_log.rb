class AddDeliveredAtToMailLog < ActiveRecord::Migration[8.1]
  def change
    add_column :mail_log, :delivered_at, :timestamp,
               comment: "when SES reported the message reached the recipient's mail server"
  end
end
