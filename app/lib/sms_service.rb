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

  # How many times a text Twilio turns away for being asked too fast (HTTP
  # 429) is asked again: each pause twice the last, from a tenth of a second.
  RATE_LIMIT_RETRIES = 5

  # Twilio is asked about a text with no final receipt once it is this old
  # (Twilio's advice), and no longer once it is older than RECHECK_WITHIN; the
  # daily recheck asks about RECHECK_BATCH rows' worth at a time.
  RECHECK_AFTER = 12.hours
  RECHECK_WITHIN = 3.days
  RECHECK_BATCH = 100

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
  # What one of Twilio's delivery receipts says: the row the text was recorded
  # in (its id rides in the receipt address), the SID Twilio gave the text, and
  # the Clubhouse's word for what became of it.
  #
  StatusCallback = Data.define(:row_id, :sid, :status)

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
    # @param receipt_for [Integer, nil] the id of the row the text is recorded in, for Twilio's receipt
    # @return [String] the SID Twilio gave the text
    # @raise [SmsException::Unconfirmed] if Twilio may have taken it without answering
    # @raise [SmsException] if Twilio refused it, or the Messaging Service setting cannot be used
    #
    def send_text(phone_number, message, receipt_for: nil)
      service_id, account_sid, auth_token = text_settings
      text_through(TwilioAccount.build_client(account_sid, auth_token), service_id, phone_number, message,
                   receipt_for:)
    end

    #
    # What sending texts needs: the Messaging Service, and the account's tokens.
    #
    # @return [Array<String>] [messaging_service_id, account_sid, auth_token]
    # @raise [SmsException] if the Messaging Service setting cannot be used
    # @raise [RuntimeError] if TwilioAccountSID or TwilioAuthToken is not configured
    #
    def text_settings
      account_sid, auth_token = get_tokens
      service_id = TwilioAccount.settings[:messaging_service_id]
      problem = TwilioAccount.messaging_service_problem(service_id)
      raise SmsException, problem if problem

      [service_id, account_sid, auth_token]
    end

    #
    # Send one text through a client the caller made: a job sending many on a
    # few threads gives each thread a client of its own, as one client is not
    # safe to share. Asked again after a pause while Twilio answers that it is
    # being asked too fast. With receipt_for, Twilio reports what became of it
    # to receipt_address, the row's id in the query.
    #
    # @return [String] the SID Twilio gave the text
    # @raise [SmsException::Unconfirmed] if Twilio may have taken it without answering
    # @raise [SmsException] if Twilio refused it
    #
    def text_through(twilio, service_id, phone_number, message, receipt_for: nil)
      address = receipt_for && receipt_address
      request = { messaging_service_sid: service_id, to: normalize_phone(phone_number), body: message,
                  validity_period: VALIDITY_PERIOD, status_callback: (address && "#{address}?message=#{receipt_for}") }
      attempts = 0
      begin
        twilio.messages.create(**request.compact).sid
      rescue Twilio::REST::RestError => e
        raise unless e.status_code == 429 && (attempts += 1) <= RATE_LIMIT_RETRIES

        sleep(0.1 * (2**(attempts - 1)) * rand(0.9..1.1))
        retry
      end
    rescue *TwilioAccount::ERRORS => e
      error_class = TwilioAccount.unanswered?(e) ? SmsException::Unconfirmed : SmsException
      raise error_class, e.message
    end

    #
    # Where Twilio sends this server its delivery receipts, or nil when Twilio
    # cannot reach it -- dev's localhost, say -- where asking would raise an
    # 11200 alert on the live account for every text.
    #
    # @return [String, nil]
    #
    def receipt_address
      address = TwilioSignatureConcern.address(Rails.application.routes.url_helpers.infrastructure_sms_status_path)
      address unless SmsManagement.incoming_url_problem(address)
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
    # Read one of Twilio's delivery receipts.
    #
    # @param params [Hash, ActionController::Parameters] the receipt Twilio posted
    # @param row_id [String] the row's id, from the receipt address's query
    # @return [SmsService::StatusCallback]
    #
    def process_status_callback(params, row_id)
      StatusCallback.new(row_id: row_id.to_s, sid: params[:MessageSid].to_s,
                         status: receipt_status(params[:MessageStatus], params[:ErrorCode]))
    end

    #
    # The Clubhouse's word for a text's status at Twilio: sent, while it is
    # still on its way (Twilio sends no receipt for accepted); delivered; or,
    # where it did not arrive, blocked, bounced or failed, by Twilio's error code.
    #
    # @param message_status [String] Twilio's MessageStatus
    # @param error_code [String, Integer, nil] Twilio's ErrorCode
    # @return [String] Broadcast::STATUS_*
    #
    def receipt_status(message_status, error_code)
      case message_status
      when "delivered"
        Broadcast::STATUS_DELIVERED
      when "undelivered", "failed"
        case error_code.to_i
        when 30004 # phone maybe black listed
          Broadcast::STATUS_BLOCKED
        when 30005, 30006, 30007 # unreachable phone, landline
          Broadcast::STATUS_BOUNCED
        else
          Broadcast::STATUS_FAILED
        end
      else
        Broadcast::STATUS_SENT
      end
    end

    #
    # Ask Twilio what became of each text still waiting for a receipt between
    # RECHECK_AFTER and RECHECK_WITHIN after it went, as Twilio advises: a
    # receipt is best-effort, none comes for accepted, and one that beats the
    # Clubhouse's own write of the SID is lost. What Twilio says is recorded
    # as a receipt would be (BroadcastMessage.record_receipt), so a late
    # receipt and the recheck never disagree. A text Twilio no longer has is
    # skipped; any other refusal, or no answer, stops the run, logged once,
    # and the next run asks again. Never on the training server.
    #
    # @return [Integer] how many texts moved
    #
    def recheck_unfinished_texts
      return 0 if Current.is_ghd_server?

      twilio = TwilioAccount.client
      return 0 if twilio.nil?

      moved = 0
      BroadcastMessage.awaiting_receipt.where(created_at: RECHECK_WITHIN.ago..RECHECK_AFTER.ago)
                      .in_batches(of: RECHECK_BATCH) do |batch|
        batch.pluck(:id, :message_id).each do |id, sid|
          text = twilio.messages(sid).fetch
          moved += BroadcastMessage.record_receipt(id, sid, receipt_status(text.status, text.error_code))
        rescue Twilio::REST::RestError => e
          raise unless e.status_code == 404
        end
      end
      moved
    rescue *TwilioAccount::ERRORS => e
      ErrorLog.record_exception(e, "sms-recheck-exception", extra: { moved: })
      moved
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
