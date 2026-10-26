# frozen_string_literal: true

# What SmsService raises when Twilio refuses a text or cannot be reached. Its
# own file, so the autoloader finds it before SmsService loads.
class SmsException < StandardError
  # The call may have reached Twilio and no answer came back, so the text may
  # have gone out all the same: it is recorded send-unconfirmed, never sent again.
  class Unconfirmed < SmsException; end
end
