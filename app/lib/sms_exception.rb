# frozen_string_literal: true

# What SmsService.broadcast raises when Twilio refuses a text or cannot be
# reached. Its own file, so the autoloader finds it before SmsService loads.
class SmsException < StandardError; end
