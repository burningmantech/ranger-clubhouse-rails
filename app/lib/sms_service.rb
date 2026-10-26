# frozen_string_literal: true

#
# SMS Services provided by Twilio.
#
# Handle sending SMS broadcasts, processing incoming messages,
# and phone number normalization.
#
# Converted from SMSService.php (Laravel/PHP)
#

class SmsService
  # Do not reply to stop replies
  NO_STOP_REPLIES = 1

  # How long Twilio may hold a text it has not yet managed to send before
  # failing it, in seconds. An alert or a code hours late is no use, and
  # Twilio's own default is ten hours.
  VALIDITY_PERIOD = 2.hours.to_i

  #
  # Structured result for incoming SMS messages.
  # Replaces the PHP associative array return from processIncoming().
  #
  class IncomingMessage
    attr_reader :phone, :message, :raw

    def initialize(phone:, message:, raw:)
      @phone = phone
      @message = message
      @raw = raw
    end
  end

  #
  # Structured result for status callbacks.
  # Replaces the PHP associative array return from processStatusCallback().
  #
  class StatusCallback
    attr_reader :status, :message, :broadcast_id, :phone

    def initialize(status:, message:, broadcast_id:, phone:)
      @status = status
      @message = message
      @broadcast_id = broadcast_id
      @phone = phone
    end
  end

  class << self
    #
    # Retrieve the authentication tokens needed for Twilio.
    #
    # @return [Array<String>] [account_sid, auth_token]
    # @raise [RuntimeError] if TwilioAccountSID or TwilioAuthToken is not configured
    #
    def get_tokens
      sid, auth_token = TwilioAccount.settings.values_at(:account_sid, :auth_token)
      raise "TwilioAccountSID is not configured" if sid.blank?
      raise "TwilioAuthToken is not configured" if auth_token.blank?

      [sid, auth_token]
    end

    #
    # Broadcast a message to a set of phone numbers.
    #
    # @param phone_numbers [Array<String>] list of phone numbers to send to
    # @param message [String] text to send
    # @return [String] "sent" on success
    # @raise [SmsException] if Twilio experienced an error
    #
    def broadcast(phone_numbers, message)
      account_sid, auth_token = get_tokens

      service_ids = TwilioAccount.settings[:service_ids]
      raise "TwilioServiceId is not configured" if service_ids.all?(&:blank?)

      # Build up request - normalize the numbers
      bindings = phone_numbers.map do |phone|
        { binding_type: "sms", address: normalize_phone(phone) }.to_json
      end

      service_count = service_ids.length
      chunk_size = (bindings.length + (service_count - 1)) / service_count
      binding_chunks = bindings.each_slice(chunk_size).to_a

      twilio = TwilioAccount.build_client(account_sid, auth_token)
      service_ids.each_with_index do |service_id, idx|
        chunk = binding_chunks[idx]
        next if chunk.blank?

        # The Twilio notify API will not produce an error when
        # an invalid phone number is given.
        begin
          notification = twilio.notify.v1.services(service_id).notifications
          notification.create(
            body: message,
            to_binding: chunk
          )
        rescue Twilio::REST::TwilioError => e
          raise SmsException, "service #{service_id}: #{e.message}"
        end
      end

      "sent"
    end

    #
    # Send one text through the Messaging Service in TwilioMessagingServiceId,
    # with the Messages API, which outlives Notify (gone 2027-01-31).
    #
    # @param phone_number [String] number to text
    # @param message [String] text to send
    # @return [String] the SID Twilio gave the text
    # @raise [SmsException::Unconfirmed] if Twilio may have taken it without answering
    # @raise [SmsException] if Twilio refused it, or the Messaging Service setting cannot be used
    #
    def send_text(phone_number, message)
      account_sid, auth_token = get_tokens
      service_id = TwilioAccount.settings[:messaging_service_id]
      problem = TwilioAccount.messaging_service_problem(service_id)
      raise SmsException, problem if problem

      twilio = TwilioAccount.build_client(account_sid, auth_token)
      twilio.messages.create(messaging_service_sid: service_id, to: normalize_phone(phone_number), body: message,
                             validity_period: VALIDITY_PERIOD).sid
    rescue *TwilioAccount::ERRORS => e
      error_class = TwilioAccount.unanswered?(e) ? SmsException::Unconfirmed : SmsException
      raise error_class, e.message
    end

    #
    # Try to find out if a phone number can text, maybe.
    #
    # Note this may only work for US numbers.
    #
    # @see https://support.twilio.com/hc/en-us/articles/360004563433
    #
    # @param phone_number [String] number to look up in E.164 format
    # @return [Boolean] true if the phone can text
    #
    def sms_capable?(phone_number)
      account_sid, auth_token = get_tokens

      twilio = TwilioAccount.build_client(account_sid, auth_token)

      begin
        info = twilio.lookups.v1.phone_numbers(phone_number)
          .fetch(type: ["carrier"])
      rescue Twilio::REST::RestError => e
        return false if e.status_code == 404 # Not a valid phone number

        raise # Not sure what's going on.
      end

      type = info.carrier["type"]
      # In case there's no line type, allow it to pass. The verification
      # stage will flush that out.
      type == "mobile" || type == "voip" || type == ""
    end

    #
    # Process an incoming message into a common format.
    #
    # @param params [Hash, ActionController::Parameters] the request parameters
    # @return [SmsService::IncomingMessage] structured incoming message
    #
    def process_incoming(params)
      IncomingMessage.new(
        phone: params[:From].to_s,
        message: params[:Body].to_s,
        raw: params.to_json
      )
    end

    #
    # Process a status callback.
    #
    # @param params [Hash, ActionController::Parameters] the request parameters
    # @return [SmsService::StatusCallback] structured status callback result
    #
    def process_status_callback(params)
      status_code = params[:MessageStatus]

      status = case status_code
               when "delivered"
                 "delivered"
               when "undelivered", "failed"
                 "failed"
               else
                 "sent"
               end

      if status == "failed"
        error_code = params[:ErrorCode].to_i
        status = case error_code
                 when 30004 # phone maybe black listed
                   "blocked"
                 when 30005, 30006, 30007 # unreachable phone, landline
                   "bounced"
                 else
                   status
                 end
      end

      StatusCallback.new(
        status: status,
        message: params.to_json,
        broadcast_id: params[:broadcast_id].to_s,
        phone: params[:To].to_s
      )
    end

    #
    # Format a TwiML reply response.
    #
    # Returns the TwiML XML string for the controller to render,
    # or an empty string if no reply is needed.
    #
    # @param reply [String, nil] the reply message text
    # @return [String] TwiML XML string, or empty string
    #
    def reply_response(reply)
      return "" if reply.blank?

      response = Twilio::TwiML::MessagingResponse.new
      response.message(body: reply)
      response.to_s
    end

    #
    # Normalize a phone number to E.164 format for use by Twilio.
    #  - number needs to start with a '+'
    #  - number needs to have a country code
    #  - 10 chars long with no + prefix assumes to be a US/Canadian number.
    #
    # @param phone [String] number to normalize
    # @return [String] normalized number in E.164 format
    #
    def normalize_phone(phone)
      phone = phone.strip
      normalized = phone.gsub(/\W+/, "")
      len = normalized.length

      country = nil
      if len == 10 || (phone.start_with?("1") && len == 11)
        country = "US"
      end

      parsed = Phonelib.parse(phone, country)
      if parsed.valid?
        parsed.e164
      else
        phone
      end
    end
  end
end
