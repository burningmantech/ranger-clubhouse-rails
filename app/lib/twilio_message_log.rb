# frozen_string_literal: true

# The texts Twilio sent and received on the account, newest first, for the
# log on Administration › SMS Management: a page at a time, or the newest
# EXPORT_LIMIT for the export. Twilio filters by the two numbers and by the
# UTC date a text was sent, and by nothing else, so those are the log's
# filters; it pages by a token it hands back with each page.
class TwilioMessageLog
  PAGE_SIZE = 50
  # The most Twilio lists on one page, so the export is a single call.
  EXPORT_LIMIT = 1_000

  # A text as the log shows it, read off Twilio's answer once.
  Text = Data.define(:sent_at, :direction, :status, :error_code, :from, :to, :body) do
    def incoming? = direction == "inbound"

    # The number at the Ranger's end: who it went to, or who sent it in.
    def number = incoming? ? from : to
  end

  class << self
    # One page as { texts:, people:, page:, next_page:, previous_page: }, a
    # neighbouring page being { page:, token: } or nil. { error: } when
    # Twilio cannot answer, and nil while the settings to ask with are missing.
    def page(criteria, page: 0, token: nil)
      client = SmsManagement.client or return
      filters = twilio_filters(criteria)
      return { texts: [], people: {}, page: 0, next_page: nil, previous_page: nil } unless filters

      result = client.messages.page(**filters, page_size: PAGE_SIZE, page_number: page, page_token: token || :unset)
      texts = result.map { |message| text(message) }
      { texts:, people: people(texts), page:,
        next_page: neighbour(result.next_page_url), previous_page: neighbour(result.previous_page_url) }
    rescue *SmsManagement::ERRORS => e
      { error: SmsManagement.describe(e) }
    end

    # The newest EXPORT_LIMIT texts the filters match, as { texts:, people: },
    # with the same { error: } and nil as page.
    def export(criteria)
      client = SmsManagement.client or return
      filters = twilio_filters(criteria)
      return { texts: [], people: {} } unless filters

      texts = client.messages.list(**filters, limit: EXPORT_LIMIT, page_size: EXPORT_LIMIT).map { |message| text(message) }
      { texts:, people: people(texts) }
    rescue *SmsManagement::ERRORS => e
      { error: SmsManagement.describe(e) }
    end

    private

    # The log's filters as Twilio takes them, or nil when a To or From names
    # no one person with a number on file, which no text can match.
    def twilio_filters(criteria)
      filters = {}
      { to: criteria[:to], from: criteria[:from] }.compact.each do |key, value|
        filters[key] = number_for(value) or return nil
      end
      filters[:date_sent_after] = criteria[:sent_after].iso8601 if criteria[:sent_after]
      filters[:date_sent_before] = criteria[:sent_before].iso8601 if criteria[:sent_before]
      filters
    end

    # A phone number as Twilio keeps it, or the number on file for the one
    # person a callsign names (Person.resolve_callsign: none when it could be
    # two people).
    def number_for(value)
      number = SmsService.normalize_phone(value)
      return number if number.start_with?("+")

      on_file = Person.resolve_callsign(value)&.sms_number
      SmsService.normalize_phone(on_file) if on_file.present?
    end

    def text(message)
      Text.new(sent_at: message.date_sent || message.date_created, direction: message.direction,
               status: message.status, error_code: message.error_code, from: message.from, to: message.to,
               body: message.body)
    end

    # Whose number each text has at the Ranger's end, matched as the inbound
    # webhook matches it (Person.find_by_sms_number): exactly, to sms_number,
    # the lowest id where two people share a number. index_by keeps the last.
    def people(texts)
      Person.where(sms_number: texts.filter_map(&:number).uniq).order(id: :desc).index_by(&:sms_number)
    end

    # Where a page link from Twilio leads.
    def neighbour(url)
      return unless url

      query = URI.decode_www_form(URI.parse(url).query.to_s).to_h
      { page: query["Page"].to_i, token: query["PageToken"] } if query["PageToken"].present?
    end
  end
end
