# frozen_string_literal: true

class BroadcastMessage < ApplicationRecord
  self.table_name = "broadcast_message"

  PAGE_SIZE_DEFAULT = 50

  # How many of the latest texts SMS Management's Delivery Reports row looks
  # over for one Twilio has reported on: more than a broadcast to everyone.
  RECEIPT_LOOKBACK = 2_000

  belongs_to :person, optional: true
  belongs_to :broadcast, optional: true

  scope :for_year, ->(year) { where_year("created_at", year) }

  # The messages that could go again to their person now, worked out each time
  # it is asked: time passes between a broadcast failing and someone sending it
  # again, and in that time a Ranger may have asked us to stop, changed their
  # number, or left. The one rule for who a Retry sends to.
  #
  # An email goes to the address on its row, so only the person is asked about.
  # A text goes only to a number still theirs, confirmed and not stopped. No
  # other kind of message is ever sent again.
  scope :sendable, lambda {
    reachable = joins(:person).where.not(person: { status: Person::NO_MESSAGES_STATUSES })
    reachable.where(address_type: "email")
             .or(reachable.where(address_type: "sms", person: { sms_verified: true, sms_stopped: false })
                          .where(arel_table[:address].eq(Person.arel_table[:sms_number])))
  }

  # Texts Twilio took that no receipt has moved on yet: the rows record_receipt
  # would change.
  scope :awaiting_receipt, lambda {
    where(address_type: "sms", direction: "outbound", status: [Broadcast::STATUS_SENT, Broadcast::STATUS_VERIFY])
      .where.not(message_id: nil)
  }

  class << self
    include Pagy::Method

    # Find all unknown phone numbers (aka spam) for a given year.
    def find_unknown_phones_for_year(year)
      where(status: Broadcast::STATUS_UNKNOWN_PHONE)
        .for_year(year)
        .order(created_at: :desc)
    end

    # Retrieve all unknown phone numbers for the last 24 hours.
    def retrieve_unknown_phones_for_daily_report
      where(status: Broadcast::STATUS_UNKNOWN_PHONE)
        .where(created_at: (Current.time - 24.hours)..)
    end

    # Find broadcast messages based on query parameters.
    #
    # @param query [Hash] Query parameters
    #   - status: specific status to find
    #   - year: specific year
    #   - person_id: specific person
    #   - direction: 'inbound' or 'outbound'
    #   - order: 'asc' or 'desc' (default: 'desc')
    #   - page: page number (1 to n)
    #   - page_size: size of page (default: PAGE_SIZE_DEFAULT)
    #
    # @return [Hash] { messages:, meta: { total:, total_pages:, page_size:, page: } }
    def find_for_query(query)
      scope = includes(:person)

      scope = scope.for_year(query[:year]) if query[:year].present?
      scope = scope.where(person_id: query[:person_id]) if query[:person_id].present?
      scope = scope.where(status: query[:status]) if query[:status].present?
      scope = scope.where(direction: query[:direction]) if query[:direction].present?

      order_dir = (query[:order] == "asc") ? :asc : :desc
      scope = scope.order(created_at: order_dir)

      page = (query[:page] || 1).to_i
      page = 1 if page < 1
      page_size = (query[:page_size] || PAGE_SIZE_DEFAULT).to_i
      page_size = PAGE_SIZE_DEFAULT if page_size <= 0

      pagy_instance, records = pagy(:offset, scope, page: page, limit: page_size,
                                    request: { params: {} })

      # A page number past the end asks the database for an offset it cannot
      # reach and leaves the reader on an empty table under a heading claiming a
      # full one. Land them on the last page there actually is.
      if page > pagy_instance.pages
        pagy_instance, records = pagy(:offset, scope, page: pagy_instance.pages, limit: page_size,
                                      request: { params: {} })
      end

      {
        messages: records,
        meta: {
          total: pagy_instance.count,
          total_pages: pagy_instance.pages,
          page_size: pagy_instance.limit,
          page: pagy_instance.page
        }
      }
    end

    # Record an inbound or outbound message which might be associated
    # with a person and/or broadcast.
    #
    # @param broadcast_id [Integer, nil] broadcast identifier
    # @param status [String] message status (Broadcast::STATUS_*)
    # @param person_id [Integer, nil] person identifier
    # @param type [String] message type (sms, email, clubhouse)
    # @param address [String] email or sms address
    # @param direction [String] outbound (sent by Clubhouse) or inbound (received by Clubhouse)
    # @param message [String, nil] incoming message from phone (optional)
    # @param message_id [String, nil] the SID Twilio gave a text it took
    # @return [Integer] the id of the newly created broadcast_message row
    def record(broadcast_id, status, person_id, type, address, direction, message = nil, message_id: nil)
      columns = { direction:, status:, address_type: type, address:, message_id: }

      columns[:broadcast_id] = broadcast_id if broadcast_id.present?
      columns[:person_id] = person_id if person_id.present?
      columns[:message] = message if message.present?

      create!(columns).id
    end

    # Record many outbound messages of one broadcast at once -- the rows
    # record writes one at a time, in a single insert. The broadcast, type and
    # direction are this method's to set, whatever a message carries.
    #
    # @param broadcast_id [Integer] broadcast identifier
    # @param type [String] message type (sms, email, clubhouse)
    # @param messages [Array<Hash>] person_id:, address:, status:, message_id: -- every message carrying the
    #   same keys, message_id: nil included, as a single insert needs
    def record_outbound(broadcast_id, type, messages)
      insert_all(messages.map { |message| { **message, broadcast_id:, address_type: type, direction: "outbound" } })
    end

    # Count failed messages for a broadcast and address type: every message
    # that did not go, whatever the reason -- whether or not sending it again
    # could help.
    #
    # @param broadcast_id [Integer] broadcast identifier
    # @param address_type [String] address type (sms, email)
    # @return [Integer] count of failed messages
    def count_fail(broadcast_id, address_type)
      where(broadcast_id:, address_type:, status: Broadcast::FAILURE_STATUSES).count
    end

    # SES reported a broadcast email bounced, of any type: its copy moves from
    # sent to bounced. The broadcast, the person and SES's id all come from the
    # mail log row the report stamped -- never the person at the bounced
    # address, which in test address mode is nobody's -- so the match is the
    # one copy, also after a Retry gave its row a new id. broadcast_id carries
    # the index; message_id has none.
    #
    # A bounce is not a failure: the email went, and a Retry could not make it
    # arrive, so email_failed is left as it is. A repeated report finds no sent
    # row and changes nothing.
    #
    # @param mail_log [MailLog, nil] the row the report stamped, if any
    # @return [Integer, nil] how many rows moved, or nil for no broadcast email
    def mark_email_bounced(mail_log)
      return if mail_log&.broadcast_id.nil?

      where(broadcast_id: mail_log.broadcast_id, person_id: mail_log.person_id, message_id: mail_log.message_id,
            address_type: "email", status: Broadcast::STATUS_SENT)
        .update_all(status: Broadcast::STATUS_BOUNCED)
    end

    # Twilio's delivery receipt for one text the Clubhouse sent: the row whose
    # id and SID both match moves on from sent -- or from a confirmation
    # code's verify -- to what Twilio said, once. Anything else changes
    # nothing: a receipt for an earlier status (they come out of order, and
    # none comes for accepted), a repeat, a row not yet settled, an id that
    # is not that text's. One indexed update; a text that did not arrive is
    # also counted on its broadcast's sms_failed.
    #
    # @param id [String] the row's id, from the receipt address
    # @param sid [String] the SID Twilio gave the text
    # @param status [String] Broadcast::STATUS_*, from SmsService.process_status_callback
    # @return [Integer] how many rows moved, 0 or 1
    def record_receipt(id, sid, status)
      return 0 unless Broadcast::RECEIPT_STATUSES.include?(status) && sid.present?

      moved = awaiting_receipt.where(id:, message_id: sid).update_all(status:)
      if moved.positive? && Broadcast::FAILURE_STATUSES.include?(status)
        broadcast_id = where(id:).pick(:broadcast_id)
        Broadcast.recount_failed_texts(broadcast_id) if broadcast_id
      end
      moved
    end

    # When the newest text Twilio has reported on was sent, among the latest
    # RECEIPT_LOOKBACK texts the Clubhouse sent; nil when none of them has a
    # receipt. One query, newest rows first.
    def last_text_receipt_at
      latest = where(address_type: "sms", direction: "outbound").order(id: :desc).limit(RECEIPT_LOOKBACK)
      from(latest, table_name).where(status: Broadcast::RECEIPT_STATUSES).maximum(:created_at)
    end

    # Who already has a row of this type for a broadcast: the people a send
    # picked up again leaves alone.
    #
    # @param broadcast_id [Integer] broadcast identifier
    # @param address_type [String] address type (sms, email)
    # @return [Array<Integer>] person ids
    def person_ids_for(broadcast_id, address_type)
      where(broadcast_id:, address_type:).pluck(:person_id)
    end
  end
end
