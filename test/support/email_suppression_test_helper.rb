# frozen_string_literal: true

# Writes an email_suppression row the way an SES report does, through
# EmailSuppression.record. There are no fixture rows: fixtures :all would load
# them into every test.
module EmailSuppressionTestHelper
  def suppress_email(address, reason: EmailSuppression::BOUNCE, sub_type: nil, message_id: nil)
    EmailSuppression.record(address, reason:, sub_type:, message_id:)
    EmailSuppression.find_by!(email: address)
  end
end
