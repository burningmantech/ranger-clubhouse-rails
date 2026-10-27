# frozen_string_literal: true

#
# The Ranger Broadcast System.
#
# Sends one message to a group of Rangers over three channels -- text, email,
# and Clubhouse message -- and records who it reached. Every channel is queued
# so a broadcast to thousands of people does not hold up the page. Texts go out
# through Twilio, one request a person; emails through Amazon SES, many people
# to a call.
#
class Rbs
  #
  # One person a broadcast may reach, and how they can be reached.
  #
  # A plain object rather than a Person: the two "can we use this channel"
  # answers are worked out per broadcast, and the send records a delivery
  # status on each one.
  #
  Recipient = Struct.new(:id, :callsign, :status, :first_name, :preferred_name, :last_name,
                         :email, :sms_number, :use_sms, :use_email, :sms_status, :email_status,
                         keyword_init: true)

  #
  # What a send or a retry did: the people it touched, with per-channel
  # results, and the counts the results page reports.
  #
  TransmitResult = Struct.new(:broadcast, :people, :texts_queued, :emails_queued,
                              :clubhouse_messages, :sent_sms, :sent_email, :sent_clubhouse,
                              keyword_init: true)

  # Positions which may have frequent shift muster requests
  FREQUENT_MUSTER_POSITIONS = [
    Position::DOUBLE_OH_7,
    Position::DIRT_GREEN_DOT,
    Position::GREEN_DOT_LEAD,
    Position::GREEN_DOT_MENTOR,
    Position::HQ_WINDOW,
    Position::RSC_SHIFT_LEAD,
    Position::TROUBLESHOOTER
  ].freeze

  # Delivery outcomes recorded against a person
  SMS_STATUS_NO_PHONE = "no-phone"
  SMS_STATUS_NO_CONTACT = Broadcast::STATUS_NO_CONTACT
  SMS_STATUS_STOPPED = "stopped"
  SMS_STATUS_UNVERIFIED = "unverified"
  EMAIL_STATUS_NO_CONTACT = Broadcast::STATUS_NO_CONTACT
  EMAIL_STATUS_NO_ADDRESS = "no-address"
  # An address EmailSuppression holds: it bounced for good, or its owner
  # reported a Clubhouse email as spam. The record does not say which. Never
  # "bounced", which is an email SES reported bounced (Broadcast::STATUS_BOUNCED).
  EMAIL_STATUS_SUPPRESSED = Broadcast::STATUS_SUPPRESSED

  # A text longer than 160 characters is split into several messages and billed
  # for each one, so the message a sender may type is the limit less the words
  # added to every text.
  SMS_PREFIX = ""
  SMS_SUFFIX = " TXT STOP to unsub"
  SMS_LIMIT = 160 - (SMS_PREFIX.size + SMS_SUFFIX.size)

  # Texts a broadcast's job sends at once, each on a thread with a Twilio
  # client of its own. A round is one text a thread, so it ends well inside the
  # time a deploy waits for a job (config.solid_queue.shutdown_timeout, 30 s),
  # even when a call runs to TwilioAccount's 5-second timeouts.
  SMS_THREADS = 4

  # The most people SES takes in one SendBulkEmail call.
  SES_BATCH_LIMIT = 50

  # The room a person's id takes in a test address beyond its ?, at most.
  TEST_ADDRESS_ID_ROOM = 10

  # What became of an email SES did not confirm taking: a status, and no
  # message id. Held email was never handed over (recorded as sent, as the
  # sandbox always has). A failed one never reached SES; an invalid one had an
  # address SES would refuse, so it was never tried. An unconfirmed one may
  # have been taken without SES saying so -- a timeout, a fault at its end, a
  # short answer -- so it is never assumed safe to send again.
  EMAIL_HELD = [Broadcast::STATUS_SENT, nil].freeze
  EMAIL_FAILED = [Broadcast::STATUS_SERVICE_FAIL, nil].freeze
  EMAIL_INVALID = [Broadcast::STATUS_INVALID_PARAMETER, nil].freeze
  EMAIL_UNCONFIRMED = [Broadcast::STATUS_SEND_UNCONFIRMED, nil].freeze

  # A whole call SES refused, by the exception it raised, as the reason SES
  # would have given each person -- which becomes a status the same way a
  # per-person reason does. Any other refusal the request never got past is
  # service-fail.
  SES_CALL_REFUSALS = {
    "TooManyRequestsException" => "ACCOUNT_THROTTLED",
    "LimitExceededException" => "ACCOUNT_THROTTLED",
    "SendingPausedException" => "ACCOUNT_SENDING_PAUSED",
    "AccountSuspendedException" => "ACCOUNT_SUSPENDED",
    "MailFromDomainNotVerifiedException" => "MAIL_FROM_DOMAIN_NOT_VERIFIED",
    "MessageRejected" => "MESSAGE_REJECTED"
  }.freeze

  # Failures in a row, each one that every later call would meet too, before
  # the rest of a broadcast is given up on. Missing keys or a paused account
  # would otherwise fail every call the same way, once a second, for as long
  # as the broadcast lasts.
  SES_FAILURES_BEFORE_GIVING_UP = 3

  # SES's answers about one person that are really about the account or its
  # setup, and so the same for everyone in every call.
  SES_ACCOUNT_REFUSALS = %w[
    ACCOUNT_SUSPENDED ACCOUNT_SENDING_PAUSED ACCOUNT_DAILY_QUOTA_EXCEEDED CONFIGURATION_SET_SENDING_PAUSED
    CONFIGURATION_SET_NOT_FOUND MAIL_FROM_DOMAIN_NOT_VERIFIED TEMPLATE_NOT_FOUND INVALID_SENDING_POOL_NAME
  ].freeze

  # Errors that mean no connection to SES was ever made, so nothing was sent.
  NEVER_CONNECTED = [Net::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
                     SocketError].freeze

  # One broadcast's email on its way out: what it says, and what the batches
  # so far have built and learned -- the finished email, what SES is handed,
  # the client, when the last call began, how many lasting failures in a row
  # there have been, how many people were not sent to once it gave up, and how
  # many were kept from being sent at all -- by a test address that cannot be
  # used, or a mode less safe than the one the job was queued in (`queued`),
  # with the mode and test address that stopped them (`refused_in`) -- whether the email could
  # not be drawn or handed to SES at all (`broken`), and who is in a call SES
  # may have taken that is not yet written down (`in_flight`). Built once per
  # job run, never kept beyond it.
  EmailRun = Struct.new(:broadcast_id, :alert, :subject, :message, :expires_at, :queued,
                        :mail, :content, :client, :last_call, :failures, :skipped, :unaddressed, :refused_in,
                        :broken, :in_flight,
                        keyword_init: true) do
    def initialize(failures: 0, skipped: 0, unaddressed: 0, **)
      super
    end
  end

  #
  # What each kind of broadcast asks for.
  #
  # is_simple - one short message, sent as a text and usually an email as well
  # sms_only - with is_simple, no email is sent
  # has_status - the sender picks which account statuses to reach
  # has_restrictions - the sender narrows by attendance and training
  # has_position - the sender picks one or more positions
  # has_muster_position - the sender picks one position that has a shift running
  # alerts - the alert types the sender may choose between
  # alert_id - with is_simple, the alert type the message always uses
  # has_slot - the sender picks one shift and reaches its sign-ups
  #
  ATTRIBUTES = {
    Broadcast::TYPE_GENERAL => {
      has_status: true,
      has_restrictions: true
    },

    Broadcast::TYPE_POSITION => {
      has_status: true,
      has_position: true,
      alerts: [
        Alert::TRAINING,
        Alert::SHIFT_CHANGE,
        Alert::SHIFT_MUSTER,
        Alert::SHIFT_CHANGE_PRE_EVENT,
        Alert::SHIFT_MUSTER_PRE_EVENT
      ]
    },

    Broadcast::TYPE_SLOT => {
      has_slot: true,
      alerts: [
        Alert::TRAINING,
        Alert::SHIFT_CHANGE,
        Alert::SHIFT_CHANGE_PRE_EVENT
      ]
    },

    # Sent from the shift editor when a shift's times change or it is cancelled,
    # so it has no page of its own.
    Broadcast::TYPE_SLOT_EDIT => {
      alerts: [
        Alert::TRAINING,
        Alert::SHIFT_CHANGE,
        Alert::SHIFT_CHANGE_PRE_EVENT
      ]
    },

    # The short broadcasts. Each takes one text-sized message, which is also
    # used as the email subject. No Clubhouse message is created.
    Broadcast::TYPE_ONSHIFT => {
      alert_id: Alert::ON_SHIFT,
      is_simple: true,
      sms_only: true
    },

    Broadcast::TYPE_RECRUIT_DIRT => {
      alert_id: Alert::SHIFT_MUSTER,
      is_simple: true
    },

    Broadcast::TYPE_RECRUIT_POSITION => {
      alert_id: Alert::SHIFT_MUSTER,
      is_simple: true,
      has_muster_position: true
    },

    Broadcast::TYPE_EMERGENCY => {
      alert_id: Alert::EMERGENCY_BROADCAST,
      is_simple: true
    }
  }.freeze

  # The kinds of broadcast that have a page of their own, in the order the
  # launchpad offers them.
  PAGE_TYPES = [
    Broadcast::TYPE_EMERGENCY,
    Broadcast::TYPE_ONSHIFT,
    Broadcast::TYPE_RECRUIT_DIRT,
    Broadcast::TYPE_RECRUIT_POSITION,
    Broadcast::TYPE_SLOT,
    Broadcast::TYPE_POSITION,
    Broadcast::TYPE_GENERAL
  ].freeze

  # Who may send each kind. A team lead may call up their own team; reaching
  # everyone, or every Ranger on shift, needs the wider permission, and the
  # emergency broadcast needs its own.
  MEGAPHONE_ROLES = [
    Role::ADMIN,
    Role::MEGAPHONE,
    Role::MEGAPHONE_TEAM_ONPLAYA,
    Role::MEGAPHONE_EMERGENCY_ONPLAYA
  ].freeze

  GENERAL_ROLES = [Role::ADMIN, Role::MEGAPHONE].freeze

  TYPE_ROLES = {
    Broadcast::TYPE_EMERGENCY => [Role::ADMIN, Role::MEGAPHONE_EMERGENCY_ONPLAYA].freeze,
    Broadcast::TYPE_ONSHIFT => GENERAL_ROLES,
    Broadcast::TYPE_RECRUIT_DIRT => GENERAL_ROLES,
    Broadcast::TYPE_GENERAL => GENERAL_ROLES,
    Broadcast::TYPE_RECRUIT_POSITION => MEGAPHONE_ROLES,
    Broadcast::TYPE_POSITION => MEGAPHONE_ROLES,
    Broadcast::TYPE_SLOT => MEGAPHONE_ROLES
  }.freeze

  # Alert types that belong to other features and are never offered here.
  NON_BROADCAST_ALERTS = [
    Alert::CLUBHOUSE_NOTIFY_ON_PLAYA,
    Alert::CLUBHOUSE_NOTIFY_PRE_EVENT,
    Alert::RANGER_CONTACT,
    Alert::MENTOR_CONTACT
  ].freeze

  # How a person may be narrowed down by their sign-ups for a position.
  SIGNED_UP_ANY = "any"
  SIGNED_UP_YES = "signed-up"
  SIGNED_UP_NO = "not-signed-up"
  SIGNED_UP_OPTIONS = [SIGNED_UP_ANY, SIGNED_UP_YES, SIGNED_UP_NO].freeze

  # How a person may be narrowed down by their in-person training.
  TRAINING_ANY = "any"
  TRAINING_PASSED = "passed"
  TRAINING_REGISTERED = "registered"
  TRAINING_NONE = "no-training"
  TRAINING_OPTIONS = [TRAINING_ANY, TRAINING_PASSED, TRAINING_REGISTERED, TRAINING_NONE].freeze

  # One shift a broadcast can be aimed at, and how many people are already
  # signed up for it.
  SlotChoice = Struct.new(:id, :position_id, :position_title, :begins, :description, :signed_up,
                          keyword_init: true)

  # The person columns a broadcast reads.
  RECIPIENT_COLUMNS = %w[
    person.id person.callsign person.status person.first_name person.preferred_name
    person.last_name person.email person.sms_number person.sms_verified person.sms_stopped
  ].freeze

  # Where the address sits in each row a broadcast reads.
  RECIPIENT_EMAIL = RECIPIENT_COLUMNS.index("person.email")

  class << self
    # =======================================================================
    # Permissions
    # =======================================================================

    # May the signed-in person send this kind of broadcast?
    def type_allowed?(type)
      roles = TYPE_ROLES[type]
      roles.present? && Current.has_role?(roles)
    end

    # Every kind the signed-in person may send, in launchpad order.
    def allowed_types
      PAGE_TYPES.select { |type| type_allowed?(type) }
    end

    # Team leads see only their own team's positions and shifts. Only Admin and
    # the full Megaphone permission reach every team: the two on-playa
    # permissions are narrow ones, and the emergency broadcast they exist for
    # picks its own audience without a position or a shift.
    def team_only?
      !Current.has_role?(GENERAL_ROLES)
    end

    # =======================================================================
    # What a broadcast form needs to offer
    # =======================================================================

    def attributes_for(type)
      ATTRIBUTES[type]
    end

    # The alert types this kind of broadcast may be sent under. A short
    # broadcast always uses one particular alert and so offers no choice.
    def alerts_for(type)
      attrs = ATTRIBUTES[type]
      return [] if attrs.nil? || attrs[:alert_id]

      scope = attrs[:alerts] ? Alert.where(id: attrs[:alerts]) : Alert.all
      # The emergency alert reaches people past every choice they have made, so
      # it is only ever the emergency broadcast's own alert -- never something
      # another kind of broadcast can be sent under.
      scope.where.not(id: NON_BROADCAST_ALERTS + [Alert::EMERGENCY_BROADCAST])
           .order(on_playa: :desc, title: :asc).to_a
    end

    # The alert a broadcast is sent under: fixed for the short broadcasts,
    # chosen by the sender otherwise.
    def alert_id_for(type, chosen_alert_id)
      ATTRIBUTES[type]&.dig(:alert_id) || chosen_alert_id
    end

    # Active positions grouped by team, for the position pickers.
    def position_groups(team_only: team_only?)
      PositionGroups.by_team(Position.retrieve_all_active(ctm_only: team_only))
    end

    # Positions whose shift is running now or starts within a few hours -- the
    # ones a shift muster is usually about.
    def in_progress_positions(team_only: team_only?)
      Position.find_all_with_in_progress_slots(ctm_only: team_only).to_a
    end

    # The positions that have shifts with sign-ups this year, for the first
    # step of picking a shift.
    def slot_positions(year: Current.year, team_only: team_only?)
      slots_with_signups(year:, team_only:)
        .map { |slot| [slot.position_id, slot.position_title] }
        .uniq
        .sort_by { |_id, title| title.to_s.downcase }
    end

    # The shifts of one position that have sign-ups, earliest first.
    def slots_for_position(position_id, year: Current.year, team_only: team_only?)
      slots_with_signups(year:, team_only:).select { |slot| slot.position_id == position_id.to_i }
    end

    # The position a shift belongs to, for checking whether the sender may reach
    # the people signed up for it.
    def position_id_for_slot(slot_id)
      Slot.where(id: slot_id).pick(:position_id)
    end

    # One shift, described the way the pickers describe it.
    def slot_choice(slot_id)
      slot = Slot.includes(:position).find_by(id: slot_id)
      return nil if slot.nil?

      build_slot_choice(slot, PersonSlot.where(slot_id: slot.id).count)
    end

    # Roughly how many people a short broadcast would reach right now. Shown so
    # a sender knows the size of what they are about to do. It leaves out the
    # people no channel reaches, whom an emergency still lists (unreachable).
    def receiver_estimate(type)
      return nil unless [Broadcast::TYPE_ONSHIFT, Broadcast::TYPE_EMERGENCY,
                         Broadcast::TYPE_RECRUIT_DIRT].include?(type)

      # None of the three sends a Clubhouse message.
      people = retrieve_recipients(type, {})
      people.size - unreachable(people, send_clubhouse: false).size
    end

    # =======================================================================
    # Who a broadcast reaches
    # =======================================================================

    #
    # The people a broadcast would reach, in callsign order.
    #
    # @param broadcast_type [String] one of the Broadcast::TYPE_* values
    # @param params [Hash] what the sender chose
    # @return [Array<Recipient>]
    #
    def retrieve_recipients(broadcast_type, params)
      attrs = ATTRIBUTES[broadcast_type]
      raise ArgumentError, "Unknown broadcast type" if attrs.nil?

      year = Current.year
      alert = Alert.find(alert_id_for(broadcast_type, params[:alert_id]))
      is_emergency = broadcast_type == Broadcast::TYPE_EMERGENCY

      scope = base_scope(broadcast_type, params, year)
      send_sms, send_email, send_clubhouse = channels_for(attrs, params)

      # Everyone matched receives a Clubhouse message, so no one is narrowed
      # out. An emergency overrides the choice not to be contacted, and keeps
      # everyone listed, anyone no channel reaches included, so its pages can
      # name them (unreachable).
      unless send_clubhouse || is_emergency
        scope = only_reachable(scope, send_sms:, send_email:)
      end

      scope = with_statuses(scope, broadcast_type, attrs, params)
      scope = add_alert_preference(scope, alert.id)
      scope = only_attending(scope, year) if flag?(params[:attending])
      scope = with_training(scope, params[:training], year)

      rows = scope.distinct.order(Arel.sql("person.callsign")).pluck(*recipient_selects)
      # Asked once for everyone, with each address as it is stored.
      suppressed = EmailSuppression.suppressed(rows.map { |row| row[RECIPIENT_EMAIL] })
      people = rows.map { |row| build_recipient(row, send_sms:, send_email:, is_emergency:, suppressed:) }

      unless send_clubhouse || is_emergency
        people = people.select { |person| person.use_sms || person.use_email }
      end

      people
    end

    #
    # The people on a broadcast's list whom no channel reaches, in list order.
    # Only an emergency lists any: every other broadcast drops them
    # (retrieve_recipients), and a Clubhouse message reaches everyone listed.
    # The pages name them, and leave them out of every count of who the
    # broadcast reaches; a count of the list keeps them.
    #
    # send_clubhouse: has no default: a Clubhouse-only broadcast lists everyone
    # with neither channel, and reaches them all.
    #
    # @param people [Array<Recipient>] the list, as retrieve_recipients or a send gives it
    # @param send_clubhouse [Boolean] whether the broadcast sends a Clubhouse message
    # @return [Array<Recipient>]
    #
    def unreachable(people, send_clubhouse:)
      return [] if send_clubhouse

      people.reject { |person| person.use_sms || person.use_email }
    end

    # =======================================================================
    # Sending
    # =======================================================================

    #
    # Send a broadcast and record what happened.
    #
    # Texts, emails and Clubhouse messages are each queued for a job, and the
    # results page reports how many of each.
    #
    # @param type [String] one of the Broadcast::TYPE_* values
    # @param sender [Person] who is sending
    # @param criteria [Hash] who to reach
    # @param message [Hash] :sms_message, :subject, :message, :expires_at
    # @param people [Array<Recipient>] the recipients, worked out again if not given
    # @return [TransmitResult]
    #
    def transmit(type:, sender:, criteria:, message:, people: nil)
      attrs = ATTRIBUTES[type]
      raise ArgumentError, "Unknown broadcast type" if attrs.nil?

      alert = Alert.find(alert_id_for(type, criteria[:alert_id]))
      people ||= retrieve_recipients(type, criteria)
      send_sms, send_email, send_clubhouse = channels_for(attrs, criteria)

      # A short broadcast uses its one message as the email subject as well.
      subject = attrs[:is_simple] ? message[:sms_message] : message[:subject]
      expires_at = message[:expires_at]

      broadcast = Broadcast.create!(
        sender_id: sender.id,
        alert_id: alert.id,
        sms_message: message[:sms_message].to_s,
        email_message: message[:message].to_s,
        subject: subject.to_s,
        sender_address: EmailAddresses::DO_NOT_REPLY.to_s,
        recipient_count: people.size,
        sent_sms: send_sms,
        sent_email: send_email,
        sent_clubhouse: send_clubhouse,
        expires_at:
      )

      texts_queued = send_sms ? queue_sms(broadcast.id, people) : 0

      emails_queued = 0
      if send_email
        emails_queued = people.count(&:use_email)
        RbsTransmitEmailJob.perform_later(broadcast.id, alert.id, sender.id,
                                          mail_targets(people), subject.to_s,
                                          message[:message].to_s, expires_at&.to_s, email_mode.to_s)
      end

      clubhouse_messages = 0
      if send_clubhouse
        clubhouse_messages = people.size
        RbsTransmitClubhouseMessageJob.perform_later(broadcast.id, sender.id, people.map(&:id),
                                                     subject.to_s, message[:message].to_s,
                                                     expires_at&.to_s)
      end

      TransmitResult.new(broadcast:, people:, texts_queued:, emails_queued:,
                         clubhouse_messages:, sent_sms: send_sms, sent_email: send_email,
                         sent_clubhouse: send_clubhouse)
    end

    #
    # Send the messages of a broadcast that failed the first time, and only
    # those that can still go (Broadcast#failed_messages). Everyone who already
    # received it is left alone.
    #
    # @param broadcast [Broadcast]
    # @param retry_person_id [Integer] who asked for the retry
    # @return [TransmitResult]
    #
    def retry_broadcast(broadcast, retry_person_id)
      sms, emails = broadcast.failed_messages.includes(:person).partition { |message| message.address_type == "sms" }

      queue_retried_sms(broadcast.id, sms)

      # The emails go to a queue, as they do on a send: doing hundreds of them
      # while the page waits would time the request out part-way through, and
      # the next click would send again to everyone the first attempt reached.
      RbsRetryEmailJob.perform_later(broadcast.id, emails.map(&:id), email_mode.to_s) if emails.any?

      broadcast.update!(
        sms_failed: BroadcastMessage.count_fail(broadcast.id, "sms"),
        # Recounted from the rows, never cleared to 0. The Retry button reads
        # the rows too, and a second click queues a run that waits for this one
        # (the shared rbs-email lock) and finds those rows already sent.
        email_failed: BroadcastMessage.count_fail(broadcast.id, "email"),
        retry_at: Current.time,
        retry_person_id:
      )

      retry_result(broadcast, sms, emails)
    end

    #
    # Sends the emails of a broadcast that failed the first time, away from the
    # page that asked for it, through the same batches a send uses, and
    # recounts what is still outstanding.
    #
    # Live, each goes to the address it was meant for the first time. While
    # testing it goes to the test address instead, whatever the row says.
    #
    # Yields after each batch is written down: the one place a job may stop.
    #
    def deliver_retried_emails(broadcast_id, message_ids, queued = nil)
      broadcast = Broadcast.find_by(id: broadcast_id)
      return if broadcast.nil?

      alert = Alert.find_by(id: broadcast.alert_id)
      return if alert.nil?

      run = EmailRun.new(broadcast_id: broadcast.id, alert:, subject: broadcast.subject.to_s,
                         message: broadcast.email_message.to_s, expires_at: broadcast.expires_at, queued:)
      message_ids.each_slice(ses_batch_size) do |batch_ids|
        # Read again just before the batch goes, so a row another run has
        # already sent since is left alone, and so is the row of someone who
        # can no longer be messaged since the click: it keeps its failure.
        messages = broadcast.failed_messages.where(id: batch_ids).includes(:person).to_a
        next if messages.empty?

        outcomes = deliver_email_batch(run, messages.map { |message| [message.person, message.address] })
        write_down(run, outcomes) { record_retried_batch(broadcast, run, messages, outcomes) }
        yield if block_given?
      end
    rescue StandardError
      # Stopped by an error part-way. A call SES may have taken must never be
      # sent again, so its rows stop being retryable; the rest stay as they were.
      mark_unconfirmed(broadcast_id, run&.in_flight)
      raise
    ensure
      wind_up(run, broadcast_id, stopped_by: $!)
    end

    #
    # Queue a broadcast's texts: a queued row for each person who may be
    # texted, which RbsTransmitSmsJob sends.
    #
    # @return [Integer] how many texts were queued
    #
    def queue_sms(broadcast_id, people)
      recipients = people.select(&:use_sms)
      return 0 if recipients.empty?

      BroadcastMessage.record_outbound(broadcast_id, "sms", recipients.map do |person|
        { person_id: person.id, address: person.sms_number, status: Broadcast::STATUS_QUEUED, message_id: nil }
      end)
      RbsTransmitSmsJob.perform_later(broadcast_id, sms_held?)
      recipients.size
    end

    #
    # Send a broadcast's queued texts through Twilio, SMS_THREADS at a time,
    # each on a thread with a client of its own. A round's rows are marked
    # send-unconfirmed before its texts go and settled from Twilio's answers
    # after, so a run stopped part-way never sends anyone twice. A deploy stops
    # it between rounds, leaving the rest queued for the job to pick up again;
    # an error leaves them failed, for a Retry.
    #
    # Held -- recorded as sent and sent to no one, as the sandbox has always
    # held texts -- while the sandbox was on when Send or Retry was pressed, or
    # is on now: it is asked before every round, so turning it on holds what is
    # left of a broadcast already under way.
    #
    # Yields after each round is written down: the one place a job may stop.
    #
    def deliver_queued_sms(broadcast_id, held)
      broadcast = Broadcast.find_by(id: broadcast_id)
      return if broadcast.nil?

      queued = BroadcastMessage.where(broadcast_id:, address_type: "sms", status: Broadcast::STATUS_QUEUED)
      body = sms_body(broadcast.sms_message)
      senders = nil
      while (round = queued.order(:id).limit(SMS_THREADS).to_a).any?
        if held || sms_held?
          queued.update_all(status: Broadcast::STATUS_SENT)
          break
        end

        senders ||= sms_senders(broadcast_id, queued)
        break if senders.nil?

        send_sms_round(broadcast_id, senders, round, body)
        recount_sms_failed(broadcast_id)
        yield if block_given?
      end
    rescue StandardError
      fail_queued_sms(broadcast_id)
      raise
    ensure
      wind_up_sms(broadcast_id, stopped_by: $!)
    end

    #
    # Email a list of people through SES, many to a call, and record the
    # outcome against each one.
    #
    # The email is the same for everyone but the To line, so it is drawn once,
    # and only when a batch is actually going out: a held broadcast needs no
    # template and no SES account at all.
    #
    # Yields after each batch is written down: the one place a job may stop.
    #
    # @param targets [Array<Array>] person id and whether email may be used
    #
    def broadcast_email(alert, broadcast_id, sender_id, targets, subject, message, expires_at, queued = nil)
      wants_email = targets.to_h
      # A run picked up again -- after a deploy stopped it, or a worker gave it
      # back -- leaves alone everyone it already wrote down.
      done = BroadcastMessage.person_ids_for(broadcast_id, "email")
      emailable, unwanted = people_by_id(targets.map(&:first) - done).partition { |person| wants_email[person.id] }

      # Whether each person may be emailed was settled when the recipients were
      # worked out, emergency and all, so it is not asked again here. Only why
      # not is read now, from the address the person has: suppressed when
      # EmailSuppression holds it, no-contact for any other reason. Recorded
      # as an empty address rather than a missing one: the column will not hold
      # nothing, and a person with no address on file still belongs in the
      # record of who this broadcast considered.
      suppressed = EmailSuppression.suppressed(unwanted.map(&:email))
      skipped = unwanted.map do |person|
        status = suppressed.include?(person.email) ? EMAIL_STATUS_SUPPRESSED : EMAIL_STATUS_NO_CONTACT
        [person, person.email.to_s, status, nil]
      end
      record_email_batch(broadcast_id, sender_id, nil, skipped)

      run = EmailRun.new(broadcast_id:, alert:, subject:, message:, expires_at:, queued:)
      emailable.each_slice(ses_batch_size) do |batch|
        outcomes = deliver_email_batch(run, batch.map { |person| [person, person.email.to_s] })
        write_down(run, outcomes) { record_email_batch(broadcast_id, sender_id, run.mail&.from&.first, outcomes) }
        yield if block_given?
      end
    rescue StandardError
      # Stopped by an error part-way: no one is left without a row, or the page
      # would read "Delivered" with them unsent and no Retry could reach them.
      record_stopped(broadcast_id, sender_id, emailable, queued, run&.in_flight) if emailable
      raise
    ensure
      wind_up(run, broadcast_id, stopped_by: $!)
    end

    #
    # Whether broadcast email may leave the building right now, and where to.
    # Every batch asks before it goes, so turning the sandbox on stops what is
    # left of a broadcast already under way.
    #
    # :held - recorded as sent and delivered to no one: the sandbox, the
    #   training server, and anywhere sending to Rangers is not switched on
    #   and no test address is set
    # :test - delivered through SES to the test address, never to a Ranger,
    #   in any environment
    # :misconfigured - a test address is set but cannot be used, so nothing
    #   goes anywhere
    # :live - delivered to each Ranger's own address
    #
    # Pass the test address pattern when it has been read already, so one
    # batch goes by one reading of it.
    #
    def email_mode(pattern = nil)
      return :held if Setting.fresh_value(Setting::BROADCAST_MAIL_SANDBOX) || Current.is_ghd_server?

      pattern ||= test_address_pattern
      return (test_address(pattern, 1) ? :test : :misconfigured) if pattern.present?

      # A config.x setting nobody set reads as an empty set of options, which
      # counts as true. Only a real true sends to Rangers.
      (Rails.configuration.x.rbs_email_rangers == true) ? :live : :held
    end

    #
    # The mode a queued job may send in: never less safe than the one it was
    # queued in. A broadcast queued for the test inbox does not reach Rangers
    # because the test address was cleared while it waited. Either one held is
    # held, so turning the sandbox on while a job waits, or part-way through,
    # holds the rest; a test address set now is always used. Any other change
    # sends nothing (:misconfigured). A job queued before the mode was recorded
    # goes by the mode as it is now.
    #
    # @param queued [String, nil] the mode when Send or Retry was pressed
    #
    def effective_email_mode(queued, now)
      queued = queued.presence&.to_sym
      return now if queued.nil? || queued == now
      return :held if [now, queued].include?(:held)

      (now == :test) ? :test : :misconfigured
    end

    # The test address as the setting holds it: a pattern with a ? where each
    # Ranger's id goes, or blank when broadcast email is not being tested.
    # Read past the cache, like the sandbox: a send must see the latest save.
    def test_address_pattern
      Setting.fresh_value(Setting::BROADCAST_MAIL_TEST_ADDRESS).to_s.strip
    end

    #
    # Where one person's email goes while broadcast email is being tested: the
    # test address with their id in place of its ?. Nothing when the pattern is
    # not one address with exactly one ? before the @, does not make an address
    # SES would take, or would make one too long to record for the largest id.
    #
    # @example
    #   Rbs.test_address("test+?@example.com", 2) #=> "test+2@example.com"
    #
    def test_address(pattern, person_id)
      pattern = pattern.to_s.strip
      local, domain = pattern.split("@", 2)
      return nil unless domain && local.count("?") == 1 && !domain.include?("?")
      # The address columns hold 255, and the part before the @ may be 64.
      return nil if local.length + TEST_ADDRESS_ID_ROOM > 64 || pattern.length + TEST_ADDRESS_ID_ROOM > 254

      address = "#{local.sub("?", person_id.to_s)}@#{domain}"
      address if sendable_address?(address)
    end

    #
    # Put a Clubhouse message in each person's inbox, and record it.
    #
    def broadcast_message(broadcast_id, sender_id, person_ids, from, subject, message, expires_at)
      sandboxed = Setting.get_value(Setting::BROADCAST_CLUBHOUSE_SANDBOX)

      people_by_id(person_ids).each do |person|
        unless sandboxed
          PersonMessage.new(
            person_id: person.id,
            message_from: from,
            sender_type: PersonMessage::SENDER_TYPE_RBS,
            creator_person_id: sender_id,
            subject:,
            body: message,
            expires_at:,
            broadcast_id:
          ).save(validate: false)
        end

        BroadcastMessage.record(broadcast_id, Broadcast::STATUS_SENT, person.id, "clubhouse",
                                person.callsign, "outbound")
      end
    end

    # =======================================================================
    # Event dates
    # =======================================================================

    # The event runs from two weeks before Labor Day to five days after it.
    def event_dates
      labor_day = Date.new(Current.year, 9, 1)
      labor_day += 1 until labor_day.monday?

      [labor_day - 14.days, labor_day + 5.days]
    end

    # Is the event running today?
    def during_event?
      start_date, end_date = event_dates

      Current.today.between?(start_date, end_date)
    end

    # =======================================================================
    # New Clubhouse message alerts
    # =======================================================================

    #
    # Tell a Ranger they have a new Clubhouse message, by text and email.
    #
    # @param person [Person] who to tell
    # @param sender_id [Integer] who is sending
    # @param from [String] the callsign shown as the sender, or a team's title
    # @param subject [String] the message subject
    # @param message [String] the message body
    # @param group [Boolean] a group message, one conversation everyone in it sees
    # @param anonymous [Boolean] written as a team: the email's mail log row
    #   names no sender (Person › Mail Log is open to VCs, who may not be on
    #   the team); the broadcast row keeps sender_id, which it requires, on
    #   pages only Admin and Tech Ninja open
    #
    def message_notify(person, sender_id, from, subject, message, group: false, anonymous: false)
      return unless Setting.get_value(Setting::BROADCAST_CLUBHOUSE_NOTIFY)
      return if Person::NO_MESSAGES_STATUSES.include?(person.status)

      alert_id = during_event? ? Alert::CLUBHOUSE_NOTIFY_ON_PLAYA : Alert::CLUBHOUSE_NOTIFY_PRE_EVENT
      alert = PersonAlert.find_alert_for_person(alert_id, person.id)

      phone_number = person.sms_number
      send_sms = (alert.nil? || alert.use_sms) &&
                 phone_number.present? && person.sms_verified && !person.sms_stopped
      send_email = alert.nil? || alert.use_email

      return unless send_email || send_sms

      log_ids = []
      sms_failed = 0
      email_failed = 0
      sms_message = ""

      if send_sms
        sms_message = notify_text(from, subject, group:)
        # Written before the text goes, so Twilio's receipt can find it, and
        # send-unconfirmed until Twilio answers.
        row_id = BroadcastMessage.record(nil, Broadcast::STATUS_SEND_UNCONFIRMED, person.id, "sms", phone_number,
                                         "outbound", sms_message)
        status, sid = notify_by_text(phone_number, sms_message, row_id)
        BroadcastMessage.where(id: row_id).update_all(status:, message_id: sid)
        sms_failed = 1 if status != Broadcast::STATUS_SENT
        log_ids << row_id
      end

      if send_email
        # SuppressedRecipientsInterceptor would drop the email at delivery
        # under a row that says sent, so the record is asked here and the row
        # records the skip, as broadcast_email's skip rows do. Asked before
        # the sandbox, so the row reads the same in every mode. The
        # interceptor stays the backstop for an address suppressed after the
        # alert is queued.
        suppressed = EmailSuppression.suppressed?(person.email)
        # Addressed as a broadcast's email is: to the test address while one
        # is set, and to no one when it can't be used. A skip row keeps the
        # Ranger's own address, as broadcast_email's do.
        pattern = test_address_pattern
        mode = email_mode(pattern)
        address = suppressed ? person.email : destination(mode, pattern, person, person.email)
        unless suppressed || mode == :misconfigured || Setting.get_value(Setting::BROADCAST_MAIL_SANDBOX)
          ClubhouseNewMessageMailer.with(sender_id: (sender_id unless anonymous), group:)
                                   .notify(person:, to: address, from:, subject:, message:)
                                   .deliver_later
        end
        status = if suppressed then EMAIL_STATUS_SUPPRESSED
                 elsif mode == :misconfigured then Broadcast::STATUS_SERVICE_FAIL
                 else Broadcast::STATUS_SENT
                 end
        email_failed = 1 if status == Broadcast::STATUS_SERVICE_FAIL
        log_ids << BroadcastMessage.record(nil, status, person.id, "email", address, "outbound", message)
      else
        subject = message = ""
      end

      broadcast = Broadcast.create!(
        sender_id:,
        alert_id:,
        sms_message:,
        sender_address: EmailAddresses::DO_NOT_REPLY.to_s,
        email_message: message,
        subject:,
        recipient_count: 1,
        sms_failed:,
        email_failed:,
        sent_sms: send_sms,
        sent_email: send_email,
        sent_clubhouse: false
      )

      BroadcastMessage.where(id: log_ids).update_all(broadcast_id: broadcast.id)
    end

    private

    # -----------------------------------------------------------------------
    # Building the recipient query
    # -----------------------------------------------------------------------

    # Where each kind of broadcast starts looking for people.
    def base_scope(broadcast_type, params, year)
      case broadcast_type
      when Broadcast::TYPE_EMERGENCY, Broadcast::TYPE_RECRUIT_DIRT
        # Anyone who might be on playa and is not already on a shift.
        not_on_duty(on_site(Person.all), year)

      when Broadcast::TYPE_ONSHIFT
        Person.joins("INNER JOIN timesheet ON person.id = timesheet.person_id")
              .where_year("timesheet.on_duty", year)
              .where("timesheet.off_duty IS NULL")
              .where(sms_verified: true, sms_stopped: false)
              .where("IFNULL(person_alert.use_sms, TRUE) IS TRUE")

      when Broadcast::TYPE_GENERAL
        flag?(params[:on_site]) ? on_site(Person.all) : Person.all

      when Broadcast::TYPE_SLOT_EDIT
        person_ids = params[:person_ids]
        raise ArgumentError, "Person ids cannot be missing or empty" if person_ids.blank?

        Person.where(id: person_ids)

      when Broadcast::TYPE_POSITION, Broadcast::TYPE_RECRUIT_POSITION
        position_scope(broadcast_type, params, year)

      when Broadcast::TYPE_SLOT
        Person.joins("INNER JOIN person_slot ON person.id = person_slot.person_id")
              .where("person_slot.slot_id = ?", params[:slot_id])

      else
        raise ArgumentError, "Unknown broadcast type [#{broadcast_type}]"
      end
    end

    def position_scope(broadcast_type, params, year)
      is_muster = broadcast_type == Broadcast::TYPE_RECRUIT_POSITION
      position_ids = Array(params[:position_ids])

      scope = Person.joins("INNER JOIN person_position ON person.id = person_position.person_id")
                    .where("person_position.position_id IN (?)", position_ids)

      scope = on_site(scope) if flag?(params[:on_site]) || is_muster

      # A shift muster asks for people who could come in, so anyone already on
      # a shift is left out.
      return not_on_duty(scope, year) if is_muster

      signed_up = params[:position_signed_up].presence || SIGNED_UP_ANY
      return scope if signed_up == SIGNED_UP_ANY

      condition = "EXISTS (SELECT 1 FROM slot INNER JOIN person_slot ON person_slot.slot_id = slot.id" \
                  " WHERE slot.begins_year = ? AND slot.position_id IN (?)" \
                  " AND person_slot.person_id = person.id LIMIT 1)"

      if signed_up == SIGNED_UP_NO
        scope.where.not(condition, year, position_ids)
      else
        scope.where(condition, year, position_ids)
      end
    end

    # Someone is taken to be on site if they are signed up for anything during
    # the event, or have said they are here.
    def on_site(scope)
      start_date, end_date = event_dates

      scope.where(
        "EXISTS (SELECT 1 FROM slot INNER JOIN person_slot ON person_slot.slot_id = slot.id" \
        " WHERE slot.begins >= ? AND slot.ends <= ? AND person_slot.person_id = person.id LIMIT 1)" \
        " OR person.on_site = TRUE",
        start_date, end_date + 1.day
      )
    end

    # Leave out anyone who is on a shift right now.
    def not_on_duty(scope, year)
      scope.where(
        "NOT EXISTS (SELECT 1 FROM timesheet WHERE timesheet.person_id = person.id" \
        " AND timesheet.on_duty >= ? AND timesheet.on_duty < ? AND timesheet.off_duty IS NULL LIMIT 1)",
        Time.local(year), Time.local(year + 1)
      )
    end

    # Each person's choice about being contacted for this alert. Nothing on
    # record means they are happy to hear from us.
    def add_alert_preference(scope, alert_id)
      scope.joins(
        ActiveRecord::Base.sanitize_sql_array([
                                                "LEFT JOIN person_alert ON person_alert.person_id = person.id" \
                                                " AND person_alert.alert_id = ?", alert_id
                                              ])
      )
    end

    # Only people the chosen channels can actually reach.
    def only_reachable(scope, send_sms:, send_email:)
      conditions = []
      if send_sms
        conditions << "IFNULL(person_alert.use_sms, TRUE) IS TRUE AND person.sms_number != ''" \
                      " AND person.sms_verified IS TRUE AND person.sms_stopped IS FALSE"
      end
      conditions << "IFNULL(person_alert.use_email, TRUE) IS TRUE" if send_email

      return scope if conditions.empty?

      scope.where("(#{conditions.join(" OR ")})")
    end

    # Which account statuses to reach. Some statuses are never messaged at all.
    def with_statuses(scope, broadcast_type, attrs, params)
      unless [Broadcast::TYPE_SLOT, Broadcast::TYPE_SLOT_EDIT].include?(broadcast_type)
        statuses = (attrs[:has_status] && params[:statuses].present?) ? params[:statuses] : Person::ACTIVE
        scope = scope.where(status: statuses)
      end

      scope.where.not(status: Person::NO_MESSAGES_STATUSES)
    end

    # People who are signed up for something this year.
    def only_attending(scope, year)
      scope.joins("INNER JOIN person_slot AS attending_signup ON attending_signup.person_id = person.id")
           .joins("INNER JOIN slot AS attending_slot ON attending_slot.id = attending_signup.slot_id" \
                  " AND attending_slot.begins_year = #{year.to_i}")
    end

    # Narrow by this year's in-person training. Registered means any trainee
    # status row for one of the year's sessions, whatever it says.
    def with_training(scope, training, year)
      return scope unless [TRAINING_PASSED, TRAINING_REGISTERED, TRAINING_NONE].include?(training)

      sessions = TraineeStatus.joins(:slot)
                              .where(slot: { position_id: Position::TRAINING, begins_year: year })
                              .where("trainee_status.person_id = person.id")
      sessions = sessions.passed if training == TRAINING_PASSED

      (training == TRAINING_NONE) ? scope.where.not(sessions.arel.exists) : scope.where(sessions.arel.exists)
    end

    def recipient_selects
      RECIPIENT_COLUMNS.map { |column| Arel.sql(column) } +
        [Arel.sql("IFNULL(person_alert.use_sms, TRUE)"), Arel.sql("IFNULL(person_alert.use_email, TRUE)")]
    end

    # MariaDB hands back 1 and 0 for booleans here, and 0 is true in Ruby, so
    # every one of them is cast before it is used.
    #
    # @param suppressed [Set<String>] the addresses EmailSuppression holds
    def build_recipient(row, send_sms:, send_email:, is_emergency:, suppressed:)
      id, callsign, status, first_name, preferred_name, last_name, email, sms_number,
        sms_verified, sms_stopped, wants_sms, wants_email = row

      sms_status = text_block_reason(sms_number, flag?(sms_verified), flag?(sms_stopped),
                                     flag?(wants_sms), is_emergency)
      use_sms = send_sms && sms_status.nil?

      email_status = email_block_reason(email, suppressed.include?(email), flag?(wants_email), is_emergency)
      use_email = send_email && email_status.nil?

      Recipient.new(id:, callsign:, status:, first_name:, preferred_name:, last_name:, email:,
                    sms_number:, use_sms:, use_email:, sms_status:, email_status:)
    end

    # Why a text cannot reach this person, or nothing if one can. An emergency
    # overrides the choice not to be texted, but not a missing or stopped number.
    def text_block_reason(sms_number, verified, stopped, wants_sms, is_emergency)
      return SMS_STATUS_NO_PHONE if sms_number.blank?
      return SMS_STATUS_STOPPED if stopped
      return SMS_STATUS_UNVERIFIED unless verified
      return SMS_STATUS_NO_CONTACT if !wants_sms && !is_emergency

      nil
    end

    # Why an email cannot reach this person, or nothing if one can. An emergency
    # overrides the choice not to be emailed, but not a missing address, nor
    # one that bounced for good or reported spam.
    def email_block_reason(email, suppressed, wants_email, is_emergency)
      return EMAIL_STATUS_NO_ADDRESS if email.blank?
      return EMAIL_STATUS_SUPPRESSED if suppressed
      return EMAIL_STATUS_NO_CONTACT if !wants_email && !is_emergency

      nil
    end

    def flag?(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    # Which channels this broadcast uses. The short broadcasts always text, and
    # email as well unless they are text-only.
    def channels_for(attrs, params)
      return [true, !attrs[:sms_only], false] if attrs[:is_simple]

      [flag?(params[:send_sms]), flag?(params[:send_email]), flag?(params[:send_clubhouse])]
    end

    # The year's shifts that someone has actually signed up for, earliest first.
    #
    # The sign-ups are counted from the sign-up rows rather than read from the
    # running total a shift keeps: a total that has drifted low would hide a
    # shift from the picker altogether, and there would be no way to reach the
    # people on it.
    #
    # Deliberately not held on to between calls: which shifts these are depends
    # on who is asking, and a list kept past the end of a request would be
    # handed to the next person to ask.
    def slots_with_signups(year:, team_only:)
      scope = Slot.includes(:position).where(begins_year: year, active: true).order(:begins)

      if team_only
        team_ids = TeamManager.retrieve_team_ids_for_person(Current.person_id)
        return [] if team_ids.empty?

        scope = scope.joins(:position).where(position: { team_id: team_ids })
      end

      slots = scope.to_a
      counts = PersonSlot.where(slot_id: slots.map(&:id)).group(:slot_id).count

      slots.filter_map do |slot|
        signed_up = counts[slot.id].to_i
        build_slot_choice(slot, signed_up) if signed_up.positive?
      end
    end

    def build_slot_choice(slot, signed_up)
      SlotChoice.new(id: slot.id, position_id: slot.position_id,
                     position_title: slot.position&.title, begins: slot.begins,
                     description: slot.description, signed_up:)
    end

    # -----------------------------------------------------------------------
    # Delivery
    # -----------------------------------------------------------------------

    # Every text carries the same wrapper, whether it is the first attempt or a
    # later one.
    def sms_body(message)
      "#{SMS_PREFIX}#{message}#{SMS_SUFFIX}"
    end

    # Whether the text sandbox holds broadcast texts. Read past the cache, like
    # the email sandbox: a send must see the latest save.
    def sms_held? = Setting.fresh_value(Setting::BROADCAST_SMS_SANDBOX)

    # The Messaging Service, and a client for each thread, asked for once a
    # run. Settings no text can be sent with would fail every text the same
    # way, so the queued texts all fail, logged once, and Twilio is not asked.
    def sms_senders(broadcast_id, queued)
      service_id, account_sid, auth_token = SmsService.text_settings
      [service_id, Array.new(SMS_THREADS) { TwilioAccount.build_client(account_sid, auth_token) }]
    rescue StandardError => e
      note("sms-exception", { type: "broadcast", broadcast_id:, texts: queued.count }, exception: e)
      queued.update_all(status: Broadcast::STATUS_SERVICE_FAIL)
      nil
    end

    # One round: its rows marked send-unconfirmed, a thread and a client for
    # each text, then each row settled from what Twilio said -- its SID, or why
    # it did not go. The threads only ask Twilio; the rows are written here.
    def send_sms_round(broadcast_id, senders, round, body)
      service_id, clients = senders
      BroadcastMessage.where(id: round.map(&:id)).update_all(status: Broadcast::STATUS_SEND_UNCONFIRMED)
      outcomes = round.zip(clients).map do |row, client|
        Thread.new { text_outcome(client, service_id, row, body) }
      end.map(&:value)

      BroadcastMessage.transaction do
        round.zip(outcomes).each { |row, (status, sid)| row.update_columns(status:, message_id: sid) }
      end
      round.zip(outcomes).each do |row, (_status, _sid, error)|
        note("sms-exception", { type: "broadcast", broadcast_id:, phone: row.address }, exception: error) if error
      end
    end

    # What became of one row's text: sent, with its SID, Twilio's receipt to
    # follow; maybe sent, when Twilio may have taken it without answering; or
    # not sent, and why.
    def text_outcome(client, service_id, row, body)
      [Broadcast::STATUS_SENT, SmsService.text_through(client, service_id, row.address, body, receipt_for: row.id), nil]
    rescue SmsException::Unconfirmed => e
      [Broadcast::STATUS_SEND_UNCONFIRMED, nil, e]
    rescue StandardError => e
      [Broadcast::STATUS_SERVICE_FAIL, nil, e]
    end

    # A run stopped by an error part-way: the texts not yet tried become
    # failures a Retry can send. The round in flight stays send-unconfirmed.
    def fail_queued_sms(broadcast_id)
      BroadcastMessage.where(broadcast_id:, address_type: "sms", status: Broadcast::STATUS_QUEUED)
                      .update_all(status: Broadcast::STATUS_SERVICE_FAIL)
    rescue StandardError
      nil # what stopped the run is the error that goes on
    end

    def recount_sms_failed(broadcast_id) = Broadcast.recount_failed_texts(broadcast_id)

    # Recounted however a run ends. Should that fail too, whatever stopped the
    # run -- an error, or a deploy's stop the job must resume from -- is what
    # goes on, never this.
    def wind_up_sms(broadcast_id, stopped_by:)
      recount_sms_failed(broadcast_id)
    rescue StandardError
      raise unless stopped_by
    end

    # The name a Ranger sees on the "to" line. Works for a recipient worked out
    # for a send and for a person read back out of the records.
    def mail_name(person)
      first_name = person.preferred_name.presence || person.first_name

      "#{person.callsign} (#{first_name} #{person.last_name})"
    end

    # The broadcast as one finished email, drawn by the mailer so the wording
    # kept in the Clubhouse and the house layout both apply.
    def render_broadcast(alert, subject, message, expires_at)
      RbsMailer.broadcast(subject:, rbs_message: message, alert:, expires_at:).message
    end

    # One per job run, and never kept on the class: a client held between runs
    # outlives the settings and stand-ins it was built under.
    #
    # The SDK's own retries are off. SendBulkEmail carries no way to say "this
    # is the same call again", so a retry after a timeout SES had in fact
    # answered would email the whole batch twice. The short log line keeps
    # every address and the whole message out of the log.
    #
    # A call is bounded well inside the time a deploy waits for a job
    # (config.solid_queue.shutdown_timeout, 30 s): one cut off mid-call would be
    # let go and started over, and the batch could go twice. No connection in
    # 5 s means nothing went; no answer in 20 s is recorded send-unconfirmed.
    def ses_client
      Aws::SESV2::Client.new(retry_limit: 0, max_attempts: 1, http_open_timeout: 5, http_read_timeout: 20,
                             log_formatter: Aws::Log::Formatter.short)
    end

    # SES takes one SendBulkEmail call a second from the whole account, so each
    # call waits until a second has passed since the one before it began.
    # Returns when this call begins, for the next one to wait on.
    def pace(last_call)
      wait = last_call && (last_call + 1.0 - Process.clock_gettime(Process::CLOCK_MONOTONIC))
      sleep(wait) if wait&.positive?
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # How many people one call carries: the account's send rate, so a call a
    # second keeps under it, and never more than SES takes at once. A rate
    # cleared to blank reads as 0, which must not mean one email a second.
    def ses_batch_size
      rate = Setting.get_value(Setting::SES_MAX_SEND_RATE).to_i
      rate = Setting::DESCRIPTIONS.dig(Setting::SES_MAX_SEND_RATE, :default) unless rate.positive?

      [rate, SES_BATCH_LIMIT].min
    end

    # Everything SES is handed for a broadcast except who it goes to.
    #
    # The template holds nothing but placeholders, one for each part of the
    # finished email, and the parts themselves travel as its data, so a "{{"
    # someone typed is only ever text. A placeholder with no data behind it
    # makes SES accept the email and then quietly drop it, so both are built
    # from the same parts, and the subject is always one of them, if only as "".
    def ses_content(mail)
      parts = { subject: mail.subject.to_s, html: (mail.html_part || mail).decoded,
                text: mail.text_part&.decoded }.compact

      {
        from_email_address: mail[:from].value,
        default_content: {
          template: {
            template_content: parts.to_h { |part, _value| [part, "{{#{part}}}"] },
            template_data: JSON.generate(parts)
          }
        }
      }
    end

    #
    # What became of one batch of people. Whether email may leave the building
    # is asked here, before every batch, so nothing that sends through here can
    # get around the sandbox, the training server, the test address or the
    # switch -- nor go anywhere less safe than the mode the job was queued in.
    # The SES client is built only by a batch that sends, so a run that starts
    # held and is let go part-way builds it then. An address SES could not take
    # is never handed to it, so one bad address cannot sink everyone else in
    # the call.
    #
    # While testing, each email goes to the test address instead, and that is
    # the address recorded -- so a later Retry lands in the test inbox too. The
    # Ranger's own address on file must still be one SES would take, so a test
    # turns up the same failures a real send would. The outcomes come back in
    # the order the people were given.
    #
    # @param recipients [Array<Array>] person and the address to send to
    # @return [Array<Array>] person, address, status and SES message id
    #
    def deliver_email_batch(run, recipients)
      mode, now, pattern = email_route(run.queued)
      case mode
      when :held
        # Held back, as the sandbox has always held it: recorded as sent and
        # delivered to no one -- except where there is no address at all.
        return recipients.map { |person, address| unsent(mode, pattern, person, address) }
      when :misconfigured
        # Sent nowhere, and recorded with no address, so a Retry once testing
        # is over cannot reach the Ranger with an email meant for the test.
        run.unaddressed += recipients.size
        run.refused_in = { now: now.to_s, test_address: pattern }
        return recipients.map { |person, address| unsent(mode, pattern, person, address) }
      end

      entries = recipients.map do |person, address|
        sent_to = destination(mode, pattern, person, address)
        # to_line checks the address it is given; while testing, the Ranger's
        # own address must pass as well.
        [person, sent_to, (mode != :test || sendable_address?(person.email.to_s)) && to_line(person, sent_to)]
      end
      sendable = entries.select(&:last)
      results = sendable.empty? ? [] : send_to_ses(run, sendable)

      entries.map { |person, address, to| [person, address, *(to ? results.shift : EMAIL_INVALID)] }
    end

    # How email may go out for a run right now: the mode it may send in, the
    # mode as it is, and the test address both were read with.
    def email_route(queued)
      pattern = test_address_pattern
      now = email_mode(pattern)
      [effective_email_mode(queued, now), now, pattern]
    end

    # What becomes of one person whose email never goes to SES: held, as a held
    # batch is, or failed at the address the mode would have used.
    def unsent(mode, pattern, person, address)
      address = destination(mode, pattern, person, address)
      outcome = if mode != :held then EMAIL_FAILED
                elsif address.present? then EMAIL_HELD
                else EMAIL_INVALID
                end
      [person, address, *outcome]
    end

    # Write down what became of one batch of retried emails, on the rows they
    # came from, all of it or none of it. Only an email SES took moves its row
    # to the address it went to; one that failed again keeps the address it
    # had, so a later Retry still knows where it was meant to go.
    def record_retried_batch(broadcast, run, messages, outcomes)
      BroadcastMessage.transaction do
        messages.zip(outcomes).each do |message, (_person, address, status, message_id)|
          message.update!(status:, message_id:, address: message_id ? address : message.address)
        end
        MailLog.record_ses_sends(ses_sends(outcomes), sender_id: broadcast.sender_id,
                                                      from_email: run.mail&.from&.first, broadcast_id: broadcast.id)
      end
    end

    # What a run could not do, written down once at its end: people left unsent
    # after SES kept failing, and people kept from being sent at all -- by a
    # test address that cannot be used, or a mode less safe than the one the
    # job was queued in (`queued:` and `now:` say which).
    def log_email_run(run)
      if run.skipped.positive?
        note("rbs-email-given-up", { broadcast_id: run.broadcast_id, people_not_sent: run.skipped })
      end
      return unless run.unaddressed.positive?

      note("rbs-email-not-sent", { broadcast_id: run.broadcast_id, people_not_sent: run.unaddressed,
                                   queued: run.queued, **run.refused_in })
    end

    #
    # One SendBulkEmail call, made once a second has passed since the last.
    # Whatever stops the call gives everyone in it the same outcome: never
    # sent, SES's reason, or send-unconfirmed when it may have gone.
    #
    # An email that will not draw, or no SES client to hand it to, stops the
    # run at once: every later batch would fail the same way, so the rest is
    # recorded failed under the one log already written. Past that, only a
    # failure every later call would meet too counts against the broadcast:
    # missing keys, a paused or suspended account. After a few of those in a
    # row, the rest is recorded failed without asking SES again. A dropped connection, being asked too
    # fast or a fault at SES's end may be gone by the next call, so none of
    # those stops a broadcast, and a call that sends anyone starts the count
    # over.
    #
    # Once SES has answered, nothing here turns its answer into a failure:
    # what it took stays taken.
    #
    # @param entries [Array<Array>] person, address and To line
    # @return [Array<Array>] status and SES message id, one per entry
    #
    def send_to_ses(run, entries)
      return Array.new(entries.size, EMAIL_FAILED) if run.broken

      if run.failures >= SES_FAILURES_BEFORE_GIVING_UP
        run.skipped += entries.size
        return Array.new(entries.size, EMAIL_FAILED)
      end

      begin
        run.mail ||= render_broadcast(run.alert, run.subject, run.message, run.expires_at)
        run.content ||= ses_content(run.mail)
        run.client ||= ses_client
      rescue => e
        # Nothing has gone anywhere yet, and nothing will this run.
        run.broken = true
        return call_failed(run, entries, e, EMAIL_FAILED)
      end

      run.last_call = pace(run.last_call)
      run.in_flight = entries.map { |person, *| person.id }
      answers = begin
        run.client.send_bulk_email(
          **run.content,
          bulk_email_entries: entries.map { |_person, _address, to| { destination: { to_addresses: [to] } } }
        ).bulk_email_entry_results
      rescue => e
        return taken_by(run, entries, call_failed(run, entries, e, [call_failure_status(e), nil]))
      end

      results = email_results(entries, answers, run.broadcast_id)
      if results.any? { |status, _message_id| status == Broadcast::STATUS_SENT }
        run.failures = 0
      elsif answers.any? && answers.all? { |answer| SES_ACCOUNT_REFUSALS.include?(answer.status) }
        run.failures += 1
      end

      taken_by(run, entries, results)
    end

    # Once the call has an answer, what is in flight narrows to the people SES
    # may have taken -- those it gave an id, and any it left in doubt -- so a
    # run stopped before they are written down never marks the rest as sent.
    def taken_by(run, entries, results)
      run.in_flight = entries.zip(results).filter_map do |(person, *), (status, message_id)|
        person.id if message_id || status == Broadcast::STATUS_SEND_UNCONFIRMED
      end
      results
    end

    #
    # What SES's answer means for each person in the call, in the order given:
    # a status, and the id SES gave the email when it took it. Anyone SES did
    # not take gets SES's reason as their status, and the refusal is written
    # down. Without one answer per person there is no telling who got it, so
    # then everyone in the call is send-unconfirmed -- any of them may have
    # gone -- and every answer is kept as SES gave it.
    #
    # @param entries [Array<Array>] person, address and To line
    # @param answers [Array<Aws::SESV2::Types::BulkEmailEntryResult>]
    # @return [Array<Array>] status and SES message id, one per entry
    #
    def email_results(entries, answers, broadcast_id)
      person_ids = entries.map { |person, _address, _to| person.id }

      if answers.size != entries.size
        note("rbs-email-not-accepted", { broadcast_id:, person_ids:, answers: answers.map(&:to_h) })
        return Array.new(entries.size, EMAIL_UNCONFIRMED)
      end

      refused = person_ids.zip(answers).reject { |_person_id, answer| answer.status == "SUCCESS" }
      if refused.any?
        note("rbs-email-not-accepted", {
               broadcast_id:,
               refused: refused.map do |person_id, answer|
                 { person_id:, status: answer.status, error: answer.error }
               end
             })
      end

      answers.map do |answer|
        (answer.status == "SUCCESS") ? [Broadcast::STATUS_SENT, answer.message_id] : [ses_refusal_status(answer.status), nil]
      end
    end

    # Whether a failed call may well go through next time: a dropped or slow
    # connection, SES asked too fast, or a fault at SES's end.
    def passing_failure?(error)
      case error
      when Seahorse::Client::NetworkingError, Aws::SESV2::Errors::TooManyRequestsException,
           Aws::SESV2::Errors::LimitExceededException
        true
      when Aws::Errors::ServiceError
        ses_fault?(error)
      else
        false
      end
    end

    # A fault at SES's end: whatever it did with the call, it may have sent it.
    def ses_fault?(error)
      error.context&.http_response&.status_code.to_i >= 500
    end

    # A call that raised: written down, counted against the broadcast unless
    # the next call may well get through, and the same outcome for everyone in it.
    def call_failed(run, entries, error, outcome)
      note("rbs-email-exception", { type: "broadcast", broadcast_id: run.broadcast_id,
                                    person_ids: entries.map { |person, _address, _to| person.id } }, exception: error)
      run.failures += 1 unless passing_failure?(error)
      Array.new(entries.size, outcome)
    end

    #
    # What a call that raised means for the people in it. Where the request
    # certainly never reached SES -- no connection made, no credentials, a
    # request SES turned away as it stood -- nothing went: service-fail, or
    # SES's own reason where it gave one. Where it may have arrived -- a fault
    # at SES's end, a connection lost partway, anything else -- the email may
    # have gone, and is never taken for unsent.
    #
    def call_failure_status(error)
      case error
      when Seahorse::Client::NetworkingError
        case error.original_error
        when *NEVER_CONNECTED then Broadcast::STATUS_SERVICE_FAIL
        else Broadcast::STATUS_SEND_UNCONFIRMED
        end
      when *NEVER_CONNECTED, Aws::Errors::MissingCredentialsError, ArgumentError
        Broadcast::STATUS_SERVICE_FAIL
      when Aws::Errors::ServiceError
        if ses_fault?(error)
          Broadcast::STATUS_SEND_UNCONFIRMED
        else
          reason = SES_CALL_REFUSALS[error.class.name.demodulize]
          reason ? ses_refusal_status(reason) : Broadcast::STATUS_SERVICE_FAIL
        end
      else
        Broadcast::STATUS_SEND_UNCONFIRMED
      end
    end

    # SES's word for one person it did not take, as a status: its reason
    # lowercased with dashes, or "failed" for a reason the Clubhouse does not
    # know.
    def ses_refusal_status(answer)
      status = answer.to_s.downcase.tr("_", "-")
      Broadcast::EMAIL_FAIL_STATUSES.include?(status) ? status : Broadcast::STATUS_FAILED
    end

    #
    # The To line SES puts on one person's copy, or nothing for an address it
    # can tell SES would refuse. Written by the mail library: a callsign with
    # brackets in it stays part of the name rather than reading as a comment,
    # and a name outside plain ASCII is encoded. A line break or other control
    # character in a name is never handed on; a header cannot hold one.
    #
    def to_line(person, address)
      return nil unless sendable_address?(address)

      to = Mail::Address.new
      to.address = address
      to.display_name = mail_name(person).gsub(/[[:cntrl:]]/, " ").squish
      to.encoded
    rescue Mail::Field::ParseError
      nil
    end

    # The rule, shared with Person and the VC's application edit, is EmailAddresses.sendable?.
    def sendable_address?(address) = EmailAddresses.sendable?(address)

    # Write down what became of one batch, all of it or none of it: a message
    # row per person, and a mail log entry for each email SES took.
    #
    # @param outcomes [Array<Array>] person, address, status and SES message id
    def record_email_batch(broadcast_id, sender_id, from_email, outcomes)
      rows = outcomes.map do |person, address, status, message_id|
        { person_id: person.id, address:, status:, message_id: }
      end

      BroadcastMessage.transaction do
        BroadcastMessage.record_outbound(broadcast_id, "email", rows)
        MailLog.record_ses_sends(ses_sends(outcomes), sender_id:, from_email:, broadcast_id:)
      end
    end

    # The mail log's entry for each email SES took.
    def ses_sends(outcomes)
      outcomes.filter_map do |person, address, _status, message_id|
        { person_id: person.id, to_email: address, message_id: } if message_id
      end
    end

    #
    # Write down a batch SES has answered. Should that fail, who was in it and
    # the ids SES gave the emails it took go to the error log before the error
    # goes on: the rows are lost, and nothing may mark those people as still
    # to send.
    #
    def recording(broadcast_id, outcomes)
      yield
    rescue => e
      note("rbs-email-unrecorded", {
             broadcast_id:, error: e.message,
             person_ids: outcomes.map { |person, *| person.id },
             ses_ids: ses_sends(outcomes).to_h { |sent| [sent[:person_id], sent[:message_id]] }
           })
      raise
    end

    # Write down one batch SES has answered, and the count with it; nothing
    # of that batch is in flight any more.
    def write_down(run, outcomes, &record)
      recording(run.broadcast_id, outcomes, &record)
      run.in_flight = nil
      recount_email_failed(run.broadcast_id)
    end

    #
    # A send stopped by an error part-way. Everyone not yet written down gets a
    # row, so the page shows what did not go and a Retry can reach them: not
    # sent, where the send had not got to them; maybe sent -- never to be sent
    # again -- where SES had their call; held, while email is held. Each row
    # holds the address the mode would have used, so a test broadcast keeps
    # its test addresses.
    #
    def record_stopped(broadcast_id, sender_id, people, queued, in_flight)
      written = BroadcastMessage.person_ids_for(broadcast_id, "email").to_set
      in_flight = Array(in_flight).to_set
      mode, _now, pattern = email_route(queued)
      rows = people.reject { |person| written.include?(person.id) }.map do |person|
        if in_flight.include?(person.id)
          [person, destination(mode, pattern, person, person.email.to_s), *EMAIL_UNCONFIRMED]
        else
          # Held while email is held: never a failure a later live Retry would
          # send to the Ranger.
          unsent(mode, pattern, person, person.email.to_s)
        end
      end
      record_email_batch(broadcast_id, sender_id, nil, rows)
    rescue StandardError
      nil # what stopped the send is the error that goes on
    end

    # A retry stopped by an error part-way: the rows of a call SES may have
    # taken stop being retryable.
    def mark_unconfirmed(broadcast_id, person_ids)
      return if person_ids.blank?

      BroadcastMessage.where(broadcast_id:, address_type: "email", person_id: person_ids,
                             status: Broadcast::RETRYABLE_STATUSES)
                      .update_all(status: Broadcast::STATUS_SEND_UNCONFIRMED)
    rescue StandardError
      nil # what stopped the retry is the error that goes on
    end

    # Where one person's email goes, and is recorded as going, in this mode.
    def destination(mode, pattern, person, address)
      case mode
      when :test then test_address(pattern, person.id)
      when :misconfigured then ""
      else address
      end
    end

    # A log written once SES has answered, or while a run winds up. What it
    # says is also on the rows, so a log that cannot be written must never
    # stop the rows being written, nor hide the error that stopped a run.
    def note(error_type, data, exception: nil)
      if exception
        ErrorLog.record_exception(exception, error_type, extra: data)
      else
        ErrorLog.record(error_type, data:)
      end
    rescue StandardError
      nil
    end

    # Written down however a run ends. Should that fail too, whatever stopped
    # the run -- an error, or a deploy's stop the job must resume from -- is
    # what goes on, never this.
    def wind_up(run, broadcast_id, stopped_by:)
      log_email_run(run) if run
      recount_email_failed(broadcast_id)
    rescue StandardError
      raise unless stopped_by
    end

    # Recounted after every batch and however a run ends, so the count never
    # says fewer failed than the rows do -- not even part-way through.
    def recount_email_failed(broadcast_id)
      Broadcast.where(id: broadcast_id).update_all(email_failed: BroadcastMessage.count_fail(broadcast_id, "email"))
    end

    # Recipients as plain data a queued job can carry: who, and whether email
    # may be used for them.
    def mail_targets(people)
      people.map { |person| [person.id, person.use_email] }
    end

    def people_by_id(person_ids)
      Person.where(id: person_ids).order(:callsign)
    end

    # -----------------------------------------------------------------------
    # Retrying
    # -----------------------------------------------------------------------

    # A broadcast's failed texts, queued again for the job that sends its first
    # ones. The stored message is what the sender typed; the job adds the words
    # every text carries -- including how to stop them -- again.
    def queue_retried_sms(broadcast_id, messages)
      return if messages.empty?

      BroadcastMessage.where(id: messages.map(&:id)).update_all(status: Broadcast::STATUS_QUEUED)
      RbsTransmitSmsJob.perform_later(broadcast_id, sms_held?)
    end

    # A retry reports itself the same way a send does, so the results page can
    # be the same one. It lists only the people sent to again.
    def retry_result(broadcast, sms, emails)
      people = {}

      sms.each do |message|
        retry_person(people, message).use_sms = true
      end

      emails.each do |message|
        person = retry_person(people, message)
        person.use_email = true
      end

      TransmitResult.new(
        broadcast:,
        people: people.values.sort_by { |person| person.callsign.to_s.downcase },
        texts_queued: sms.size,
        emails_queued: emails.size,
        clubhouse_messages: 0,
        sent_sms: sms.any?,
        sent_email: emails.any?,
        sent_clubhouse: false
      )
    end

    def retry_person(people, message)
      people[message.person_id] ||= Recipient.new(
        id: message.person_id,
        callsign: message.person.callsign,
        status: message.person.status,
        use_sms: false,
        use_email: false
      )
    end

    # -----------------------------------------------------------------------
    # New message alerts
    # -----------------------------------------------------------------------

    def notify_text(from, subject, group: false)
      opening = "You have a new Ranger Clubhouse #{"group " if group}msg from #{from}. Subject: "
      room = SMS_LIMIT - (opening.length + 3)

      "#{opening}#{subject.to_s[0, [room, 0].max]}  #{SMS_SUFFIX}"
    end

    # Text one new-message alert, recorded in row_id: the status that row
    # records, and the SID Twilio gave the text, which a held or failed one has
    # none of. A text Twilio may have taken without answering is
    # send-unconfirmed, so it is never sent again.
    def notify_by_text(phone_number, sms_message, row_id)
      return [Broadcast::STATUS_SENT, nil] if Setting.get_value(Setting::BROADCAST_SMS_SANDBOX)

      [Broadcast::STATUS_SENT, SmsService.send_text(phone_number, sms_message, receipt_for: row_id)]
    rescue => e
      ErrorLog.record_exception(e, "sms-exception", extra: {
                                 type: "clubhouse-notify",
                                 phone: phone_number
                               })
      [e.is_a?(SmsException::Unconfirmed) ? Broadcast::STATUS_SEND_UNCONFIRMED : Broadcast::STATUS_SERVICE_FAIL, nil]
    end
  end
end
