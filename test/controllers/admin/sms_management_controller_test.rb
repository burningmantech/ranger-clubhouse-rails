# frozen_string_literal: true

require "test_helper"

class Admin::SmsManagementControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper
  include FakeTwilioTestHelper
  include EnvTestHelper

  NEXT_PAGE = "https://api.twilio.com/2010-04-01/Accounts/AC0123/Messages.json?PageSize=50&Page=1&PageToken=PAMMnext"

  setup do
    Current.reset

    @tech_ninja = person(:echelon_ranger)
    @admin = person(:auditor_ranger)
    @outsider = person(:retired_ranger)
    @ranger = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)
    # Tech Ninja and nothing else: this page is one the Admin role does not
    # open, so the tests have to prove the role on its own works.
    grant_role(@tech_ninja, Role::TECH_NINJA)
  end

  teardown do
    Current.reset
  end

  # ---------------------------------------------------------------- gate

  test "denies access without the tech ninja role" do
    sign_in_as(@outsider)

    get admin_sms_management_path

    assert_redirected_to me_root_path
  end

  test "an admin without the tech ninja role is turned away, from both panels too" do
    # Configured, so a change let past the gate would reach the fake.
    configure_twilio
    sign_in_as(@admin)

    get admin_sms_management_path

    assert_redirected_to me_root_path
    assert_equal "Tech Ninja role required to manage SMS.", flash[:error]

    [admin_sms_management_twilio_path, admin_sms_management_messages_path].each do |path|
      get path

      assert_redirected_to me_root_path
    end

    fake = FakeTwilioClient.new
    with_fake_twilio(fake) do
      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/x" } }
    end

    assert_redirected_to me_root_path
    assert_empty fake.asked
  end

  # ---------------------------------------------------------------- the page

  test "the page holds the settings, and frames for the account and for the log with its filters" do
    sign_in_as(@tech_ninja)

    get admin_sms_management_path(filter: { to: "TestRanger", page: 2, page_token: "PAMMabc" })

    assert_response :success
    assert_select "turbo-frame#sms-twilio[src=?][loading=lazy]", admin_sms_management_twilio_path
    # Not permanent: a visit back asks for the panel again (from the cache)
    # rather than keeping the one Turbo's snapshot held.
    assert_select "turbo-frame[data-turbo-permanent]", 0
    assert_select "turbo-frame#sms-log[src=?][loading=lazy][target=_top]",
                  admin_sms_management_messages_path(filter: { to: "TestRanger", page: 2, page_token: "PAMMabc" })
    # A chip takes its filter off and starts again at Twilio's first page.
    assert_select "a[aria-label=?][href=?]", "Remove filter: To: TestRanger", admin_sms_management_path
    # Nothing to export from until Twilio can be asked.
    assert_select "a[href*='.csv']", 0
    assert_unique_dom_ids
  end

  test "the settings card says what is set without showing it" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")

    sign_in_as(@tech_ninja)

    get admin_sms_management_path

    assert_includes response.body, "de…beef"
    assert_not_includes response.body, "deadbeef"
    assert_not_includes response.body, "token-never-shown"
    assert_includes response.body, "A broadcast is split evenly across them."
    assert_includes response.body, TwilioSignatureConcern.address(infrastructure_sms_inbound_path)
    # The fixtures hold broadcast texts back.
    assert_includes response.body, "Broadcast texts are recorded but not sent."
    assert_select "a[href=?]", admin_sms_management_path(format: :csv)
    # Settings is an Admin page: a Tech Ninja alone is not offered it.
    assert_select "a[href=?]", admin_settings_path(filter: "twilio"), 0
  end

  test "an admin who is also a tech ninja is offered the settings" do
    grant_role(@tech_ninja, Role::ADMIN)
    sign_in_as(@tech_ninja)

    get admin_sms_management_path

    assert_select "a[href=?]", admin_settings_path(filter: "twilio"), text: /Edit Twilio Settings/
  end

  # ---------------------------------------------------------------- the log

  test "the log lists Twilio's texts with the person at the Ranger's end" do
    configure_twilio
    @ranger.update_columns(sms_number: "+14155550142")
    texts = [
      FakeTwilioClient.text(body: "Muster at HQ now"),
      FakeTwilioClient.text(direction: "inbound", status: "received", from: "+17025550188", to: "+17755550100",
                            body: "is this the rangers?"),
      FakeTwilioClient.text(status: "undelivered", error_code: 30007, body: "Shift reminder")
    ]

    sign_in_as(@tech_ninja)

    with_fake_twilio(FakeTwilioClient.new(texts:)) { get admin_sms_management_messages_path }

    assert_response :success
    assert_select "turbo-frame#sms-log[target=_top]" do
      assert_select "tbody tr", 3
      assert_select "tbody tr:nth-child(1)", text: /TestRanger.*delivered.*outgoing.*\(415\) 555-0142.*Muster at HQ now/m
      assert_select "tbody tr:nth-child(2)", text: /—.*received.*incoming.*\(702\) 555-0188.*is this the rangers\?/m
      assert_select "tbody tr:nth-child(3) .badge", text: "undelivered"
      assert_select "tbody tr:nth-child(3) a[href=?][target=_blank]", "https://www.twilio.com/docs/api/errors/30007",
                    text: "30007"
    end
  end

  test "a number two people share names the one the inbound webhook would" do
    configure_twilio
    first, second = [@ranger, @outsider].sort_by(&:id)
    [first, second].each { |person| person.update_columns(sms_number: "+14155550142") }

    sign_in_as(@tech_ninja)

    with_fake_twilio(FakeTwilioClient.new(texts: [FakeTwilioClient.text])) { get admin_sms_management_messages_path }

    assert_equal first, Person.find_by_sms_number("+14155550142")
    assert_select "tbody tr", text: /#{first.callsign}/
    assert_select "tbody tr", text: /#{second.callsign}/, count: 0
  end

  test "a callsign that could be two people finds no one, and Twilio is not asked" do
    configure_twilio
    [@ranger, @outsider].each { |person| person.update_columns(callsign_normalized: "firefly", sms_number: "+14155550142") }
    fake = FakeTwilioClient.new(texts: [FakeTwilioClient.text])

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_messages_path(filter: { to: "Fire Fly" }) }

    assert_includes response.body, "No texts match the current filters."
    assert_not_includes fake.asked, :message_page
  end

  test "the filters go to Twilio as numbers and UTC dates" do
    configure_twilio
    @ranger.update_columns(sms_number: "+14155550142")
    fake = FakeTwilioClient.new

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      get admin_sms_management_messages_path(filter: { to: @ranger.callsign.downcase, from: "(702) 555-0188",
                                                       sent_after: "2026-10-20", sent_before: "2026-10-24" })
    end

    assert_equal({ to: "+14155550142", from: "+17025550188", date_sent_after: "2026-10-20",
                   date_sent_before: "2026-10-24", page_size: 50, page_number: 0, page_token: :unset },
                 fake.params[:message_page])
    assert_includes response.body, "No texts match the current filters."

    # 20:00 in Arizona is 03:00 the next day in UTC, the date Twilio reads.
    with_fake_twilio(fake) { get admin_sms_management_messages_path(filter: { sent_after: "2026-10-25T20:00" }) }

    assert_equal "2026-10-26", fake.params[:message_page][:date_sent_after]
  end

  test "a callsign with no number on file asks Twilio nothing and lists nothing" do
    configure_twilio
    fake = FakeTwilioClient.new(texts: [FakeTwilioClient.text])

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_messages_path(filter: { to: "NoSuchRanger" }) }

    assert_includes response.body, "No texts match the current filters."
    assert_not_includes fake.asked, :message_page
  end

  test "paging follows the token Twilio hands back" do
    configure_twilio
    fake = FakeTwilioClient.new(texts: [FakeTwilioClient.text], next_page_url: NEXT_PAGE)

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_messages_path(filter: { to: "+14155550142" }) }

    assert_select "a[href=?]", admin_sms_management_path(filter: { to: "+14155550142", page: 1, page_token: "PAMMnext" }),
                  text: /Next Page/
    assert_select "a", text: /Previous Page/, count: 0

    with_fake_twilio(fake) do
      get admin_sms_management_messages_path(filter: { to: "+14155550142", page: 1, page_token: "PAMMnext" })
    end

    assert_equal [1, "PAMMnext"], fake.params[:message_page].values_at(:page_number, :page_token)
    assert_includes response.body, "Page 2"
  end

  test "a later page links back by Twilio's token, even when it comes back empty" do
    configure_twilio
    previous = "https://api.twilio.com/2010-04-01/Accounts/AC0123/Messages.json?PageSize=50&Page=0&PageToken=PAMMprev"
    fake = FakeTwilioClient.new(previous_page_url: previous)

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_messages_path(filter: { page: 1, page_token: "PAMMnext" }) }

    assert_select "a[href=?]", admin_sms_management_path(filter: { page: 0, page_token: "PAMMprev" }),
                  text: /Previous Page/
    assert_includes response.body, "Twilio lists no more texts."
    assert_not_includes response.body, "Twilio lists no texts for this account."
  end

  test "a page token Twilio could not have written starts at the first page" do
    configure_twilio
    fake = FakeTwilioClient.new

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      get admin_sms_management_messages_path(filter: { page: 3, page_token: "not a token!" })
    end

    assert_equal [0, :unset], fake.params[:message_page].values_at(:page_number, :page_token)
    assert_includes response.body, "Twilio lists no texts for this account."
  end

  test "the log says why Twilio could not answer, ids masked" do
    configure_twilio
    # A Messaging Service id: an Account SID of Twilio's shape is one GitHub
    # takes for a live credential (see FakeTwilioClient::MAIN_ACCOUNT).
    body = { code: 20003, message: "Authenticate /Services/#{FakeTwilioClient::MESSAGING_SERVICE_SID}" }.to_json
    error = Twilio::REST::RestError.new("Unable to fetch page", Twilio::Response.new(401, body))

    sign_in_as(@tech_ninja)

    with_fake_twilio(FakeTwilioClient.new(errors: { message_page: error })) { get admin_sms_management_messages_path }

    assert_select "turbo-frame#sms-log", text: %r{Authenticate /Services/MG…cdef \(Twilio error 20003\)}
    assert_not_includes response.body, FakeTwilioClient::MESSAGING_SERVICE_SID
  end

  test "the log says it cannot ask before the settings are in" do
    sign_in_as(@tech_ninja)

    get admin_sms_management_messages_path

    assert_select "turbo-frame#sms-log", text: /cannot ask Twilio for the texts/
  end

  # ---------------------------------------------------------------- export

  test "exports the newest texts Twilio lists, a formula lead disarmed" do
    configure_twilio
    @ranger.update_columns(sms_number: "+14155550142")
    texts = [FakeTwilioClient.text(direction: "inbound", status: "received", from: "+17025550188", to: "+17755550100",
                                   body: '=HYPERLINK("http://example.com")'),
             FakeTwilioClient.text(status: "undelivered", error_code: 30007),
             FakeTwilioClient.text(to: "+447700900123")]
    fake = FakeTwilioClient.new(texts:)

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_path(format: :csv, filter: { sent_after: "2026-10-20" }) }

    assert_response :success
    assert_equal "text/csv", response.media_type
    lines = response.body.lines(chomp: true)
    assert_equal "Sent,Direction,Status,Error Code,Callsign,Number,Text", lines.first
    assert_match(/\A[\d-]+ [\d:]+,incoming,received,,,\(702\) 555-0188,"'=HYPERLINK\(""http:\/\/example.com""\)"\z/,
                 lines.second)
    assert_match(/,outgoing,undelivered,30007,#{@ranger.callsign},\(415\) 555-0142,A broadcast\z/, lines.third)
    # A number PhoneFormatter leaves bare stays text, "+" and all.
    assert_match(/,outgoing,delivered,,,'\+447700900123,A broadcast\z/, lines.fourth)
    assert_equal({ date_sent_after: "2026-10-20", limit: 1_000, page_size: 1_000 }, fake.params[:messages])
  end

  test "an export that cannot ask Twilio goes back to the page and says why" do
    sign_in_as(@tech_ninja)

    get admin_sms_management_path(format: :csv)

    assert_redirected_to admin_sms_management_path
    assert_equal "The texts could not be exported: the Account SID and Auth Token are not set.", flash[:error]
  end

  # ---------------------------------------------------------------- incoming texts

  test "the panel says where Twilio sends incoming texts, and offers this server's address" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")
    fake = FakeTwilioClient.new(services: { "ISservice0001" => "Ranger Alerts", "ISservice0002" => "Ranger News" })

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_twilio_path }

    assert_select "turbo-frame#sms-twilio" do
      assert_select "dd", text: /Another server.*#{Regexp.escape(FakeTwilioClient::CLUBHOUSE2_INCOMING)}/m
      # Both send through one Messaging Service, so it is listed once.
      assert_select ".badge", text: "Another server", count: 1
      assert_select "form[action=?]", admin_sms_management_incoming_path do
        assert_select "input[name=_method][value=patch]"
        assert_select "input[type=url][name=?][value=?]", "twilio_incoming[url]",
                      TwilioSignatureConcern.address(infrastructure_sms_inbound_path)
        assert_select "[type=submit][data-turbo-confirm*='stops getting STOP, START and HELP replies']"
      end
    end
  end

  test "pointing Twilio at this server changes the Messaging Service, records it, and says so" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")
    fake = FakeTwilioClient.new(services: { "ISservice0001" => "Ranger Alerts", "ISservice0002" => "Ranger News" })
    # The address its signatures are checked against, not the one this page
    # is reached at (http://www.example.com).
    here = TwilioSignatureConcern.address(infrastructure_sms_inbound_path)

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: here } }

      assert_redirected_to admin_sms_management_twilio_path(refresh: 1)
      follow_redirect!
    end

    assert_equal({ inbound_request_url: here, inbound_method: "POST", fallback_url: "", use_inbound_webhook_on_number: false },
                 fake.params[:messaging_update])
    # The two Notify services send through one Messaging Service.
    assert_equal 1, fake.asked.count(:messaging_update)
    assert_select "turbo-frame#sms-twilio" do
      assert_select "[role=alert]", text: "Twilio now sends incoming texts to #{here}. " \
                                          "It sent them to #{FakeTwilioClient::CLUBHOUSE2_INCOMING} until now."
      assert_select "dd", text: /This server.*#{Regexp.escape(here)}/m
    end
    log = ActionLog.find_by!(event: "twilio-incoming-update")
    assert_equal @tech_ninja.id, log.person_id
    assert_equal here, log.data["url"]
    assert_equal [{ "service" => "MG…cdef",
                    "before" => { "url" => FakeTwilioClient::CLUBHOUSE2_INCOMING, "method" => "POST", "fallback_url" => nil,
                                  "defers_to_number" => false } }], log.data["services"]
  end

  test "a fallback address is shown, cleared by the change, and kept in the action log" do
    configure_twilio
    fallback = "https://ranger-clubhouse.burningman.org/api/sms/fallback"
    service = FakeTwilioClient::MessagingService.new(inbound_request_url: FakeTwilioClient::CLUBHOUSE2_INCOMING,
                                                     inbound_method: "GET", use_inbound_webhook_on_number: true,
                                                     fallback_url: fallback)
    fake = FakeTwilioClient.new(messaging_services: { FakeTwilioClient::MESSAGING_SERVICE_SID => service })

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      get admin_sms_management_twilio_path

      assert_select "dd", text: /When that address fails, Twilio sends the text to #{Regexp.escape(fallback)}\./

      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
    end

    assert_equal "Twilio now sends incoming texts to https://clubhouse.example.org/in. It sent them to " \
                 "#{FakeTwilioClient::CLUBHOUSE2_INCOMING} until now. The fallback address #{fallback} is cleared.",
                 flash[:success]
    assert_equal "", fake.messaging_service(FakeTwilioClient::MESSAGING_SERVICE_SID).fallback_url
    # Everything the change replaced, so it can be put back.
    assert_equal({ "url" => FakeTwilioClient::CLUBHOUSE2_INCOMING, "method" => "GET", "fallback_url" => fallback,
                   "defers_to_number" => true },
                 ActionLog.find_by!(event: "twilio-incoming-update").data["services"].sole["before"])
  end

  test "an address Twilio cannot reach is refused before Twilio is asked" do
    configure_twilio
    fake = FakeTwilioClient.new

    sign_in_as(@tech_ninja)

    ["http://clubhouse.example.org/infrastructure/sms/inbound", "https://localhost:3000/infrastructure/sms/inbound",
     "https://wt.localhost/infrastructure/sms/inbound", "https://127.0.0.1/infrastructure/sms/inbound",
     "https://user:secret@clubhouse.example.org/infrastructure/sms/inbound", "not an address",
     "https://127.1/in", "https://2130706433/in", "https://0x7f000001/in", "https://010.0.0.1/in", "https://[::1]/in",
     "https://LOCALHOST/in", "https://localhost./in", "https://box.LOCAL/in", "https://clubhouse/in",
     "https://clubhouse.example.org/in?token=s3cret", "https://clubhouse.example.org/in#top"].each do |url|
      with_fake_twilio(fake) { patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: } } }

      assert_redirected_to admin_sms_management_twilio_path
      assert_match(/\ATwilio was not changed: /, flash[:error], url)
    end
    assert_empty fake.asked
    assert_not ActionLog.exists?(event: "twilio-incoming-update")
  end

  test "a change Twilio refuses says so and records nothing" do
    configure_twilio
    body = { code: 20003, message: "Authenticate" }.to_json
    error = Twilio::REST::RestError.new("Unable to update record", Twilio::Response.new(401, body))
    fake = FakeTwilioClient.new(errors: { messaging_update: error })

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
    end

    assert_redirected_to admin_sms_management_twilio_path(refresh: 1)
    assert_equal "Twilio was not changed: Authenticate (Twilio error 20003).", flash[:error]
    assert_nil flash[:success]
    assert_not ActionLog.exists?(event: "twilio-incoming-update")
  end

  test "the training server asks Twilio nothing about the account, and is not allowed the change" do
    configure_twilio
    fake = FakeTwilioClient.new

    sign_in_as(@tech_ninja)

    with_env("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => "2026-08-01 12:00:00") do
      with_fake_twilio(fake) do
        get admin_sms_management_twilio_path(refresh: 1)

        assert_response :success
        assert_select "turbo-frame#sms-twilio", text: /Live Twilio account reads are not available on the Groundhog Day Server\./
        assert_select "form[action=?]", admin_sms_management_incoming_path, 0
        assert_empty fake.asked

        patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
      end
    end

    assert_redirected_to me_root_path
    assert_not_includes fake.asked, :messaging_update
  end

  test "the training server asks Twilio nothing for the log or the export, and offers no export" do
    configure_twilio
    fake = FakeTwilioClient.new(texts: [FakeTwilioClient.text])

    sign_in_as(@tech_ninja)

    with_env("RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME" => "2026-08-01 12:00:00") do
      with_fake_twilio(fake) do
        get admin_sms_management_path

        assert_response :success
        assert_select "a[href*='.csv']", 0

        get admin_sms_management_messages_path

        assert_select "turbo-frame#sms-log", text: /Live Twilio text logs are not available on the Groundhog Day Server\./

        get admin_sms_management_path(format: :csv)

        assert_redirected_to admin_sms_management_path
        assert_equal "The texts could not be exported: live Twilio reads are not available on the Groundhog Day Server.",
                     flash[:error]
      end
    end

    assert_empty fake.asked
  end

  test "a change Twilio does not answer may have been made, so it is recorded and said so" do
    configure_twilio
    fake = FakeTwilioClient.new(errors: { messaging_update: FakeTwilioClient.read_timeout })

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
    end

    assert_redirected_to admin_sms_management_twilio_path(refresh: 1)
    assert_nil flash[:success]
    assert_equal "Twilio did not confirm the change, so it may or may not have been made " \
                 "(Could not reach Twilio: Net::ReadTimeout with #<TCPSocket:(closed)>). " \
                 "The address below shows where Twilio sends incoming texts now.", flash[:error]
    logged = ActionLog.find_by!(event: "twilio-incoming-update").data["services"].sole
    assert logged["unanswered"]
    assert_equal FakeTwilioClient::CLUBHOUSE2_INCOMING, logged["before"]["url"]
  end

  test "a change that stops partway keeps what it changed, and says the rest was not" do
    configure_twilio(service_ids: "ISservice0001,ISservice0002")
    unknown = "MGfedcba9876543210fedcba9876543210"
    fake = FakeTwilioClient.new(services: { "ISservice0001" => "Ranger Alerts",
                                            "ISservice0002" => FakeTwilioClient::Service.new("Ranger News", unknown) })

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
    end

    assert_match(/\ATwilio now sends incoming texts to https:\/\/clubhouse.example.org\/in\./, flash[:success])
    assert_equal "Twilio stopped partway, and the rest was not changed: " \
                 "The requested resource /Services/MG…3210 was not found (Twilio error 20404).", flash[:error]
    assert_equal "https://clubhouse.example.org/in",
                 fake.messaging_service(FakeTwilioClient::MESSAGING_SERVICE_SID).inbound_request_url
    assert_equal ["MG…cdef"], ActionLog.find_by!(event: "twilio-incoming-update").data["services"].pluck("service")
  end

  test "an id with a space in it is reported, not asked about, and blocks the change" do
    configure_twilio(service_ids: "ISservice0001, ISservice0002")
    fake = FakeTwilioClient.new

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) do
      get admin_sms_management_twilio_path

      assert_response :success
      assert_select "dd", text: /Could not be read.*the id is empty or holds a space or punctuation/m
      assert_select "form[action=?]", admin_sms_management_incoming_path, 0
      assert_select "turbo-frame#sms-twilio p", text: /Twilio could not read every Notify service above/

      patch admin_sms_management_incoming_path, params: { twilio_incoming: { url: "https://clubhouse.example.org/in" } }
    end

    assert_equal 1, fake.asked.count(:services)
    assert_equal "Twilio was not changed: TwilioServiceId holds an id that is empty or has a space or punctuation in it.",
                 flash[:error]
    assert_not_includes fake.asked, :messaging_update
  end

  # ---------------------------------------------------------------- Twilio panel

  test "the Twilio panel says it cannot ask before the settings are in" do
    sign_in_as(@tech_ninja)

    get admin_sms_management_twilio_path

    assert_response :success
    assert_select "turbo-frame#sms-twilio", text: /cannot ask Twilio about the account/
  end

  test "the Twilio panel shows the account, and what could not be read, ids masked" do
    configure_twilio(service_ids: "ISservice0001,ISfedcba9876543210fedcba9876543210")
    alert = FakeTwilioClient::Alert.new(1.hour.ago, "30007", "warning", "ErrorCode=30007&Msg=Message+filtered")
    texts = [FakeTwilioClient.text, FakeTwilioClient.text, FakeTwilioClient.text(status: "undelivered")]
    fake = FakeTwilioClient.new(texts:, alerts: [alert])

    sign_in_as(@tech_ninja)

    with_fake_twilio(fake) { get admin_sms_management_twilio_path }

    assert_response :success
    assert_select "turbo-frame#sms-twilio" do
      assert_select "dd", text: /Black Rock Rangers/
      assert_select "dd", text: /412\.37 USD/
      assert_select "dd", text: /Ranger Alerts/
      assert_select "dd", text: %r{/Services/IS…3210 was not found \(Twilio error 20404\)}
      assert_select ".badge", text: "1 undelivered"
      assert_select "td", text: "Message filtered"
      assert_select "a[href=?][target=_blank]", "https://www.twilio.com/docs/api/errors/30007", text: "30007"
      assert_select "a[href=?]", admin_sms_management_twilio_path(refresh: 1), text: /Refresh/
      # The change would stop at the service Twilio cannot find, so it is not offered.
      assert_select "form[action=?]", admin_sms_management_incoming_path, 0
      assert_select "p", text: /Twilio could not read every Notify service above/
    end
    assert_not_includes response.body, "ISfedcba9876543210fedcba9876543210"
  end
end
