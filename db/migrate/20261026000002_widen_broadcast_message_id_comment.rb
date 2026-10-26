# frozen_string_literal: true

# A text's row keeps the SID Twilio gave it in message_id, beside the id SES
# gives an email, now that single texts go through the Messages API rather
# than Notify, which answers with no id per phone.
class WidenBroadcastMessageIdComment < ActiveRecord::Migration[8.1]
  def change
    change_column_comment :broadcast_message, :message_id,
                          from: "the id SES gave this email; mail_log.message_id holds the same",
                          to: "the id SES gave this email (mail_log.message_id holds the same), or the SID Twilio gave this text"
  end
end
