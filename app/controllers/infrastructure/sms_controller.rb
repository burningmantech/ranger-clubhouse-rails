# frozen_string_literal: true

class Infrastructure::SmsController < ApplicationController
  # No authentication - this endpoint is called by Twilio
  skip_forgery_protection
  allow_unauthenticated_access

  # Block known web crawlers from this unpublished endpoint
  before_action :reject_crawlers

  # Process an inbound SMS message from Twilio
  def inbound
    incoming = parse_incoming
    return if incoming.nil?

    number = incoming.phone
    message = incoming.message

    if number.blank?
      ErrorLog.record("sms-inbound-exception", data: { type: "inbound-malformed" })
      render plain: "Missing phone number?", status: :unprocessable_entity
      return
    end

    person = Person.find_by_sms_number(number)

    unless person
      reply = "Hello from the Black Rock Ranger Clubhouse Bot. Sorry, your phone number cannot be found in the database. Contact rangers@burningman.org for help."
      BroadcastMessage.record(nil, Broadcast::STATUS_UNKNOWN_PHONE, nil, "sms", number, "inbound", message)
      render_twiml(reply)
      return
    end

    status, reply = process_command(person, message.to_s.strip.downcase, number)

    # Record the inbound message
    BroadcastMessage.record(nil, status, person.id, "sms", number, "inbound", message)

    # Record the reply if one was generated
    if reply.present?
      BroadcastMessage.record(nil, Broadcast::STATUS_REPLY, person.id, "sms", number, "outbound", reply)
    end

    render_twiml(reply)
  end

  private

  def parse_incoming
    SmsService.process_incoming(params)
  rescue => e
    ErrorLog.record_exception(e, "sms-inbound-exception")
    render json: { status: "error" }, status: :internal_server_error
    nil
  end

  def process_command(person, command, _number)
    case command
    # Stop commands - industry standard opt-out keywords
    when "stop", "quit", "cancel", "end", "arret", "unsubscribe", "unsub"
      person.mark_sms_stopped!(true)

      # Some services (e.g., Twilio) may respond automatically to STOP
      # and not allow a response from the application
      reply = if SmsService::NO_STOP_REPLIES
                ""
              else
                "You will no longer receive alerts. Reply START to resubscribe."
              end

      [Broadcast::STATUS_STOP, reply]

    # Start commands - re-subscribe
    when "start", "unstop", "sub", "subscribe", "yes"
      person.mark_sms_stopped!(false)
      [Broadcast::STATUS_START, "You have been re-subscribed to Clubhouse alerts."]

    # Help
    when "help"
      [Broadcast::STATUS_HELP, "Commands available: STOP, START, HELP. Contact rangers@burningman.org for more help."]

    # Stats - admin only
    when "stats"
      handle_stats(person)

    # Next shift
    when "next"
      handle_next_shift(person)

    # Unknown command
    else
      [Broadcast::STATUS_UNKNOWN_COMMAND, "The command is not understood. Contact rangers@burningman.org for help."]
    end
  end

  def handle_stats(person)
    unless person.has_role?(Role::ADMIN)
      return [Broadcast::STATUS_STATS, "Sorry, you are not permitted to use this command."]
    end

    rows = Broadcast.where("created_at >= ?", Current.time - 1.day)
    broadcast_count = rows.count

    if broadcast_count.zero?
      reply = "All quiet. No broadcasts sent in the last 24 hours."
    else
      total_recipients = rows.sum(:recipient_count)
      sms_fails = rows.sum(:sms_failed)
      email_fails = rows.sum(:email_failed)
      last_broadcast = rows.order(:created_at).last
      last_date = last_broadcast.created_at

      reply = "Broadcasts #{broadcast_count} Recipients #{total_recipients} SMS fails #{sms_fails} Email fails #{email_fails} Last broadcast @ #{last_date}"
    end

    inbound_count = BroadcastMessage.where(direction: "inbound")
                                    .where("created_at >= ?", Current.time - 1.day)
                                    .count
    reply += " Inbound msgs #{inbound_count}"

    [Broadcast::STATUS_STATS, reply]
  end

  def handle_next_shift(person)
    next_shift = Scheduling::Query.find_next_shift(person.id)

    reply = if next_shift
              formatted = next_shift.begins.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)
              "Next shift is #{next_shift.title} - #{next_shift.description} #{formatted}"
            else
              "No upcoming shifts were found."
            end

    [Broadcast::STATUS_NEXT, reply]
  end

  def render_twiml(reply)
    twiml = SmsService.reply_response(reply.presence ? "#{Rbs::SMS_PREFIX}#{reply}#{Rbs::SMS_SUFFIX}" : "")
    if twiml.present?
      render xml: twiml, content_type: "text/xml"
    else
      head :ok
    end
  end

  def reject_crawlers
    ua = request.user_agent.to_s
    if ua.match?(/AOLBuild|Baidu|bingbot|DuckDuckBot|googlebot|yahoo|yandex/i)
      render json: { error: "not authorized." }, status: :forbidden
    end
  end
end
