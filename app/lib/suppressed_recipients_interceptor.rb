# frozen_string_literal: true

#
# Leaves out of every email the addresses the Clubhouse should not mail: the
# ones EmailSuppression holds because they bounced for good, or because their
# owner reported a Clubhouse email as spam. Through SES each email to a dead
# address is a fresh bounce, and enough of them pause the account, broadcast
# email included. Registered by config/initializers/mail_delivery.rb, in every
# environment, ahead of MailTestAddressInterceptor: it must see the real
# recipients before the test address replaces them.
#
# One query asks about every To, Cc and Bcc address together. Each suppressed
# address is dropped from its field, the others stay as written, and a field
# left empty goes. An email left with nobody to send to is held, so it is
# never sent and gets no mail log row.
#
# Each dropped address gets an email-suppressed action log, not an error log:
# the skip is what should happen. It names the person, so it sits beside the
# bounce or complaint log that put the address on the record and answers
# "why didn't my reset arrive?".
#
# Held mail (the training server's) never leaves, so it is not looked at. A
# lookup that fails lets the email go as it is, and says so in the error log:
# a password reset matters more than one bounce. A log that cannot be written
# never stops an email.
#
# This covers all ActionMailer mail, new-message alerts and the scheduled team
# mail included. Broadcast email never passes through here (Rbs hands it to
# SES itself).
#
class SuppressedRecipientsInterceptor
  FIELDS = %i[to cc bcc].freeze

  class << self
    def delivering_email(message)
      return unless message.perform_deliveries

      suppressed = suppressed_recipients(message)
      return if suppressed.empty?

      FIELDS.each { |field| drop(message, field, suppressed) }
      # SMTP raises on an email with no recipient, and SES would be asked to
      # send nothing.
      message.perform_deliveries = false if message.destinations.empty?
      suppressed.each { |address| record_skip(message, address) }
    end

    private

    # The recipients the record holds, written as the message writes them.
    # Destinations are the To, Cc and Bcc addresses together.
    def suppressed_recipients(message)
      EmailSuppression.suppressed(message.destinations)
    rescue ActiveRecord::ActiveRecordError => e
      record_failure(e, "email-suppression-lookup-failed", message)
      Set.new
    end

    # Rebuilt from the field's own addresses, display names and all, so the
    # ones kept read as they did. An empty field is removed, not sent blank.
    def drop(message, field, suppressed)
      return unless suppressed.intersect?(Array(message.public_send(field)))

      kept = message[field].addrs.reject { |address| suppressed.include?(address.address) }
      message[field] = kept.empty? ? nil : kept.map(&:format)
    end

    # The actor is nobody, as in the SES report logs; the target is whoever
    # holds the address, as the bounce log finds them.
    def record_skip(message, address)
      ActionLog.record(nil, "email-suppressed", "",
                       { to_email: address, mailer: mailer_name(message), subject: message.subject },
                       Person.find_by(email: address)&.id)
    rescue ActiveRecord::ActiveRecordError => e
      record_failure(e, "email-suppressed-log-failed", message)
    end

    # Names the mailer, never an address or the body.
    def record_failure(error, error_type, message)
      ErrorLog.record_exception(error, error_type, extra: { mailer: mailer_name(message) })
    rescue StandardError
      nil
    end

    # ActionMailer makes the mailer class the message's delivery handler.
    def mailer_name(message) = message.delivery_handler&.name
  end
end
