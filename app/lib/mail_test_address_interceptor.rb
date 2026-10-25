# frozen_string_literal: true

#
# Sends every email the Clubhouse delivers to one test inbox while
# RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS is set, so the maintainer can read each
# kind of mail before anyone else gets it. Registered by
# config/initializers/mail_delivery.rb, in every environment.
#
# Read from the environment at each delivery, never from a setting: a
# Clubhouse 2 restore replaces the setting table and would clear the address
# without a word.
#
# Each email reaches the inbox as a member would get it -- subject and body
# unchanged -- with To the test inbox, no Cc or Bcc, and the recipients it was
# for in one header. Held mail is left alone: it goes nowhere anyway, and the
# training server's keeps its real recipients.
#
# This covers all ActionMailer mail, new-message alerts and the scheduled team
# mail included. Broadcast email never passes through here (Rbs hands it to
# SES itself); it has its own test address, BroadcastMailTestAddress.
#
class MailTestAddressInterceptor
  ADDRESS_VAR = "RANGER_CLUBHOUSE_MAIL_TEST_ADDRESS"

  # Where the test inbox's copy says who the email was for.
  RECIPIENTS_HEADER = "X-Clubhouse-Original-Recipients"

  class ConfigurationError < StandardError; end

  class << self
    def delivering_email(message)
      address = test_address
      return if address.nil? || !message.perform_deliveries

      message[RECIPIENTS_HEADER] = message.destinations.join(", ")
      message.to = address
      message.cc = nil
      message.bcc = nil
      # SMTP, and SES through SesMailDelivery, would send to this instead of To.
      message.smtp_envelope_to = nil
    end

    # Refuse to boot with a test address that is not one address SES would
    # take. Better than every email failing, or reaching nobody, unnoticed.
    def validate!
      address = test_address
      return if address.nil? || EmailAddresses.sendable?(address)

      raise ConfigurationError, "#{ADDRESS_VAR} must be one email address, such as test@example.com, " \
                                "not #{address.inspect}"
    end

    private

    def test_address
      ENV[ADDRESS_VAR].to_s.strip.presence
    end
  end
end
