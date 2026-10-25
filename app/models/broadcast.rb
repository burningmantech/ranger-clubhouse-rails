# frozen_string_literal: true

class Broadcast < ApplicationRecord
  self.table_name = "broadcast"

  # Broadcast Types
  TYPE_GENERAL = "general"            # General non-emergency announcement
  TYPE_SLOT_EDIT = "slot-edit"        # Slot time change or deletion cancellation
  TYPE_POSITION = "position"          # People who hold a position
  TYPE_SLOT = "slot"                  # People who are signed up for a shift
  TYPE_ONSHIFT = "onshift"            # Send to people on shift
  TYPE_RECRUIT_DIRT = "recruit-dirt"  # Request for more people for a shift, dirt
  TYPE_RECRUIT_POSITION = "recruit-position" # Request for more people based on position
  TYPE_EMERGENCY = "emergency" # All hands on deck - limited to playa

  # Status Constants
  STATUS_SENT = "sent"                    # Accepted by SES or the SMS vendor (or held, as if sent)
  STATUS_SERVICE_FAIL = "service-fail"    # Email never reached SES, or was held back; a text whose vendor call failed
  STATUS_VERIFY = "verify"                # Verify code sent to target phone
  STATUS_STOP = "stop"                    # Stop request received
  STATUS_START = "start"                  # Start request received
  STATUS_HELP = "help"                    # Help request was received from phone
  STATUS_STATS = "stats"                  # Administration command - reply with a 24 hour activity summary
  STATUS_NEXT = "next"                    # Next shift request
  STATUS_UNKNOWN_COMMAND = "unknown-command" # Unknown command / message was received from phone
  STATUS_UNKNOWN_PHONE = "unknown-phone"  # Message received from an unknown phone number
  STATUS_REPLY = "reply"                  # Reply sent in response to an inbound message
  STATUS_BOUNCED = "bounced"              # Email or SMS message was bounced
  STATUS_BLOCKED = "blocked"              # SMS message was blocked
  STATUS_SUPPRESSED = "suppressed"        # Email never sent: EmailSuppression holds the address. Not a failure
  # Email never sent, and not a failure. Only the email send writes it as a
  # row, for someone who opted out of the alert's email or has no address on
  # file. The text reason (Rbs::SMS_STATUS_NO_CONTACT) is the same string, but
  # lives only on the recipient in memory: no text row is written with it.
  STATUS_NO_CONTACT = "no-contact"

  # Why a broadcast email did not go. SES's own reasons, lowercased with dashes
  # (ACCOUNT_THROTTLED is "account-throttled"); "failed" stands in for any
  # reason SES gives that is not on this list. Two are the Clubhouse's own:
  # an address SES would refuse never goes to it, and an email SES may have
  # sent without saying so -- a timeout, a fault on its side, a short answer --
  # is never assumed unsent.
  STATUS_INVALID_PARAMETER = "invalid-parameter"
  STATUS_SEND_UNCONFIRMED = "send-unconfirmed"
  STATUS_FAILED = "failed"
  EMAIL_FAIL_STATUSES = [
    "message-rejected", STATUS_INVALID_PARAMETER, "transient-failure", "account-throttled",
    "account-daily-quota-exceeded", "account-sending-paused", "configuration-set-sending-paused",
    "account-suspended", "mail-from-domain-not-verified", "configuration-set-not-found", "template-not-found",
    "invalid-sending-pool-name", STATUS_FAILED, STATUS_SEND_UNCONFIRMED
  ].freeze

  # Every status a message that did not go can have.
  FAILURE_STATUSES = [STATUS_SERVICE_FAIL, *EMAIL_FAIL_STATUSES].freeze

  # Every status a text or email the send tried can end in: sent or held,
  # bounced or blocked after it went, or a failure. The reasons a send skipped
  # someone (no-contact, suppressed) stay out by design, and so does any skip
  # reason added later, since the list names what counts. A new outcome status
  # is the opposite: whoever starts writing one adds it here, or it drops out
  # of the stats.
  ATTEMPTED_STATUSES = [STATUS_SENT, STATUS_BOUNCED, STATUS_BLOCKED, *FAILURE_STATUSES].freeze

  # The failures a Retry never sends: an address SES would refuse never gets
  # better, and an email SES may already have sent is never sent twice. Every
  # other failure was certainly not sent, and is worth another try.
  UNRETRYABLE_STATUSES = [STATUS_INVALID_PARAMETER, STATUS_SEND_UNCONFIRMED].freeze
  RETRYABLE_STATUSES = (FAILURE_STATUSES - UNRETRYABLE_STATUSES).freeze

  # Associations
  belongs_to :sender, class_name: "Person", optional: true
  belongs_to :retry_person, class_name: "Person", optional: true
  belongs_to :alert, optional: true

  has_many :broadcast_message, dependent: :destroy
  # Exactly what a Retry sends: the failures worth another try, to people who
  # can still be messaged that way (BroadcastMessage.sendable). One left out
  # for its person keeps its status and stays counted, and goes on a later
  # Retry once that person can be reached again.
  has_many :failed_messages,
           -> { where(status: RETRYABLE_STATUSES).sendable },
           class_name: "BroadcastMessage"
  # Every failure a Retry won't send, whatever the reason, for the page that
  # says why. With failed_messages it makes up all the failures.
  has_many :unretryable_messages,
           ->(broadcast) { where(status: FAILURE_STATUSES).where.not(id: broadcast.failed_messages.select(:id)) },
           class_name: "BroadcastMessage"
  # The emails SES reported bounced. They are not failures: each one went, and
  # a Retry never sends them.
  has_many :bounced_messages,
           -> { where(status: STATUS_BOUNCED) },
           class_name: "BroadcastMessage"

  # Most rows are the one-person alerts sent when a Ranger receives a Clubhouse
  # message. Those are not broadcasts anyone sent to a group, so the history
  # separates them.
  NOTIFICATION_ALERTS = [
    Alert::CLUBHOUSE_NOTIFY_ON_PLAYA,
    Alert::CLUBHOUSE_NOTIFY_PRE_EVENT,
    Alert::RANGER_CONTACT,
    Alert::MENTOR_CONTACT
  ].freeze

  KIND_BROADCAST = "broadcast"
  KIND_NOTIFICATION = "notification"
  KINDS = [KIND_BROADCAST, KIND_NOTIFICATION].freeze

  # What a message log row can say happened, whichever way the message went.
  # Anything outside this list is a value the log cannot be filtered by.
  MESSAGE_STATUSES = [
    STATUS_SENT, STATUS_SERVICE_FAIL, STATUS_VERIFY, STATUS_REPLY,
    STATUS_START, STATUS_STOP, STATUS_HELP, STATUS_STATS, STATUS_NEXT,
    STATUS_UNKNOWN_COMMAND, STATUS_UNKNOWN_PHONE, STATUS_BOUNCED, STATUS_BLOCKED,
    STATUS_SUPPRESSED, STATUS_NO_CONTACT, *EMAIL_FAIL_STATUSES
  ].freeze

  scope :operator, -> { where.not(alert_id: NOTIFICATION_ALERTS) }
  scope :notifications, -> { where(alert_id: NOTIFICATION_ALERTS) }
  scope :with_failures, -> { where(arel_table[:sms_failed].gt(0).or(arel_table[:email_failed].gt(0))) }

  # Did anything fail to send?
  def failed?
    sms_failed.to_i.positive? || email_failed.to_i.positive?
  end

  # Is there anything a Retry would send? A broadcast can have failed with
  # nothing left to retry: its failures may not be worth another try, or be
  # for people who can no longer be messaged that way.
  def retryable?
    failed_messages.exists?
  end

  def notification?
    NOTIFICATION_ALERTS.include?(alert_id)
  end

  def kind
    notification? ? KIND_NOTIFICATION : KIND_BROADCAST
  end

  # A broadcast can reach thousands of people over three channels, which is more
  # rows than a page can usefully show. The list stops here and says so.
  RECIPIENT_LIMIT = 250

  # What the recipient list of this one broadcast looks like: a row per person,
  # carrying the outcome on each channel it was sent over.
  #
  # Only ever asked of a single broadcast -- the list pages report the count the
  # broadcast already stores instead.
  def recipients(limit: RECIPIENT_LIMIT)
    # The people are chosen first, in callsign order, and only then are their
    # messages loaded. Cutting the messages instead would hand back an
    # arbitrary set -- and could take one person's channels while leaving
    # another's, so a delivered email would read as never sent.
    person_ids = BroadcastMessage.where(broadcast_id: id)
                                 .joins(:person)
                                 .distinct
                                 .order(Arel.sql("person.callsign"))
                                 .limit(limit)
                                 .pluck(:person_id)
    return [] if person_ids.empty?

    people = Person.where(id: person_ids).index_by(&:id)
    rows = person_ids.index_with do |person_id|
      person = people[person_id]
      { person:, person_id:, callsign: person&.callsign,
        first_name: person&.first_name, last_name: person&.last_name }
    end

    BroadcastMessage.where(broadcast_id: id, person_id: person_ids).find_each do |message|
      next if message.address_type.blank?

      rows[message.person_id][message.address_type.to_sym] =
        { status: message.status, address: message.address }
    end

    rows.values
  end

  # What the send tried over the whole broadcast, keyed by address type
  # ("sms", "email", "clubhouse"), with a channel that has no such row left
  # out. Read from the rows, not recipients, which stops at RECIPIENT_LIMIT.
  # One query on the indexed broadcast_id, as bounced_messages and
  # BroadcastMessage.count_fail are, with no join to person, so a deleted
  # person's rows count, as they do in Failed.
  def attempted_counts
    broadcast_message.where(status: ATTEMPTED_STATUSES).group(:address_type).count
  end

  class << self
    #
    # The broadcasts to list, newest first.
    #
    # The people each one reached are not loaded: a single broadcast can carry
    # thousands of messages, and the list only reports how many there were.
    #
    # @param year [Integer] the year to list
    # @param kind [String] "broadcast", "notification", or nil for both
    # @param failed [Boolean] only those with a delivery failure
    # @param alert_id [Integer] only those sent under one alert type
    #
    def find_for_query(year:, kind: nil, failed: false, alert_id: nil)
      scope = includes(:alert, :sender, :retry_person)
                .where_year("broadcast.created_at", year)
                .order(created_at: :desc, id: :desc)

      scope = scope.operator if kind == KIND_BROADCAST
      scope = scope.notifications if kind == KIND_NOTIFICATION
      scope = scope.with_failures if failed
      scope = scope.where(alert_id:) if alert_id.present?

      scope
    end
  end
end
