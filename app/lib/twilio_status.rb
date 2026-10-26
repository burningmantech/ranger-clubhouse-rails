# frozen_string_literal: true

# What Twilio says about the account the Clubhouse texts through, for the
# Twilio Account panel on Administration › SMS Management: the account and
# its balance, each Notify service in TwilioServiceId, the last day's texts by
# what became of them, and the alerts Twilio raised. It only reads.
#
# Each answer is its own call and its own rescue, so one Twilio cannot give
# leaves the rest standing. Once Twilio cannot be connected to at all, nothing
# more is asked: every call would wait out its own timeout. An answer that was
# only slow fails alone.
#
# The answers are cached for CACHE_FOR, keyed by the settings they were asked
# with, so a corrected setting is asked about at once. A read missing an answer
# Twilio never gave is not cached, so the next look asks again.
class TwilioStatus
  CACHE_FOR = 5.minutes
  # Part of the cache key. Bump it whenever what read returns changes shape,
  # so a deploy never hands the new panel an answer the old code cached.
  CACHE_VERSION = 1
  WINDOW = 24.hours
  # One page of Twilio's message list. Past it the counts are a sample.
  MESSAGE_LIMIT = 1_000
  ALERT_LIMIT = 20

  # nil while the settings to ask with are missing. Otherwise a Hash of plain
  # values, safe to cache: checked_at, and an answer each for the account, its
  # balance, the texts and the alerts, plus one per service carrying its id.
  # An answer is { value: } or { error: }.
  def self.fetch(refresh: false)
    sid, token, service_ids = TwilioAccount.settings.values_at(:account_sid, :auth_token, :service_ids)
    return if sid.nil? || token.nil?

    key = ["twilio-status", CACHE_VERSION, Digest::SHA256.hexdigest([sid, token, *service_ids].join("|"))]
    cached = Rails.cache.read(key) unless refresh
    return cached if cached

    reader = new(TwilioAccount.build_client(sid, token))
    status = reader.read(sid, service_ids)
    Rails.cache.write(key, status, expires_in: CACHE_FOR) unless reader.missed?
    status
  end

  def initialize(client)
    @client = client
  end

  # Whether a call went out and no answer came back.
  def missed? = @missed == true

  def read(sid, service_ids)
    since = WINDOW.ago
    account = @client.api.v2010.accounts(sid)
    summary = ask do
      found = account.fetch
      { name: found.friendly_name, status: found.status, type: found.type,
        subaccount: found.owner_account_sid != found.sid }
    end
    # A subaccount keeps no balance of its own: Twilio bills its texts to the
    # main account, so there is nothing to ask for.
    balance = if summary.dig(:value, :subaccount)
                { value: { main_account: true } }
              else
                ask do
                  found = account.balance.fetch
                  { amount: found.balance, currency: found.currency }
                end
              end

    {
      checked_at: Time.current,
      account: summary,
      balance:,
      services: service_ids.map { |id| service_answer(id) },
      texts: ask { text_counts(since) },
      alerts: ask do
        @client.monitor.v1.alerts.list(start_date: since, limit: ALERT_LIMIT).map { |alert| alert_row(alert) }
      end
    }
  end

  private

  def ask
    return { error: @unreachable } if @unreachable

    { value: yield }
  rescue *TwilioAccount::ERRORS => e
    error = TwilioAccount.describe(e)
    if TwilioAccount.unanswered?(e)
      @missed = true
      @unreachable = error unless TwilioAccount.slow_answer?(e)
    end
    { error: }
  end

  # An id Twilio cannot be asked about is answered for without asking.
  def service_answer(id)
    answer = TwilioAccount.usable_id?(id) ? ask { service(id) } : { error: TwilioAccount::UNUSABLE_ID }
    answer.merge(id:)
  end

  # A Notify service, and where the Messaging Service it sends through posts
  # the texts Rangers send back, and where it posts them when that address
  # fails. While that service defers to each number's own webhook, its own
  # addresses are not the ones Twilio uses.
  def service(id)
    notify = @client.notify.v1.services(id).fetch
    messaging_sid = notify.messaging_service_sid.presence
    messaging = @client.messaging.v1.services(messaging_sid).fetch if messaging_sid
    { name: notify.friendly_name, messaging_service: messaging_sid, incoming_url: messaging&.inbound_request_url,
      fallback_url: messaging&.fallback_url.presence, defers_to_number: messaging&.use_inbound_webhook_on_number == true }
  end

  # Twilio filters by the UTC date a text was sent, not the time, so it is
  # asked for the date the window opens and each text's own time trims the rest.
  # It lists newest first, so a full page that reaches back past the window's
  # start holds all of it; one that does not may be missing the oldest.
  def text_counts(since)
    listed = @client.messages.list(date_sent_after: since.utc.to_date.iso8601, limit: MESSAGE_LIMIT,
                                   page_size: MESSAGE_LIMIT)
    inside = listed.select { |text| text.date_sent && text.date_sent >= since }
    reached_back = listed.any? { |text| text.date_sent && text.date_sent < since }
    { counts: inside.map(&:status).tally, sampled: listed.size >= MESSAGE_LIMIT && !reached_back }
  end

  def alert_row(alert)
    { at: alert.date_generated, code: alert.error_code.to_i, level: alert.log_level.to_s,
      text: alert_message(alert.alert_text) }
  end

  # Twilio writes an alert's text as encoded fields (ErrorCode=30007&Msg=…).
  # The message is what a reader wants; anything else is shown as it came.
  def alert_message(text)
    fields = URI.decode_www_form(text.to_s).to_h
    fields["Msg"].presence || fields["msg"].presence || text.to_s
  rescue ArgumentError
    text.to_s
  end
end
