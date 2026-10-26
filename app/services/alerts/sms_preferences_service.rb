# frozen_string_literal: true

module Alerts
  class SmsPreferencesService
    Result = Data.define(:success, :status, :errors) do
      alias_method :success?, :success
    end

    # All regions on the +44 numbering plan: United Kingdom, Guernsey, Isle of Man, Jersey
    UNSUPPORTED_COUNTRY_CODES = %w[GB GG IM JE].freeze

    class << self
      # Save a new SMS number for a person. Normalizes, validates uniqueness,
      # checks country support, resets verification state when changed,
      # generates a code, and attempts to send it.
      #
      # @param person [Person] the person to update
      # @param raw_number [String] the raw phone number input
      # @return [Result]
      def save_number(person:, raw_number:)
        raw_number = raw_number.to_s.strip

        # Allow clearing the number
        if raw_number.blank?
          person.sms_number = nil
          person.reset_sms_verification!
          person.save(validate: false)
          return Result.new(success: true, status: "cleared", errors: {})
        end

        # Normalize with Phonelib via SmsService
        normalized = SmsService.normalize_phone(raw_number)

        # Validate the number is parseable
        parsed = Phonelib.parse(normalized)
        unless parsed.valid?
          return Result.new(
            success: false,
            status: "invalid-number",
            errors: { sms_number: "does not appear to be a valid phone number" }
          )
        end

        # Block numbers on the +44 numbering plan (UK telecom regulatory restriction)
        blocked = (Array(parsed.countries) & UNSUPPORTED_COUNTRY_CODES)
        if blocked.any?
          region = blocked.first
          return Result.new(
            success: false,
            status: "country-not-supported",
            errors: { sms_number: "Sorry, #{country_name(region)} phone numbers cannot be used at this time" }
          )
        end

        # Check uniqueness - number must not belong to another person
        existing = Person.where.not(id: person.id).where(sms_number: normalized).exists?
        if existing
          return Result.new(
            success: false,
            status: "duplicate-number",
            errors: { sms_number: "is already used by another account" }
          )
        end

        # If the number hasn't changed, nothing to do
        if person.sms_number == normalized
          return Result.new(success: true, status: "unchanged", errors: {})
        end

        # Update number and reset verification
        person.sms_number = normalized
        person.reset_sms_verification!

        # Generate code and attempt to send
        code = person.generate_sms_code!
        person.save(validate: false)

        send_status = deliver_verification_code(person, normalized, code)

        Result.new(success: true, status: send_status, errors: {})
      end

      # Resend a verification code. Only when number exists and is not verified.
      #
      # @param person [Person] the person
      # @return [Result]
      def send_code(person:)
        if person.sms_number.blank?
          return Result.new(success: false, status: "no-number", errors: {})
        end

        if person.sms_verified?
          return Result.new(success: false, status: "already-verified", errors: {})
        end

        code = person.generate_sms_code!
        person.save(validate: false)

        send_status = deliver_verification_code(person, person.sms_number, code)

        Result.new(success: true, status: send_status, errors: {})
      end

      # Confirm a verification code.
      #
      # @param person [Person] the person
      # @param code [String] the submitted verification code
      # @return [Result]
      def confirm_code(person:, code:)
        if person.sms_number.blank?
          return Result.new(success: false, status: "no-number", errors: {})
        end

        if person.sms_verified?
          return Result.new(success: false, status: "already-verified", errors: {})
        end

        submitted = code.to_s.strip
        if person.sms_code.blank? ||
           !ActiveSupport::SecurityUtils.secure_compare(person.sms_code, submitted)
          return Result.new(
            success: false,
            status: "no-match",
            errors: { verification_code: "does not match the code sent to your phone" }
          )
        end

        person.mark_sms_verified!

        Result.new(success: true, status: "confirmed", errors: {})
      end

      private

      # Send a verification code via SMS and log it, with the SID Twilio gave
      # the text. A code Twilio may have taken without answering is recorded
      # send-unconfirmed, and the person is still told it could not be sent:
      # sending again makes a new code.
      #
      # @return [String] "sent" or "sent-fail"
      def deliver_verification_code(person, phone, code)
        message = "Your Clubhouse verification code is: #{code}"

        begin
          sid = SmsService.send_text(phone, message)
          BroadcastMessage.record(nil, Broadcast::STATUS_VERIFY, person.id, "sms", phone, "outbound", message,
                                  message_id: sid)
          "sent"
        rescue StandardError => e
          ErrorLog.record_exception(e, "sms-exception", extra: {
            type: "sms-verify",
            person_id: person.id,
            phone: phone
          })
          if e.is_a?(SmsException::Unconfirmed)
            BroadcastMessage.record(nil, Broadcast::STATUS_SEND_UNCONFIRMED, person.id, "sms", phone, "outbound",
                                    message)
          end
          "sent-fail"
        end
      end

      def country_name(code)
        case code
        when "GB" then "United Kingdom"
        when "GG" then "Guernsey"
        when "IM" then "Isle of Man"
        when "JE" then "Jersey"
        else code
        end
      end
    end
  end
end
