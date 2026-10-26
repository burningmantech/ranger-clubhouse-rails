# frozen_string_literal: true

require "faraday"

# A stand-in for Twilio::REST::Client answering what SMS Management asks:
# the account, its balance, the Notify services, the Messaging Services (which
# an update changes), the message list (a page at a time, or all at once) and
# the alerts, from plain values; and what the send path sends: a Notify
# service's notifications, and texts made with messages.create, each answered
# with a SID of its own. A part named in errors: raises the error given
# instead. asked records every part asked for, in order, and params the
# keywords each part was last asked with; notifications and created_texts keep
# every send, in order. A Notify service is its name.
class FakeTwilioClient
  Account = Data.define(:friendly_name, :status, :type, :sid, :owner_account_sid)
  # Never a real Account SID's shape (AC and 32 hex digits): GitHub's secret
  # scanning takes any such string for a live credential and refuses the push.
  MAIN_ACCOUNT = Account.new("Black Rock Rangers", "active", "Full", "deadbeef", "deadbeef")
  Balance = Data.define(:balance, :currency)
  Service = Data.define(:friendly_name)
  MessagingService = Data.define(:inbound_request_url, :inbound_method, :use_inbound_webhook_on_number,
                                 :fallback_url) do
    def initialize(inbound_request_url:, inbound_method:, use_inbound_webhook_on_number:, fallback_url: nil) = super
  end
  MESSAGING_SERVICE_SID = "MG0123456789abcdef0123456789abcdef"
  CLUBHOUSE2_INCOMING = "https://ranger-clubhouse.burningman.org/api/sms/inbound"
  Text = Data.define(:date_sent, :date_created, :direction, :status, :error_code, :from, :to, :body)
  # A text messages.create took: the SID Twilio answers with.
  CreatedText = Data.define(:sid)
  Alert = Data.define(:date_generated, :error_code, :log_level, :alert_text)

  # One call Twilio would answer: fetch for a record.
  Call = Struct.new(:answer) do
    def fetch = answer.call
  end

  # client.monitor.v1.alerts, taking only the keywords twilio-ruby's
  # AlertList#list takes, so a misspelled one fails here as it would there.
  AlertList = Struct.new(:client) do
    def list(log_level: :unset, start_date: :unset, end_date: :unset, limit: nil, page_size: nil)
      params = { log_level:, start_date:, end_date:, limit:, page_size: }.reject { |_, value| value.nil? || value == :unset }
      client.answer(:alerts, params) { client.alert_rows }
    end
  end

  # One page of the message list, and the links Twilio gives to its neighbours.
  MessagePage = Struct.new(:texts, :next_page_url, :previous_page_url) do
    include Enumerable

    def each(&) = texts.each(&)
  end

  # client.notify.v1 and client.messaging.v1: each its own list of services.
  NotifyV1 = Struct.new(:client) do
    def v1 = self
    def services(id) = NotifyCall.new(client, id)
  end

  MessagingV1 = Struct.new(:client) do
    def v1 = self
    def services(sid) = MessagingCall.new(client, sid)
  end

  # One Notify service: read it, or send through it
  # (services(id).notifications.create).
  NotifyCall = Struct.new(:client, :id) do
    def fetch = client.answer(:services) { client.notify_service(id) }
    def notifications = self
    def create(**params) = client.answer(:notification_create, params) { client.notify_through(id, params) }
  end

  # One Messaging Service: read it, or change where it sends incoming texts.
  MessagingCall = Struct.new(:client, :sid) do
    def fetch = client.answer(:messaging_service) { client.messaging_service(sid) }
    def update(**params) = client.answer(:messaging_update, params) { client.update_messaging_service(sid, params) }
  end

  # client.messages: the list the panel counts and the export reads, the
  # pages the log reads, and a text to send.
  MessageList = Struct.new(:client) do
    def list(**params) = client.answer(:messages, params) { client.texts }

    def page(**params)
      client.answer(:message_page, params) { MessagePage.new(client.texts, client.next_page_url, client.previous_page_url) }
    end

    def create(**params) = client.answer(:message_create, params) { client.create_text(params) }
  end

  # A text as Twilio lists it. A field not given reads as a delivered text,
  # sent an hour ago from the Clubhouse's number to +1 415 555 0142.
  def self.text(**fields)
    at = 1.hour.ago
    Text.new(**{ date_sent: at, date_created: at, direction: "outbound-api", status: "delivered", error_code: nil,
                 from: "+17755550100", to: "+14155550142", body: "A broadcast" }.merge(fields))
  end

  # The error twilio-ruby raises when Twilio is slow to answer: a plain
  # TwilioError whose cause is Faraday's timeout. Raising it keeps the cause.
  def self.read_timeout
    raise Faraday::TimeoutError, "Net::ReadTimeout"
  rescue Faraday::TimeoutError
    begin
      raise Twilio::REST::TwilioError, "Net::ReadTimeout with #<TCPSocket:(closed)>"
    rescue Twilio::REST::TwilioError => e
      e
    end
  end

  # The error twilio-ruby raises when Twilio refuses a call, with Twilio's own
  # code and words: 21610 for a number that texted STOP, say.
  def self.refusal(code, message)
    Twilio::REST::RestError.new("Unable to create record", Twilio::Response.new(400, { code:, message: }.to_json))
  end

  attr_reader :asked, :params, :texts, :next_page_url, :previous_page_url, :notifications, :created_texts

  def initialize(account: MAIN_ACCOUNT, balance: Balance.new("412.37", "USD"),
                 services: { "ISservice0001" => "Ranger Alerts" },
                 messaging_services: { MESSAGING_SERVICE_SID => MessagingService.new(CLUBHOUSE2_INCOMING, "POST", false) },
                 texts: [], alerts: [], next_page_url: nil, previous_page_url: nil, errors: {})
    @account = account
    @balance = balance
    @services = services
    @messaging_services = messaging_services
    @texts = texts
    @alerts = alerts
    @next_page_url = next_page_url
    @previous_page_url = previous_page_url
    @errors = errors
    @asked = []
    @params = {}
    @notifications = []
    @created_texts = []
  end

  # The way to a call, not a call: client.api.v2010.accounts(sid) and
  # client.monitor.v1 lead back here.
  def api = self
  def v2010 = self
  def monitor = self
  def v1 = self
  def accounts(_sid) = self

  def fetch = answer(:account) { @account }
  def balance = Call.new(-> { answer(:balance) { @balance } })
  def notify = NotifyV1.new(self)
  def messaging = MessagingV1.new(self)
  def messages = MessageList.new(self)
  def alerts = AlertList.new(self)
  def alert_rows = @alerts

  def notify_service(id) = Service.new(@services.fetch(id) { raise not_found(id) })

  def messaging_service(sid) = @messaging_services.fetch(sid) { raise not_found(sid) }

  # A notification through a Notify service Twilio knows, kept with the
  # service's id. Notify checks no number, so every one is taken.
  def notify_through(id, params)
    notify_service(id)
    @notifications << { service: id, **params }
  end

  # A text made with messages.create, kept as asked, and answered with a
  # message SID of its own.
  def create_text(params)
    @created_texts << params
    CreatedText.new(format("SM%032d", @created_texts.size))
  end

  def update_messaging_service(sid, params)
    @messaging_services[sid] = messaging_service(sid).with(**params.slice(:inbound_request_url, :inbound_method,
                                                                          :fallback_url, :use_inbound_webhook_on_number))
  end

  def answer(part, params = {})
    @asked << part
    @params[part] = params
    raise @errors[part] if @errors[part]

    yield
  end

  private

  def not_found(id)
    body = { code: 20404, message: "The requested resource /Services/#{id} was not found" }.to_json
    Twilio::REST::RestError.new("Unable to fetch record", Twilio::Response.new(404, body))
  end
end

module FakeTwilioTestHelper
  # TwilioAccount builds every client in one place; this hands it the fake there.
  def with_fake_twilio(fake)
    original = TwilioAccount.method(:build_client)
    TwilioAccount.define_singleton_method(:build_client) { |*| fake }
    yield fake
  ensure
    TwilioAccount.define_singleton_method(:build_client, original)
  end

  def configure_twilio(sid: "deadbeef", token: "token-never-shown",
                       service_ids: "ISservice0001", messaging_service_id: FakeTwilioClient::MESSAGING_SERVICE_SID)
    { Setting::TWILIO_ACCOUNT_SID => sid, Setting::TWILIO_AUTH_TOKEN => token,
      Setting::TWILIO_SERVICE_ID => service_ids,
      Setting::TWILIO_MESSAGING_SERVICE_ID => messaging_service_id }.each do |name, value|
      Setting.find_or_initialize_by(name:).update!(value:)
    end
  end
end
