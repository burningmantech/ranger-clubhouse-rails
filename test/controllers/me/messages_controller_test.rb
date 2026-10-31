# frozen_string_literal: true

require "test_helper"
# turbo-rails includes it into every test case only once Action Cable has loaded,
# which can be after this file is read.
require "turbo/broadcastable/test_helper"

class Me::MessagesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include GroupMessageTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @sender = person(:active_ranger)
    @recipient = person(:ranger_with_custom_gender)
    @prospective = person(:prospective_ranger)

    # Ensure recipients have last_seen_at set (required for messaging_permitted?)
    @recipient.update!(last_seen_at: 1.day.ago)
    @prospective.update!(last_seen_at: 1.day.ago)

    sign_in_as(@sender)
    # Ensure Current.person is set for controller actions
    Current.person = @sender
    Current.roles_manager = RoleManager.retrieve(@sender)
  end

  # Index action tests
  test "should get index when authenticated" do
    get me_messages_path
    assert_response :success
  end

  test "should redirect to login when not authenticated" do
    sign_out
    get me_messages_path
    assert_redirected_to root_path
  end

  test "should display inbox folder by default" do
    get me_messages_path
    assert_response :success
    assert_select "div", text: /Messages/
  end

  test "should filter messages by folder" do
    # Create test messages
    sent_message = create_message(@sender, @recipient, "Sent Message", "Body")
    received_message = create_message(@recipient, @sender, "Received Message", "Body")

    get me_messages_path(folder: PersonMessage::FOLDER_INBOX)
    assert_response :success

    get me_messages_path(folder: PersonMessage::FOLDER_SENT), as: :turbo_stream
    assert_response :success

    get me_messages_path(folder: PersonMessage::FOLDER_ARCHIVED), as: :turbo_stream
    assert_response :success

    get me_messages_path(folder: PersonMessage::FOLDER_UNREAD), as: :turbo_stream
    assert_response :success
  end

  test "inbox sorts by most recent activity, not unread first" do
    older_unread = create_message(@recipient, @sender, "Older Unread", "Body")
    newer_read = create_message(@recipient, @sender, "Newer Read", "Body")
    older_unread.update_columns(created_at: 2.hours.ago)
    newer_read.update_columns(created_at: 1.hour.ago)
    newer_read.mark_thread_read!(@sender.id)

    inbox_ids = PersonMessage.retrieve_for_person(@sender.id, PersonMessage::FOLDER_INBOX).map(&:id)
    assert_equal [newer_read.id, older_unread.id], inbox_ids & [newer_read.id, older_unread.id]
  end

  test "should normalize invalid folder to inbox" do
    get me_messages_path(folder: "invalid_folder")
    assert_response :success
  end

  test "should handle turbo_stream request for folder change" do
    get me_messages_path(folder: PersonMessage::FOLDER_SENT), as: :turbo_stream
    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
  end

  test "index with to opens the compose page addressed to it" do
    get me_messages_path(to: @recipient.callsign)
    assert_redirected_to new_me_message_path(to: @recipient.callsign)
  end

  test "index cuts a to longer than any callsign before echoing it" do
    get me_messages_path(to: "a" * 6000)
    assert_redirected_to new_me_message_path(to: "a" * Person::CALLSIGN_MAX_LENGTH)
  end

  test "new with to fills in the recipient" do
    get new_me_message_path(to: @recipient.callsign.downcase)
    assert_response :success
    assert_select "#message_form_callsigns_chips input[type=hidden][name='message_form[callsigns][]'][value=?]", @recipient.callsign
    assert_select "#form-error-summary", count: 0
  end

  test "every compose step refuses an unknown or unmessageable callsign in the same words" do
    @prospective.update!(last_seen_at: nil)

    ["NonexistentCallsign", person(:deceased_ranger).callsign, @prospective.callsign].each do |callsign|
      get new_me_message_path(to: callsign)
      assert_response :success
      assert_select "#form-error-summary", text: /You can't message that callsign\. Use Find Recipient to choose someone\./
      assert_select "#message_form_callsigns_chips input", count: 0

      post select_callsign_me_messages_path, params: { callsign: }, as: :turbo_stream
      assert_match ERB::Util.h("You can't message that callsign."), response.body

      post me_messages_path, params: { message_form: { callsigns: [callsign], subject: "Subject", body: "Body" } }
      assert_select "#form-error-summary", text: /You can't message that callsign\./
    end
  end

  test "to names the exact callsign, never one of two that normalize alike" do
    @recipient.update!(callsign: "Fire Fly")
    @prospective.update!(callsign: "Fire-Fly")

    get new_me_message_path(to: "Fire Fly")
    assert_select "#message_form_callsigns_chips input[name='message_form[callsigns][]'][value=?]", "Fire Fly"

    get new_me_message_path(to: "firefly")
    assert_select "#message_form_callsigns_chips input", count: 0
  end

  test "to with nothing left once normalized matches no one" do
    @recipient.update!(callsign: "日本") # normalizes to ""

    get new_me_message_path(to: "!!!")
    assert_select "#message_form_callsigns_chips input", count: 0

    get new_me_message_path(to: "日本")
    assert_select "#message_form_callsigns_chips input[name='message_form[callsigns][]'][value=?]", "日本"
  end

  test "only a mailbox user can start a message, but anyone can read theirs" do
    auditor = person(:auditor_ranger)
    sign_out
    sign_in_as(auditor)

    get me_messages_path
    assert_response :success

    get new_me_message_path(to: @recipient.callsign)
    assert_redirected_to me_root_path

    post select_callsign_me_messages_path, params: { callsign: @recipient.callsign }, as: :turbo_stream
    assert_redirected_to me_root_path

    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Subject", body: "Body" } }
    end
    assert_redirected_to me_root_path
  end

  test "to that is not a single value is refused" do
    get me_messages_path(to: ["a", "b"])
    assert_response :bad_request

    get new_me_message_path(to: { x: "y" })
    assert_response :bad_request
  end

  test "to or callsign that is not a String is refused without an error page" do
    body = { to: 123 }.to_json
    get new_me_message_path, headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "text/html" },
                             env: { "rack.input" => StringIO.new(body), "CONTENT_LENGTH" => body.bytesize.to_s }
    assert_response :success
    assert_select "#form-error-summary", text: /You can't message that callsign\./

    post select_callsign_me_messages_path, params: { callsign: ["a"] }, as: :turbo_stream
    assert_response :success
    assert_match ERB::Util.h("You can't message that callsign."), response.body
  end

  # Show action tests
  test "should show message when authenticated and authorized" do
    message = create_message(@sender, @recipient, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success
  end

  test "should render show page for HTML request" do
    message = create_message(@sender, @recipient, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success
  end

  test "should mark message as read when shown" do
    message = create_message(@recipient, @sender, "Unread Message", "Body")
    assert_not message.read?(@sender.id)

    get me_message_path(message)
    assert_response :success

    message.reload
    assert message.read?(@sender.id)
  end

  test "should redirect when showing message user is not authorized to view" do
    other_person = person(:prospective_ranger)
    message = create_message(@recipient, other_person, "Private Message", "Body")

    get me_message_path(message)
    assert_redirected_to me_messages_path
    assert_match(/Invalid message id/i, flash[:error].to_s)
  end

  test "should redirect when showing reply message instead of thread top" do
    parent_message = create_message(@sender, @recipient, "Parent", "Body")
    reply_message = create_message(@sender, @recipient, "Re: Parent", "Reply", reply_to_id: parent_message.id)

    get me_message_path(reply_message)
    assert_redirected_to me_messages_path
    assert_match(/not thread top/i, flash[:error].to_s)
  end

  test "should redirect when message not found" do
    get me_message_path(999999)
    assert_redirected_to me_messages_path
    assert_match(/not found/i, flash[:error].to_s)
  end

  test "should handle HTML request for show" do
    message = create_message(@sender, @recipient, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success
    assert_match %r{text/html}, response.content_type
  end

  # Toggle read tests
  test "should toggle read status for recipient" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")
    assert_not message.read?(@sender.id)

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_response :success

    message.reload
    assert message.read?(@sender.id)
  end

  test "should toggle read status for sender" do
    message = create_message(@sender, @recipient, "Test Subject", "Test Body")
    # A sent thread marked unread: never read, though its one row is the sender's own.
    assert_equal false, message.toggle_thread_read!(@sender.id)
    assert_not message.reload.thread_read?(@sender.id)

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_response :success

    message.reload
    assert message.thread_read?(@sender.id)
  end

  test "should round-trip read status and report both directions" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")
    assert_not message.read?(@sender.id)

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_response :success
    assert_match(/marked as read/i, response.body)
    message.reload
    assert message.read?(@sender.id)

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_response :success
    assert_match(/marked as unread/i, response.body)
    message.reload
    assert_not message.read?(@sender.id)
  end

  test "Mark Read and Mark Unread replace the navbar envelope with the new count" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=navbar-messages] template" do
      assert_select "span#navbar-messages[hidden]"
    end

    post toggle_read_me_message_path(message), as: :turbo_stream
    assert_select "turbo-stream[action=replace][target=navbar-messages] template" do
      assert_select "#navbar-messages a[aria-label=?]", "1 unread message"
    end
  end

  test "should reject toggle_read for a message between two other people" do
    other_message = create_message(@recipient, @prospective, "Private", "Body")

    post toggle_read_me_message_path(other_message), as: :turbo_stream
    assert_redirected_to me_messages_path
    assert_match(/Invalid message id/i, flash[:error].to_s)

    other_message.reload
    assert_not other_message.thread_read?(@prospective.id)
  end

  test "should redirect toggle_read when message not found" do
    post toggle_read_me_message_path(999999), as: :turbo_stream
    assert_redirected_to me_messages_path
    assert_match(/not found/i, flash[:error].to_s)
  end

  # Toggle archive tests
  test "should toggle archive status for recipient" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")
    assert_not message.archived?(@sender.id)

    post toggle_archive_me_message_path(message), as: :turbo_stream
    assert_response :success

    message.reload
    assert message.archived?(@sender.id)
  end

  test "should toggle archive status for sender" do
    message = create_message(@sender, @recipient, "Test Subject", "Test Body")
    assert_not message.archived?(@sender.id)

    post toggle_archive_me_message_path(message), as: :turbo_stream
    assert_response :success

    message.reload
    assert message.archived?(@sender.id)
  end

  test "should round-trip archive status and report both directions" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")
    assert_not message.archived?(@sender.id)

    post toggle_archive_me_message_path(message), as: :turbo_stream
    assert_response :success
    assert_match(/archived/i, response.body)
    message.reload
    assert message.archived?(@sender.id)

    post toggle_archive_me_message_path(message), as: :turbo_stream
    assert_response :success
    assert_match(/moved to inbox/i, response.body)
    message.reload
    assert_not message.archived?(@sender.id)
  end

  test "should reject toggle_archive for a message between two other people" do
    other_message = create_message(@recipient, @prospective, "Private", "Body")

    post toggle_archive_me_message_path(other_message), as: :turbo_stream
    assert_redirected_to me_messages_path
    assert_match(/Invalid message id/i, flash[:error].to_s)

    other_message.reload
    assert_not other_message.archived?(@prospective.id)
    assert_not other_message.archived?(@recipient.id)
  end

  test "should redirect toggle_archive when message not found" do
    post toggle_archive_me_message_path(999999), as: :turbo_stream
    assert_redirected_to me_messages_path
    assert_match(/not found/i, flash[:error].to_s)
  end

  # New action tests
  test "should show new message form" do
    get new_me_message_path
    assert_response :success
    assert_match %r{text/html}, response.content_type
    # Compose keeps the editor's full starting height; only the reply box is short.
    assert_select "lexxy-editor[name='message_form[body]']:not(.messages-reply-editor)"
  end

  # Find recipient tests
  test "should show find recipient modal" do
    get find_recipient_me_messages_path, as: :turbo_stream
    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
  end

  # Search callsigns tests
  test "should search for callsigns" do
    post search_callsigns_me_messages_path, params: {
      find_recipient_form: { query: @recipient.callsign }
    }, as: :turbo_stream

    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
  end

  test "should return error for invalid search query" do
    post search_callsigns_me_messages_path, params: {
      find_recipient_form: { query: "X" }
    }, as: :turbo_stream

    assert_response :success
  end

  test "should return error when no callsigns match" do
    post search_callsigns_me_messages_path, params: {
      find_recipient_form: { query: "NonexistentCallsign12345" }
    }, as: :turbo_stream

    assert_response :success
  end

  # Select callsign tests
  test "should select valid callsign" do
    post select_callsign_me_messages_path, params: {
      callsign: @recipient.callsign
    }, as: :turbo_stream

    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
    # The choice joins the recipients chip field.
    assert_select "turbo-stream[action=append][target=message_form_callsigns_chips] template " \
                  "input[name='message_form[callsigns][]'][value=?]", @recipient.callsign
    # An error about the recipient it replaces must not outlive the choice.
    assert_select "turbo-stream[action=remove][target=form-error-summary]"
  end

  test "the chip field's suggestions are the callsigns a send accepts, as autocomplete JSON" do
    @prospective.update!(last_seen_at: nil)

    get suggest_callsigns_me_messages_path(q: "custom"), as: :json
    assert_response :success
    assert_equal [@recipient.callsign], response.parsed_body["items"].pluck("value")
    assert_equal response.parsed_body["items"].pluck("id"), response.parsed_body["flat_item_ids"]

    get suggest_callsigns_me_messages_path(q: "prospective"), as: :json
    assert_empty response.parsed_body["items"]
    assert_equal "No callsigns matched.", response.parsed_body["empty_text"]

    get suggest_callsigns_me_messages_path(q: ["custom"]), as: :json
    assert_empty response.parsed_body["items"]
  end

  # The warning the relay's old lookup showed for a chosen party, now where any
  # party is chosen.
  test "a suggestion warns of someone who has not logged in for over two years" do
    get suggest_callsigns_me_messages_path(q: "custom"), as: :json
    assert_no_match "logged in", response.parsed_body["items"].first["html"]

    @recipient.update!(last_seen_at: 3.years.ago)
    get suggest_callsigns_me_messages_path(q: "custom"), as: :json
    html = Nokogiri::HTML5.fragment(response.parsed_body["items"].first["html"]).text.squish
    assert_includes html, "Hasn't logged in for over 2 years. They may not receive notifications."
  end

  test "compose offers the chips, Find Recipient for a phone and the Cadres and Delegations" do
    get new_me_message_path

    # The visible label names the input: an aria-label would outrank it (review finding 13).
    assert_select "label[for=message_form_callsigns]", text: "To"
    assert_select "[data-controller=callsign-chips]:not([data-callsign-chips-max-value]) " \
                  "input#message_form_callsigns:not([aria-label])[aria-describedby=message_form_callsigns_hint]"
    # Its hint says several callsigns and a Cadre or Delegation can go together.
    assert_select "#message_form_callsigns_hint", text: /up to 25, and choose a Cadre or Delegation below as well or instead/
    assert_select "[data-controller=callsign-chips] template button[aria-label]"
    assert_select ".lg\\:hidden a", text: "Find Recipient"
    assert_select "details summary", text: /Send to a Cadre or Delegation/
    assert_select "select[name='message_form[team_id]'] option", text: teams(:green_dot_cadre).title
    assert_select "select[name='message_form[team_id]'] option", text: teams(:dirt_team).title, count: 0
  end

  test "should handle blank callsign selection" do
    post select_callsign_me_messages_path, params: {
      callsign: ""
    }, as: :turbo_stream

    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
  end

  test "should return error for invalid callsign" do
    post select_callsign_me_messages_path, params: {
      callsign: "NonexistentCallsign12345"
    }, as: :turbo_stream

    assert_response :success
  end

  test "should return error for deceased person" do
    deceased = person(:deceased_test)

    post select_callsign_me_messages_path, params: {
      callsign: deceased.callsign
    }, as: :turbo_stream

    assert_response :success
  end

  test "should return error for non-messagable person" do
    bonked = person(:bonked_ranger)
    # Ensure bonked person has last_seen_at but status prevents messaging
    bonked.update!(last_seen_at: 1.day.ago)

    post select_callsign_me_messages_path, params: {
      callsign: bonked.callsign
    }, as: :turbo_stream

    assert_response :success
  end

  # Create action tests
  test "should create message with valid data" do
    assert_difference "PersonMessage.count", 1 do
      post me_messages_path, params: {
        message_form: {
          callsigns: [@recipient.callsign],
          subject: "Test Subject",
          body: "Test Body"
        }
      }
    end

    message = PersonMessage.last
    assert_redirected_to me_message_path(message)
    assert_equal "Message sent.", flash[:notice]
    assert_equal @recipient.id, message.person_id
    assert_equal @sender.id, message.sender_person_id
    assert_equal "Test Subject", message.subject
    assert_equal "Test Body", message.body
  end

  # No form has sent callsign_selected since the chip field; one sent anyway
  # held the message back with no error to say why.
  test "a stray callsign_selected does not hold a message back" do
    assert_difference "PersonMessage.count", 1 do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Subject", body: "Body",
                                                       callsign_selected: "1" } }
    end
    assert_redirected_to me_message_path(PersonMessage.last)
  end

  # Rich text (messaging rework, slice 4): the editor's HTML is what is kept,
  # read formatted, and its text alone is what a text or an email carries.
  test "a message written in the editor is kept as HTML, read formatted, and notified as text" do
    body = "<p>Bring the <strong>spare</strong> ones.</p><p>Thanks!</p>"
    calls = capture_message_notify_calls do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Batteries", body: } }
    end

    message = PersonMessage.last
    assert_equal body, message.body
    assert_equal [[@recipient.id, "Batteries", "Bring the spare ones.\nThanks!"]], calls

    get me_message_path(message)
    assert_select "article .lexxy-content strong", text: "spare"
  end

  test "a plain body still reads as text, with its line breaks and links, and a less-than sign kept" do
    message = create_message(@recipient, @sender, "Old style", "I <3 Outpost, a < b\nSee https://example.org")

    get me_message_path(message)
    assert_select "article .lexxy-content", count: 0
    assert_select "article a[href='https://example.org']"
    assert_includes response.body, "I &lt;3 Outpost, a &lt; b<br>"
  end

  test "the editor's HTML is sanitized when it is read" do
    message = create_message(@recipient, @sender, "Crafted", %(<p>Hi<script>alert(1)</script><img src="x" onerror="alert(1)"></p>))

    get me_message_path(message)
    assert_select "article script", count: 0
    assert_not_includes response.body, "onerror"
  end

  test "the length limit counts the text, not the markup, and says how long the message is" do
    assert_difference "PersonMessage.count", 1 do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Long",
                                                       body: "<p><strong>#{"x" * 4000}</strong></p>" } }
    end

    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Long",
                                                       body: "<p>#{"x" * 4001}</p>" } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Your message is 4,001 characters long. Shorten it to 4,000 or fewer."
  end

  # Live arrival (PersonMessage#announce_to_recipient): the recipient's open
  # pages get the envelope's new count and one line for a screen reader.
  test "sending a message updates the recipient's navbar live, and only theirs" do
    streams = nil
    assert_no_turbo_stream_broadcasts @sender do
      streams = capture_turbo_stream_broadcasts @recipient do
        post me_messages_path, params: {
          message_form: { callsigns: [@recipient.callsign], subject: "Shift swap", body: "Thursday?" }
        }
      end
    end

    assert_equal [%w[replace navbar-messages], %w[append live-region]],
                 streams.map { |stream| [stream["action"], stream["target"]] }
    assert_equal "1 unread message", streams.first.at_css("a")["aria-label"]
    assert_equal "#{@sender.callsign} sent you a message.", streams.last.text.strip
  end

  test "a reply updates the other party's navbar live" do
    parent = create_message(@recipient, @sender, "Parent Subject", "Parent Body")

    # Captured, not assert_no_turbo_stream_broadcasts: that counts every
    # broadcast the stream has had, and creating the thread announced it to
    # @sender before the reply.
    mine = nil
    streams = capture_turbo_stream_broadcasts @recipient do
      mine = capture_turbo_stream_broadcasts @sender do
        post create_reply_me_message_path(parent), params: { message_reply_form: { reply: "Yes" } },
                                                   as: :turbo_stream
      end
    end

    assert_empty mine
    assert_equal %w[navbar-messages live-region], streams.map { |stream| stream["target"] }
  end

  test "a note to self and a message to someone the mailbox is not for announce nothing" do
    assert_no_turbo_stream_broadcasts @sender do
      create_message(@sender, @sender, "Reminder", "Pack goggles")
    end

    assert_no_turbo_stream_broadcasts @prospective do
      post me_messages_path, params: {
        message_form: { callsigns: [@prospective.callsign], subject: "Welcome", body: "Hello" }
      }
    end
    assert_equal @prospective.id, PersonMessage.last.person_id
  end

  test "a live announcement that fails is logged, and the message is still sent" do
    original = Turbo::StreamsChannel.method(:broadcast_render_to)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_render_to) do |*, **|
      raise ActiveRecord::StatementInvalid, "cable table unreachable"
    end

    assert_difference "PersonMessage.count", 1 do
      post me_messages_path, params: {
        message_form: { callsigns: [@recipient.callsign], subject: "Shift swap", body: "Thursday?" }
      }
    end

    message = PersonMessage.last
    assert_redirected_to me_message_path(message)
    log = ErrorLog.order(:id).last
    assert_equal "message-announce-exception", log.error_type
    assert_equal message.id, log.data["person_message_id"]
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_render_to, original)
  end

  # Review finding 11: announce_reply's reload of the thread ran outside the
  # rescue, so its error left save, after the reply's commit.
  test "a reply whose live announcement cannot load its thread is still sent, notified and logged" do
    top = create_message(@recipient, @sender, "Radios", "Who has them?")
    original = PersonMessage.method(:includes)
    PersonMessage.define_singleton_method(:includes) do |*args, **kwargs|
      # announce_reply's load alone preloads the sender's photo.
      raise ActiveRecord::StatementInvalid, "lost the connection" if kwargs.key?(:sender_person)

      original.call(*args, **kwargs)
    end

    notified = nil
    assert_difference -> { ErrorLog.where(error_type: "message-announce-exception").count } => 1 do
      notified = capture_message_notifies do
        post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On my way." } }, as: :turbo_stream
      end
    end

    assert_response :success
    reply = PersonMessage.order(:id).last
    assert_equal top.id, reply.reply_to_id
    assert_equal [@recipient.id], notified
    assert_equal reply.id, ErrorLog.order(:id).last.data["person_message_id"]
  ensure
    PersonMessage.define_singleton_method(:includes, original)
  end

  test "should require callsign" do
    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: {
        message_form: {
          callsigns: [""],
          subject: "Test Subject",
          body: "Test Body"
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "should require subject" do
    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: {
        message_form: {
          callsigns: [@recipient.callsign],
          subject: "",
          body: "Test Body"
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "should require body" do
    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: {
        message_form: {
          callsigns: [@recipient.callsign],
          subject: "Test Subject",
          body: ""
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "should reject invalid recipient" do
    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: {
        message_form: {
          callsigns: ["NonexistentCallsign"],
          subject: "Test Subject",
          body: "Test Body"
        }
      }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  # Create reply tests
  test "should create reply to message" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")

    assert_difference "PersonMessage.count", 1 do
      post create_reply_me_message_path(parent_message), params: {
        message_reply_form: {
          reply: "This is a reply"
        }
      }, as: :turbo_stream
    end

    assert_response :success
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type

    reply = PersonMessage.last
    assert_equal parent_message.id, reply.reply_to_id
    assert_equal "Parent Subject", reply.subject
    assert_equal "This is a reply", reply.body
  end

  test "should reject create_reply for a thread between two other people" do
    other_thread = create_message(@recipient, @prospective, "Private Thread", "Body")

    assert_no_difference "PersonMessage.count" do
      post create_reply_me_message_path(other_thread), params: {
        message_reply_form: {
          reply: "Injected reply"
        }
      }, as: :turbo_stream
    end

    assert_redirected_to me_messages_path
    assert_match(/Invalid message id/i, flash[:error].to_s)
  end

  test "should require reply body" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")

    assert_no_difference "PersonMessage.count" do
      post create_reply_me_message_path(parent_message), params: {
        message_reply_form: {
          reply: ""
        }
      }, as: :turbo_stream
    end

    assert_response :success
    # An empty reply must re-render the reply form turbo-stream, not swallow the
    # error and return an unrelated stream.
    assert_match %r{text/vnd\.turbo-stream\.html}, response.content_type
    assert_match(/messages-reply-form/, response.body)
  end

  test "should reject reply to a non-thread-top message" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")
    reply_message = create_message(@sender, @recipient, "Parent Subject", "A reply",
                                   reply_to_id: parent_message.id)

    assert_no_difference "PersonMessage.count" do
      post create_reply_me_message_path(reply_message), params: {
        message_reply_form: {
          reply: "Reply to a reply"
        }
      }, as: :turbo_stream
    end

    assert_redirected_to me_messages_path
    assert_match(/not thread top/i, flash[:error].to_s)
  end

  test "should handle reply when user is sender" do
    parent_message = create_message(@sender, @recipient, "Parent Subject", "Parent Body")

    assert_difference "PersonMessage.count", 1 do
      post create_reply_me_message_path(parent_message), params: {
        message_reply_form: {
          reply: "Reply from sender"
        }
      }, as: :turbo_stream
    end

    assert_response :success

    reply = PersonMessage.last
    assert_equal @recipient.id, reply.person_id
  end

  test "should handle reply when user is recipient" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")

    assert_difference "PersonMessage.count", 1 do
      post create_reply_me_message_path(parent_message), params: {
        message_reply_form: {
          reply: "Reply from recipient"
        }
      }, as: :turbo_stream
    end

    assert_response :success

    reply = PersonMessage.last
    assert_equal @recipient.id, reply.person_id
  end

  test "should refuse replies to broadcast, walk-up and team messages with an error" do
    [PersonMessage::SENDER_TYPE_RBS, PersonMessage::SENDER_TYPE_OTHER, PersonMessage::SENDER_TYPE_TEAM].each do |sender_type|
      message = create_senderless(@sender, sender_type)

      assert_no_difference "PersonMessage.count" do
        post create_reply_me_message_path(message), params: {
          message_reply_form: {
            reply: "Attempted reply"
          }
        }, as: :turbo_stream
      end

      assert_response :success
      assert_includes response.body, "form-error-summary"
      assert_includes response.body, "This message cannot be replied to."
    end
  end

  test "a reply the message model refuses comes back with its errors" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")
    @recipient.update_column(:status, Person::RESIGNED)

    assert_no_difference "PersonMessage.count" do
      post create_reply_me_message_path(parent_message), params: {
        message_reply_form: {
          reply: "Reply after they resigned"
        }
      }, as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, "#{@recipient.callsign} has a status that does not allow messages."
    assert_includes response.body, "Reply after they resigned"
  end

  # View content tests
  test "index should render hero panel with chat title" do
    get me_messages_path
    assert_response :success
    assert_select "h1", text: /Messages/
  end

  test "index should render new message button" do
    get me_messages_path
    assert_response :success
    assert_match(/Write Message/, response.body)
  end

  test "a thread's page offers Write Message too" do
    message = create_message(@recipient, @sender, "Radios", "Who has them?")
    get me_message_path(message)
    assert_select "a[href='#{new_me_message_path}']", text: "Write Message"
  end

  test "index should render folder tabs" do
    get me_messages_path
    assert_response :success
    assert_select "[role='tab']", minimum: 4 # Inbox, Unread, Sent, Archived
  end

  test "index should render back to dashboard link" do
    get me_messages_path
    assert_response :success
    assert_match(/Clubhouse Dashboard/i, response.body)
  end

  test "index should render unread count when messages exist" do
    create_message(@recipient, @sender, "Unread 1", "Body")
    create_message(@recipient, @sender, "Unread 2", "Body")

    # Pin the authoritative count path: two thread-tops addressed to @sender,
    # unread, not self-sent.
    assert_equal 2, PersonMessage.count_unread(@sender.id)

    get me_messages_path
    assert_response :success
    # The Unread tab badge carries the concrete number; "unread" alone also
    # matches the static tab and "Mark as unread" labels.
    assert_select "a[role=tab] span.badge-warning", text: "2"
  end

  test "unread counts broadcasts and walk-ups, not expired or self-sent messages" do
    broadcast = create_senderless(@sender, PersonMessage::SENDER_TYPE_RBS, expires_at: Current.time + 1.day)
    walk_up = create_senderless(@sender, PersonMessage::SENDER_TYPE_OTHER)
    create_senderless(@sender, PersonMessage::SENDER_TYPE_RBS, expires_at: Current.time - 1.minute)
    create_senderless(@recipient, PersonMessage::SENDER_TYPE_RBS)
    create_message(@sender, @sender, "Note to self", "Body")

    assert_unread_threads(broadcast, walk_up)
  end

  test "a reply addressed to the owner makes the thread unread until it is opened" do
    thread = create_message(@sender, @recipient, "Started by me", "Body")
    create_message(@recipient, @sender, "Started by me", "Their reply", reply_to_id: thread.id)
    create_message(@recipient, @sender, "Started by me", "Their follow-up", reply_to_id: thread.id)

    # One thread, however many of its replies are unread.
    assert_unread_threads(thread)

    get me_messages_path
    assert_select "a[role=tab] span.badge-warning", text: "1"
    assert_select "a.messages-conversation-unread .badge", text: "New Reply"

    get me_message_path(thread)
    assert_unread_threads
  end

  # HQ and /person never mark a thread read on view, so the toggle alone has
  # to clear the replies or their unread count could never drop.
  test "mark read clears the replies addressed to the owner, mark unread flags the thread again" do
    thread = create_message(@sender, @recipient, "Started by me", "Body")
    reply = create_message(@recipient, @sender, "Started by me", "Their reply", reply_to_id: thread.id)

    post toggle_read_me_message_path(thread), as: :turbo_stream
    assert_match(/marked as read/i, response.body)
    assert_match(/aria-label="Mark as unread"/, response.body)
    assert reply.reload.read?(@sender.id)
    assert_unread_threads

    post toggle_read_me_message_path(thread), as: :turbo_stream
    assert_match(/marked as unread/i, response.body)
    assert_unread_threads(thread)
  end

  test "a thread the owner sent and marked unread counts as unread" do
    thread = create_message(@sender, @recipient, "Sent by me", "Body")
    assert_unread_threads

    post toggle_read_me_message_path(thread), as: :turbo_stream
    assert_match(/marked as unread/i, response.body)
    assert_unread_threads(thread)
  end

  test "mark unread and mark read both take effect on a note to self" do
    note = create_message(@sender, @sender, "Note to self", "Body")

    post toggle_read_me_message_path(note), as: :turbo_stream
    assert_match(/marked as unread/i, response.body)
    assert_match(/aria-label="Mark as read"/, response.body)
    assert_unread_threads(note)

    post toggle_read_me_message_path(note), as: :turbo_stream
    assert_match(/marked as read/i, response.body)
    assert_match(/aria-label="Mark as unread"/, response.body)
    assert_unread_threads
  end

  test "show should render message content" do
    message = create_message(@recipient, @sender, "Test Subject", "Message Body Content")

    get me_message_path(message)
    assert_response :success

    assert_match(/Message Body Content/, response.body)
  end

  test "show should render reply form for person message" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success

    # Should have reply form
    assert_match(/reply/i, response.body)
  end

  test "show should render action buttons" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success

    # Should have action buttons
    assert_match(/Mark.*Read/i, response.body)
    assert_match(/Archive/i, response.body)
  end

  test "show should render back button" do
    message = create_message(@recipient, @sender, "Test Subject", "Test Body")

    get me_message_path(message)
    assert_response :success

    assert_match(/Back to Messages/i, response.body)
  end

  # Message with replies view tests
  test "show should render all replies in thread" do
    parent_message = create_message(@recipient, @sender, "Parent Subject", "Parent Body")
    reply1 = create_message(@sender, @recipient, "Parent Subject", "Reply 1", reply_to_id: parent_message.id)
    reply2 = create_message(@recipient, @sender, "Parent Subject", "Reply 2", reply_to_id: parent_message.id)

    get me_message_path(parent_message)
    assert_response :success

    assert_match(/Parent Body/, response.body)
    assert_match(/Reply 1/, response.body)
    assert_match(/Reply 2/, response.body)
  end

  # Broadcast message view tests
  test "show should display broadcast message without reply form" do
    message = PersonMessage.create!(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: @sender.id,
      creator_person_id: @recipient.id,
      sender_person_id: @recipient.id,
      sender_type: PersonMessage::SENDER_TYPE_RBS,
      subject: "Broadcast Subject",
      body: "Broadcast Body"
    )

    get me_message_path(message)
    assert_response :success

    assert_match(/broadcast/i, response.body)
    assert_match(/cannot be\s+replied/i, response.body)
    assert_select "#messages-reply-form [role=status]", text: /Broadcast message\./
    # Nothing can be replied to it, so the thread listens for no replies.
    assert_select "#messages-pane turbo-cable-stream-source", count: 0
    assert_select "#messages-thread[data-controller]", count: 0
  end

  test "show should display walk-up message without reply form" do
    message = PersonMessage.create!(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: @sender.id,
      creator_person_id: @recipient.id,
      sender_type: PersonMessage::SENDER_TYPE_OTHER,
      message_from: "HQ Window Visitor",
      subject: "Walk-up Subject",
      body: "Walk-up Body"
    )

    get me_message_path(message)
    assert_response :success

    assert_select "#messages-reply-form [role=status]", text: /No Clubhouse sender\./
    assert_select "#messages-reply-form form", count: 0
  end

  # Team message view tests
  test "show should display team message with team icon and without reply form" do
    message = create_senderless(@sender, PersonMessage::SENDER_TYPE_TEAM)

    get me_message_path(message)
    assert_response :success

    # Should show team icon
    assert_match(/people-group/, response.body)
    assert_select "#messages-reply-form [role=status]", text: /Team message\./
    assert_select "#messages-reply-form [role=status] .fa-people-group"
    assert_select "#messages-reply-form a[href='mailto:council@rangers.example.com']"
    assert_select "#messages-reply-form form", count: 0
  end

  # Message expiration view test
  test "show should display expiration warning for expired messages" do
    message = create_message(@recipient, @sender, "Expired Subject", "Expired Body")
    # Set expiration in the past
    message.update_column(:expires_at, 1.day.ago)

    get me_message_path(message)
    assert_response :success

    assert_match(/expired/i, response.body)
  end

  # An expired broadcast is not counted unread (unread_for_person), so nothing
  # may call it New either: not its row, its card, or a read toggle that could
  # change nothing anyone sees. Opening it writes nothing.
  test "an expired broadcast reads as read in the list and the thread" do
    expired = create_senderless(@sender, PersonMessage::SENDER_TYPE_RBS, expires_at: Current.time - 1.minute)
    assert_unread_threads

    get me_messages_path
    row = "a[href^='#{me_message_path(expired)}']"
    assert_select row, count: 1
    assert_select "#{row}.messages-conversation-unread", count: 0
    assert_select "#{row} .badge-warning", count: 0

    assert_no_changes -> { expired.member(@sender.id).reload.last_read_message_id } do
      get me_message_path(expired)
    end
    assert_response :success
    assert_select "#messages-thread article.bg-warning\\/10", count: 0
    assert_select "#messages-thread .badge-warning", text: "New", count: 0
    assert_select "form#messages-toggle-read", count: 0
    assert_select "form#messages-toggle-archive"
  end

  # --- The Mail Desk workspace (.scratch/messaging-rework/PRD.md, slice 1) --------

  test "index renders the list beside a pane that waits for a selection" do
    create_message(@recipient, @sender, "Waiting", "Body")

    get me_messages_path
    assert_response :success
    assert_select "[data-controller=review-pane] a.review-line[data-turbo-frame=messages-pane]", count: 1
    assert_select "a.review-line[aria-current]", count: 0
    assert_select "turbo-frame#messages-pane .empty-state", text: /Select a conversation to read it here\./
    # Disabled until review_pane_controller enables it from lg up: a row's link
    # is a page visit on a phone, and before the controller loads.
    assert_select "turbo-frame#messages-pane[disabled]"
  end

  test "show renders the thread in the pane beside a list that loads itself" do
    message = create_message(@recipient, @sender, "Selected", "Body")

    get me_message_path(message)
    assert_response :success
    assert_select "turbo-frame#messages-pane[disabled] [data-review-id='#{message.id}'] #messages-thread article", count: 1
    assert_select "#messages-thread article .wrap-anywhere", text: /Body/
    # The list is a lazy frame, which a phone (where the column is hidden) never loads.
    assert_select "turbo-frame#messages-conversation-list[loading=lazy][src=?]",
                  me_messages_path(folder: PersonMessage::FOLDER_INBOX, selected: message.id)
    assert_select "a.review-line", count: 0
    # Focus stays where the reader put it; the reply box takes it only after a send.
    # The reply box starts about four lines tall, not the 16rem every other editor starts at.
    assert_select "lexxy-editor.messages-reply-editor[name='message_reply_form[reply]']"
    assert_select "lexxy-editor[autofocus]", count: 0
  end

  test "the list frame request answers the folder's rows alone, the open thread marked" do
    message = create_message(@recipient, @sender, "Selected", "Body")
    other = create_message(@recipient, @sender, "Other", "Body")

    get me_messages_path(folder: PersonMessage::FOLDER_INBOX, selected: message.id),
        headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_response :success
    assert_select "h1", count: 0
    assert_select "turbo-frame#messages-conversation-list a.review-line[aria-current=true]", count: 1
    assert_select "a.review-line[aria-current=true][href=?]", me_message_path(message, folder: PersonMessage::FOLDER_INBOX)
    assert_select "a.review-line[href=?]", me_message_path(other, folder: PersonMessage::FOLDER_INBOX)
  end

  test "a pane frame request answers the pane alone and still marks the thread read" do
    message = create_message(@recipient, @sender, "Framed", "Body")

    get me_message_path(message), headers: { "Turbo-Frame" => "messages-pane" }
    assert_response :success
    assert_select "turbo-frame#messages-pane [data-review-id='#{message.id}']"
    assert_select "h1", count: 0
    # No page around the pane: the tabs come back only inside a stream's template.
    assert_select "turbo-frame#messages-folder-selector", count: 0
    assert_select "turbo-frame#messages-conversation-list", count: 0
    assert message.reload.thread_read?(@sender.id)

    # What the read changed outside the pane rides inside the frame as streams.
    assert_select "turbo-frame#messages-pane turbo-stream[action=replace][target=navbar-messages] template " \
                  "span#navbar-messages[hidden]"
    # The Unread count alone, hidden at zero: the tab row keeps its active tab.
    assert_select "turbo-frame#messages-pane turbo-stream[action=replace][target=messages-unread-count] " \
                  "template span#messages-unread-count.badge-warning[hidden]", text: "0"
    assert_select "turbo-frame#messages-pane turbo-stream[target=messages-folder-selector]", count: 0
    assert_select "turbo-frame#messages-pane turbo-stream[action=replace][method=morph][target=?] template",
                  "conversation_person_message_#{message.id}" do
      assert_select "a.review-line[aria-current=true]:not(.messages-conversation-unread)"
    end
  end

  test "a pane frame request for a thread already read streams nothing" do
    message = create_message(@recipient, @sender, "Read Already", "Body")
    message.mark_thread_read!(@sender.id)

    get me_message_path(message), headers: { "Turbo-Frame" => "messages-pane" }
    assert_response :success
    assert_select "turbo-stream", count: 0
  end

  test "a pane frame request for a thread that cannot be shown says why in the pane" do
    parent = create_message(@recipient, @sender, "Parent", "Body")
    reply = create_message(@sender, @recipient, "Re: Parent", "Reply", reply_to_id: parent.id)

    get me_message_path(reply), headers: { "Turbo-Frame" => "messages-pane" }
    assert_response :success
    assert_select "turbo-frame#messages-pane [role=status]", text: /not thread top/
    assert_select "turbo-frame#messages-pane [data-review-id]", count: 0

    # A page visit still redirects, notice and all.
    get me_message_path(reply)
    assert_redirected_to me_messages_path
  end

  test "the thread page's back link returns to the folder the thread was opened from" do
    message = create_message(@recipient, @sender, "Folded", "Body")

    get me_message_path(message, folder: PersonMessage::FOLDER_ARCHIVED)
    assert_select "a[aria-label='Back to Messages'][href=?]", me_messages_path(folder: PersonMessage::FOLDER_ARCHIVED)
    # The header's toggles post the folder too, to stream that list back: a field
    # of the tab row's frame, which every change of the list renders anew.
    %w[messages-toggle-read messages-toggle-archive].each do |form|
      assert_select "form##{form} input[name=folder]", count: 0
      assert_select "#messages-folder-selector input[type=hidden][name=folder][form=#{form}][value=?]",
                    PersonMessage::FOLDER_ARCHIVED
    end
    assert_select "form#messages-toggle-read[action=?]", toggle_read_me_message_path(message)
    assert_select "form#messages-toggle-archive[action=?]", toggle_archive_me_message_path(message)
    assert_select "input[type=hidden][name=q]", count: 0

    get me_message_path(message)
    assert_select "a[aria-label='Back to Messages'][href=?]", me_messages_path
  end

  test "Mark Read and Mark Unread stream the list, the tabs and the cards back" do
    message = create_message(@recipient, @sender, "Toggled", "Body")

    post toggle_read_me_message_path(message), params: { folder: PersonMessage::FOLDER_UNREAD }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=messages-folder-selector] template a[role=tab][aria-selected=true]",
                  text: /Unread/
    # Read now, so the Unread folder no longer lists it.
    assert_select "turbo-stream[action=update][target=messages-conversation-list] template a.review-line", count: 0
    # Card by card: a morph of the whole thread would remove a card that landed
    # live after the request loaded it (review finding V10).
    card = "turbo-stream[action=replace][method=morph][target=#{ActionView::RecordIdentifier.dom_id(message, :card)}] template"
    assert_select "#{card} article", count: 1
    assert_select "#{card} .badge", count: 0
    assert_select "turbo-stream[target=messages-thread]", count: 0

    post toggle_read_me_message_path(message), params: { folder: PersonMessage::FOLDER_UNREAD }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=update][target=messages-conversation-list] template " \
                  "a.review-line[aria-current=true][data-review-id=?]", message.id.to_s
    assert_select "#{card} .badge", text: "New"
  end

  test "Archive takes the thread out of the Inbox list beside the pane" do
    archived = create_message(@recipient, @sender, "To Archive", "Body")
    kept = create_message(@recipient, @sender, "To Keep", "Body")

    post toggle_archive_me_message_path(archived), params: { folder: PersonMessage::FOLDER_INBOX }, as: :turbo_stream
    assert_response :success
    list = "turbo-stream[action=update][target=messages-conversation-list] template"
    assert_select "#{list} a.review-line[data-review-id=?]", kept.id.to_s
    assert_select "#{list} a.review-line[data-review-id=?]", archived.id.to_s, count: 0
    # Archiving changes no read state, so the cards are left alone.
    assert_select "turbo-stream[target=#{ActionView::RecordIdentifier.dom_id(archived, :card)}]", count: 0
  end

  test "a reply streams a card onto the thread" do
    message = create_message(@recipient, @sender, "Reply Thread", "Body")

    post create_reply_me_message_path(message), params: { message_reply_form: { reply: "Card body" } }, as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=append][target=messages-thread] template article", text: /Card body/
    # The owner's own reply is read by them, so it carries no New chip.
    assert_select "turbo-stream[action=append][target=messages-thread] template .badge", count: 0
    # The reader was just typing there, so the fresh editor takes focus back.
    assert_select "turbo-stream[action=update][target=messages-reply-form] template lexxy-editor[autofocus][required]"
  end

  # Live replies (slice 5): the open thread subscribes to the owner's view of it,
  # and on /me marks a reply that lands in it read (ruling D6).
  test "the open thread listens for replies, and on /me marks one that lands read" do
    message = create_message(@recipient, @sender, "Live Thread", "Body")

    get me_message_path(message, folder: PersonMessage::FOLDER_SENT)
    assert_select "#messages-pane turbo-cable-stream-source[channel=MailboxStreamsChannel][signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@sender, message])
    # No folder or search of its own: it posts what the list shows when it posts.
    assert_select "#messages-thread[data-controller=thread-live][data-thread-live-url-value=?]",
                  mark_read_me_message_path(message)
    # And the list beside it, whose row and Unread count a reply replaces.
    assert_select "turbo-cable-stream-source[channel=MailboxStreamsChannel][signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@sender, :messages, "me"])
    # Opening a thread here reads it, so there is no unread round to go through.
    assert_select "a", text: /Next Unread|Back to Messages/, count: 0
  end

  test "mark read is idempotent and answers what opening the thread would have changed" do
    message = create_message(@recipient, @sender, "Live Thread", "Body")
    reply = create_message(@recipient, @sender, "Live Thread", "Landed", reply_to_id: message.id)
    assert_unread_threads message

    2.times do
      post mark_read_me_message_path(message, folder: PersonMessage::FOLDER_INBOX), as: :turbo_stream
      assert_response :success
      assert reply.reload.read?(@sender.id)
      assert_equal [%w[replace navbar-messages], %w[replace messages-unread-count],
                    ["replace", ActionView::RecordIdentifier.dom_id(message, :conversation)],
                    ["replace", ActionView::RecordIdentifier.dom_id(message, :card)],
                    ["replace", ActionView::RecordIdentifier.dom_id(reply, :card)]],
                   css_select("turbo-stream").map { |stream| [stream["action"], stream["target"]] }
      assert_select "turbo-stream template article[data-unread]", count: 0
    end
    assert_unread_threads
  end

  test "a one-to-one message is notified as one, from its sender" do
    details = capture_message_notify_details do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Hi", body: "Hello" } }
    end
    assert_equal [[@recipient.id, @sender.callsign, false]], details.map { |call| call.values_at(:person_id, :from, :group) }
  end

  test "a reply written in the editor streams a formatted card and notifies its text" do
    message = create_message(@recipient, @sender, "Reply Thread", "Body")

    calls = capture_message_notify_calls do
      post create_reply_me_message_path(message), params: { message_reply_form: { reply: "<p>On <em>my</em> way</p>" } },
                                                  as: :turbo_stream
    end
    assert_select "turbo-stream[action=append][target=messages-thread] template article .lexxy-content em", text: "my"
    assert_equal [[@recipient.id, "Reply Thread", "On my way"]], calls
  end

  # --- Search. The hits are the person_message fixtures, InactiveRanger's mail:
  # the full-text index sees committed rows only, never a row a test creates.

  test "a search lists its hits from every folder, marked, in the tab row's place" do
    sign_in_as(person(:inactive_ranger))
    swap = person_message(:search_dirt_swap)
    radio = person_message(:search_radio_archived)

    get me_messages_path(q: "dirt shift")
    assert_response :success
    assert_select "form[role=search][method=get][data-turbo-frame=messages-conversation-list][data-turbo-action=advance] " \
                  "input[type=search][name=q][value=?][aria-label=?]", "dirt shift", "Search Messages"
    assert_select "[role=tablist]", count: 0
    assert_select "#messages-conversation-list [role=status]", text: /2 conversations match “dirt shift” in every folder/
    assert_select "#messages-conversation-list a[data-turbo-frame=_top][href=?]", me_messages_path, text: /Clear Search/
    assert_select "ul[aria-label='Search results'] a.review-line", count: 2
    assert_select "a.review-line[href=?]", me_message_path(swap, folder: PersonMessage::FOLDER_INBOX, q: "dirt shift") do
      assert_select "mark.search-hit", text: "Shift"
      assert_select "mark.search-hit", text: "Dirt"
      assert_select ".badge", count: 0
    end
    # The row's text is its name, snippet and marks included: a label would hide them.
    assert_select "a.review-line[aria-label]", count: 0
    # Sent and archived by the owner: the chip says where it was found.
    assert_select "a.review-line[data-review-id=?] .badge", radio.id.to_s, text: "Archived"

    # The message's apostrophe is escaped once, not shown as an entity.
    assert_equal "Can you take my 18:00 Dirt shift? I'll take your Saturday…",
                 css_select("a[data-review-id='#{swap.id}'] div.text-sm").first.text.strip
  end

  test "a search carries the folder it started from, for Clear Search and a blank search" do
    sign_in_as(person(:inactive_ranger))

    get me_messages_path(folder: PersonMessage::FOLDER_SENT)
    assert_select "form#messages-search[role=search]"
    assert_select "#messages-folder-selector input[type=hidden][name=folder][form=messages-search][value=?]",
                  PersonMessage::FOLDER_SENT

    get me_messages_path(folder: PersonMessage::FOLDER_SENT, q: "khaki"), headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "a[href=?]", me_messages_path(folder: PersonMessage::FOLDER_SENT), text: /Clear Search/
    assert_select "turbo-stream[target=messages-folder-selector] template input[name=folder][form=messages-search][value=?]",
                  PersonMessage::FOLDER_SENT

    # Inbox, the default, stays out of the address.
    get me_messages_path
    assert_select "input[name=folder][form=messages-search]", count: 0
  end

  test "the search field's request answers the list frame, taking the tab row away and back" do
    sign_in_as(person(:inactive_ranger))
    khaki = person_message(:search_khaki_notes)

    get me_messages_path(q: "khaki"), headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_response :success
    assert_select "h1", count: 0
    assert_select "turbo-frame#messages-conversation-list a.review-line[data-review-id=?]", khaki.id.to_s
    selector = "turbo-frame#messages-conversation-list turbo-stream[action=update][target=messages-folder-selector]"
    assert_select selector
    assert_select "#{selector} template [role=tablist]", count: 0
    # The tab row's frame still carries the search, for the pane's toggles to post.
    assert_select "#{selector} template input[name=q][form=messages-toggle-read][value=khaki]"

    # A blank search is the folder again, tabs and all.
    get me_messages_path(q: " "), headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "#{selector} template [role=tablist]"
    assert_select "#{selector} template input[name=q]", count: 0
    assert_select "[role=status]", count: 0
    # The swap and the khaki notes, and the group thread InactiveRanger is a member of.
    assert_select "turbo-frame#messages-conversation-list ul[aria-label=Conversations] a.review-line", count: 3
  end

  test "a search of short words alone marks the whole query" do
    sign_in_as(person(:inactive_ranger))

    get me_messages_path(q: "18")
    assert_select "a.review-line", count: 1
    assert_select "mark.search-hit", text: "18", count: 1
  end

  test "a hit's thread, its toggles and its back link keep the search" do
    sign_in_as(person(:inactive_ranger))
    swap = person_message(:search_dirt_swap)

    get me_message_path(swap, q: "dirt shift")
    assert_response :success
    assert_select "a[aria-label='Back to Messages'][href=?]", me_messages_path(q: "dirt shift")
    assert_select "input[type=search][name=q][value=?]", "dirt shift"
    assert_select "turbo-frame#messages-conversation-list[loading=lazy][src=?]",
                  me_messages_path(folder: PersonMessage::FOLDER_INBOX, selected: swap.id, q: "dirt shift")
    assert_select "#messages-folder-selector input[name=q][form=messages-toggle-archive][value=?]", "dirt shift"

    post toggle_archive_me_message_path(swap), params: { folder: PersonMessage::FOLDER_INBOX, q: "dirt shift" },
                                               as: :turbo_stream
    assert_response :success
    list = "turbo-stream[action=update][target=messages-conversation-list] template"
    assert_select "#{list} [role=status]", text: /2 conversations match/
    assert_select "#{list} a.review-line[aria-current=true][data-review-id=?] .badge", swap.id.to_s, text: "Archived"
    assert_select "turbo-stream[target=messages-folder-selector] template [role=tablist]", count: 0
  end

  test "a hit's thread marks its matches and lands on the first message holding one" do
    stepper = "[data-review-id][data-controller=search-matches] [role=group][aria-label='Matches in this conversation']"
    sign_in_as(person(:inactive_ranger))
    swap = person_message(:search_dirt_swap)
    reply_id = ActionView::RecordIdentifier.dom_id(person_message(:search_dirt_swap_reply), :card)
    top_card = "article##{ActionView::RecordIdentifier.dom_id(swap, :card)}"
    reply_card = "article##{reply_id}"

    get me_message_path(swap, q: "thermos")
    assert_response :success
    assert_select "#messages-thread [data-controller=scroll-to-element][hidden][data-scroll-to-element-id-value=?]" \
                  "[data-scroll-to-element-container-value='.review-pane']", reply_id
    assert_select "article[data-landing]", count: 1
    assert_select "#{reply_card}[data-landing] mark.search-hit", text: "thermos"
    assert_select "#{top_card} mark", count: 0
    assert_select "#{stepper} [role=status][data-search-matches-target=count]", text: "Match 1 of 1"
    assert_select "#{stepper} button[aria-label='Next match'][data-action='search-matches#next']"
    assert_select "#{stepper} button[aria-label='Previous match'][data-action='search-matches#previous']"

    # Only the top holds "dirt shift".
    get me_message_path(swap, q: "dirt shift")
    assert_select "#{top_card}[data-landing] mark.search-hit", count: 2
    assert_select "#{reply_card}[data-landing]", count: 0

    # Both hold "I'll": both marked, the first landed on.
    get me_message_path(swap, q: "I'll")
    assert_select "article mark.search-hit", count: 2
    assert_select "#{top_card}[data-landing]"
    assert_select "#{reply_card}[data-landing]", count: 0
    assert_select stepper, text: "Match 1 of 2"

    # A hit on the subject or the callsign alone, or no search: no mark, ring or scroll.
    ["Thursday", "AlphaN", nil].each do |q|
      get me_message_path(swap, q:)
      assert_response :success
      assert_select "article", count: 2
      assert_select "article mark", count: 0
      assert_select "article[data-landing]", count: 0
      assert_select "[data-controller=scroll-to-element]", count: 0
      assert_select "[data-controller=search-matches], [aria-label='Matches in this conversation']", count: 0
    end
  end

  # PersonMessage.search_for_person needs every word in one row, its subject
  # counted: here the reply's ("Shift swap…") and its "thermos". The top holds
  # "shift" alone and is marked, but is not the hit.
  test "a search of several words lands on the message holding them all" do
    sign_in_as(person(:inactive_ranger))
    swap = person_message(:search_dirt_swap)

    get me_message_path(swap, q: "thermos shift")
    assert_select "article##{ActionView::RecordIdentifier.dom_id(swap, :card)}:not([data-landing]) mark.search-hit", text: "shift"
    assert_select "article##{ActionView::RecordIdentifier.dom_id(person_message(:search_dirt_swap_reply), :card)}[data-landing] " \
                  "mark.search-hit", text: "thermos"
    # The stepper opens at the hit, the second of the two messages it stops at.
    assert_select "[aria-label='Matches in this conversation'] [role=status]", text: "Match 2 of 2"
  end

  test "a hit in a message written in the editor is marked in its text, never in its markup" do
    sign_in_as(person(:inactive_ranger))
    radio = person_message(:search_radio_archived)
    rich_card = "article##{ActionView::RecordIdentifier.dom_id(person_message(:search_radio_rich_reply), :card)}"

    get me_message_path(radio, q: "depot")
    assert_response :success
    assert_select "#{rich_card}[data-landing] .lexxy-content a[href=?] mark.search-hit", "https://example.org/depot",
                  text: "depot"

    # Words of the markup alone -- the link's address, a tag -- are no match.
    %w[https strong].each do |q|
      get me_message_path(radio, q:)
      assert_select "article mark", count: 0
      assert_select "article[data-landing]", count: 0
    end
  end

  # The legacy body's "<name@example.org>" is in its text, but the sanitizer
  # takes it out of the card as a tag: the card that shows a mark is landed on.
  test "a hit lands on a card that shows its match, never on one whose match the sanitizer took out" do
    top = create_message(@recipient, @sender, "Gate list", "Jane Smith <name@example.org> wrote:\nsee you Thursday")
    reply = create_message(@recipient, @sender, "Gate list", "The example form is on the board.", reply_to_id: top.id)

    get me_message_path(top, q: "example")
    assert_select "article##{ActionView::RecordIdentifier.dom_id(top, :card)}:not([data-landing])"
    assert_select "article##{ActionView::RecordIdentifier.dom_id(top, :card)} mark", count: 0
    assert_select "article##{ActionView::RecordIdentifier.dom_id(reply, :card)}[data-landing] mark.search-hit", text: "example"
  end

  # A plain body's own markup is sanitized, and its links are found in its
  # text: matched in the HTML, a phone number or a URL in a title made a link
  # whose quotes ended the title, and the rest of the value ran as markup.
  test "a plain body's links are found in its text, never inside one of its attributes" do
    titled = [%(<b title="555-123-4567<img src=x onerror=alert(1)>">hi</b>),
              %(<b title="a>b http://x.example/ <img src=x onerror=alert(2)>">hi</b>)].map do |body|
      create_message(@recipient, @sender, "Gate", body)
    end
    titled.each do |message|
      get me_message_path(message)
      assert_response :success
      assert_select "#messages-thread img", count: 0
      assert_select "#messages-thread a[href^='tel:'], #messages-thread a[href^='http']", count: 0
      assert_select "article [data-message-body] b[title]", text: "hi"
    end

    plain = create_message(@recipient, @sender, "Gate", "Call 775-555-1234 or see https://example.org/a?b=1&c=2.\nThanks")
    get me_message_path(plain)
    card = "article##{ActionView::RecordIdentifier.dom_id(plain, :card)} [data-message-body]"
    assert_select "#{card} a[href='tel:7755551234']", text: "775-555-1234"
    assert_select "#{card} a[href=?]", "https://example.org/a?b=1&c=2", text: "https://example.org/a?b=1&c=2"
    assert_select "#{card} br"
  end

  # Nested to the HTML5 parser's limit with a link at the bottom, which adds a
  # level: the card renders, unmarked, rather than failing the page. Read as
  # text: assert_select's own parse of the page stops at that limit too.
  test "a body nested as deep as the parser goes opens from a search" do
    message = create_message(@recipient, @sender, "Deep", ("<b>" * 400) + "dirt http://example.org/x" + ("</b>" * 400))

    get me_message_path(message, q: "dirt")
    assert_response :success
    assert_includes response.body, %(<a href="http://example.org/x">http://example.org/x</a>)
    assert_not_includes response.body, %(<mark class="search-hit">dirt</mark>)
  end

  # The read-state morphs know no search: the page keeps the bodies and the
  # ring _thread drew (review_pane_controller; the system test watches it).
  test "Mark Unread morphs every card, drawing no search's marks or ring" do
    sign_in_as(person(:inactive_ranger))
    swap = person_message(:search_dirt_swap)
    cards = [swap, person_message(:search_dirt_swap_reply)].map do |message|
      "turbo-stream[action=replace][method=morph][target=#{ActionView::RecordIdentifier.dom_id(message, :card)}] template article"
    end

    post toggle_read_me_message_path(swap), params: { folder: PersonMessage::FOLDER_INBOX, q: "thermos" }, as: :turbo_stream
    assert_response :success
    cards.each do |card|
      assert_select "#{card} [data-message-body]", count: 1
      assert_select "#{card} mark", count: 0
      assert_select "#{card}[data-landing]", count: 0
    end
  end

  # Drawn on every row the owner started and shown by a search's list alone
  # (data-search), so a render that cannot know the list -- a live reply's
  # broadcast -- still draws it right.
  test "a search's hit the owner started says Sent, under Archived, and a folder's list never shows it" do
    sign_in_as(person(:inactive_ranger))
    radio = person_message(:search_radio_archived)
    row = "a.review-line[data-review-id='#{radio.id}']"
    chips = -> { css_select("#{row} .badge").map { |chip| chip.text.strip } }

    # Sent and archived by the owner: one chip, where it was found.
    get me_messages_path(q: "radio")
    assert_equal ["Archived"], chips.call

    person_message_member(:search_radio_archived_inactive_ranger).update!(archived: false)
    get me_messages_path(q: "radio")
    assert_equal ["Sent"], chips.call
    assert_select "ul[data-search] #{row} .badge.hidden.in-data-search\\:inline-flex", text: "Sent"

    get me_messages_path(folder: PersonMessage::FOLDER_SENT)
    assert_select row
    assert_select "ul[data-search]", count: 0
  end

  # The live mark-read posts the list's folder and search (thread_live_controller),
  # as the toggles do, and the row comes back as that list draws it.
  test "mark read draws the row for the folder and search it posts" do
    sign_in_as(person(:inactive_ranger))
    radio = person_message(:search_radio_archived)
    row = "turbo-stream[target=#{ActionView::RecordIdentifier.dom_id(radio, :conversation)}] template a.review-line"

    post mark_read_me_message_path(radio), params: { folder: PersonMessage::FOLDER_ARCHIVED, q: "radio" }, as: :turbo_stream
    assert_select "#{row}[href=?] mark.search-hit", me_message_path(radio, folder: PersonMessage::FOLDER_ARCHIVED, q: "radio")

    post mark_read_me_message_path(radio), params: { folder: PersonMessage::FOLDER_ARCHIVED }, as: :turbo_stream
    assert_select "#{row}[href=?]", me_message_path(radio, folder: PersonMessage::FOLDER_ARCHIVED)
    assert_select "#{row} mark", count: 0
  end

  # --- The search field's suggestions and chips (.scratch/messages-search/PRD.md, slices 4 and 5)

  test "the search field suggests the search first, then the owner's people with how many conversations each shares" do
    sign_in_as(person(:inactive_ranger))

    get suggest_me_messages_path(q: "ran")
    assert_response :success
    # Review finding: each keystroke's JSON built the menu, which only a layout reads.
    assert_nil @controller.instance_variable_get(:@menu_context)
    body = response.parsed_body
    assert_equal [["search", ""], ["people", MessagesConcern::SUGGESTED_PEOPLE]], body["groups"].map { |group| group.values_at("key", "title") }
    search, ranger = body["items"]
    assert_equal ["ran", "search"], [search["value"], search.dig("meta", "kind")]
    assert_includes search["html"], "Search messages for “ran”"
    assert_equal ["RANGER1", "person"], [ranger["value"], ranger.dig("meta", "kind")]
    assert_includes ranger["html"], "2 conversations"

    # Review finding: a person the field holds as a chip was suggested again.
    get suggest_me_messages_path(q: "ran", with: ["ranger-1"])
    assert_equal %w[search], response.parsed_body["groups"].pluck("key")
  end

  test "the search field suggests a team of the owner's conversations as a search for its name, and escapes the text" do
    owner = person(:inactive_ranger)
    cadre = teams(:green_dot_cadre)
    [owner, @recipient].each { |member| join_team(member, cadre) }
    create_team_thread(@recipient, cadre)
    sign_in_as(owner)

    get suggest_me_messages_path(q: "green")
    team = response.parsed_body["items"].find { |item| item.dig("meta", "kind") == "team" }
    assert_equal "Green Dot Cadre", team["value"]
    assert_equal %w[search teams], response.parsed_body["groups"].pluck("key")

    get suggest_me_messages_path(q: "<b>tag")
    assert_includes response.parsed_body["items"].first["html"], "&lt;b&gt;tag"
  end

  test "a chip keeps the search to its person's conversations, and every link and toggle carries it" do
    sign_in_as(person(:inactive_ranger))
    radio = person_message(:search_radio_archived)
    khaki = person_message(:search_khaki_notes)

    get me_messages_path(with: ["RANGER1"])
    assert_response :success
    # Never kept for Back, which would pair the chips with the list before them.
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "form#messages-search [role=combobox][aria-label='Search Messages']"
    assert_select "form#messages-search [data-message-search-target=list] input[type=hidden][name='with[]'][value=RANGER1]"
    assert_select "form#messages-search button[aria-label='Remove RANGER1'][data-action='message-search#remove']"
    assert_select "[role=tablist]", count: 0
    assert_select "#messages-conversation-list [role=status]", text: /2 conversations with RANGER1 in every folder/
    assert_select "ul[aria-label='Search results'][data-search] a.review-line", count: 2
    assert_select "a.review-line[href=?]", me_message_path(khaki, folder: PersonMessage::FOLDER_INBOX, with: ["RANGER1"])
    assert_select "#messages-folder-selector input[name='with[]'][form=messages-toggle-read][value=RANGER1]"

    get me_messages_path(q: "dirt", with: ["RANGER1"])
    assert_select "[role=status]", text: /1 conversation with RANGER1 matches “dirt” in every folder/
    assert_select "a.review-line[href=?] mark.search-hit",
                  me_message_path(radio, folder: PersonMessage::FOLDER_INBOX, q: "dirt", with: ["RANGER1"]), text: "Dirt"

    # RANGER1's thread with AlphaNewbie says "roster", but it is someone else's mail.
    get me_messages_path(q: "roster", with: ["RANGER1"])
    assert_select "[role=status]", text: /No conversations with RANGER1 match “roster” in any folder/
    assert_select "a.review-line", count: 0
  end

  test "the chips are callsigns, each once, three at most" do
    sign_in_as(person(:inactive_ranger))

    get me_messages_path(with: { "a" => "RANGER1" })
    assert_select "[role=tablist]"
    assert_select "[data-message-search-target=list] [data-message-search-target=chip]", count: 0

    get me_messages_path(with: %w[RANGER1 ranger1 RetiredRanger EchelonTest AlphaNewbie])
    assert_select "[data-message-search-target=list] input[name='with[]']", count: 3
    assert_select "[role=status]", text: /No conversations with RANGER1, RetiredRanger, and EchelonTest in any folder/

    # Review finding: each spelling of one person was a chip of its own, as typed.
    # Each is looked up as the compose form looks one up, and shown as the person's.
    get me_messages_path(with: %w[ranger-1 RANGER1])
    assert_select "[data-message-search-target=list] input[name='with[]']", count: 1
    assert_select "[data-message-search-target=list] input[name='with[]'][value=RANGER1]"
    assert_select "[role=status]", text: /2 conversations with RANGER1 in every folder/

    # One naming nobody stays as typed, and finds nothing.
    get me_messages_path(with: %w[ranger-1 NoSuchRanger])
    assert_select "[data-message-search-target=list] input[name='with[]'][value=NoSuchRanger]"
    assert_select "[role=status]", text: /No conversations with RANGER1 and NoSuchRanger in any folder/
  end

  test "a hit's thread carries the chips to its back link, its lazy list and the toggles" do
    sign_in_as(person(:inactive_ranger))
    khaki = person_message(:search_khaki_notes)

    get me_message_path(khaki, with: ["RANGER1"])
    assert_response :success
    assert_select "head meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "a[aria-label='Back to Messages'][href=?]", me_messages_path(with: ["RANGER1"])
    assert_select "form#messages-search input[name='with[]'][value=RANGER1]"
    assert_select "turbo-frame#messages-conversation-list[loading=lazy][src=?]",
                  me_messages_path(folder: PersonMessage::FOLDER_INBOX, selected: khaki.id, with: ["RANGER1"])

    post toggle_archive_me_message_path(khaki), params: { folder: PersonMessage::FOLDER_INBOX, with: ["RANGER1"] },
                                                as: :turbo_stream
    list = "turbo-stream[action=update][target=messages-conversation-list] template"
    assert_select "#{list} [role=status]", text: /2 conversations with RANGER1/
    assert_select "#{list} a.review-line[aria-current=true][data-review-id=?] .badge", khaki.id.to_s, text: "Archived"
  end

  # --- Group threads (messaging rework slice 3, ruling D2) ----------------------

  test "a message to three callsigns is one shared thread: one top, a member row each, three notified" do
    people = group_recipients
    notified = capture_group_notifies do
      assert_difference -> { PersonMessage.count } => 1, -> { PersonMessageMember.count } => 4 do
        post me_messages_path, params: {
          message_form: { callsigns: people.map { |person| person.callsign.downcase }, subject: "Burn night crew", body: "Radios?" }
        }
      end
    end

    top = PersonMessage.order(:id).last
    assert_redirected_to me_message_path(top)
    assert top.group?
    assert_equal [@sender.id] * 3, [top.person_id, top.sender_person_id, top.creator_person_id]
    assert_equal [@sender, *people].map(&:id).sort, top.members.pluck(:person_id).sort
    assert_equal people.map(&:id).sort, notified.sort
    assert top.thread_read?(@sender.id)
    people.each { |person| assert_includes PersonMessage.unread_for_person(person.id), top }
  end

  test "one callsign in the chip field is a one-to-one message, as it always was" do
    # Its member rows: the recipient has not read it, the sender has.
    assert_difference -> { PersonMessageMember.count } => 2 do
      post me_messages_path, params: { message_form: { callsigns: [@recipient.callsign], subject: "Hi", body: "Body" } }
    end

    message = PersonMessage.order(:id).last
    assert_not message.group?
    assert_equal [@recipient.id, @sender.id], [message.person_id, message.sender_person_id]
    assert_equal({ @recipient.id => nil, @sender.id => message.id },
                 message.members.pluck(:person_id, :last_read_message_id).to_h)
  end

  test "one refused callsign stops the whole send and says which" do
    people = group_recipients
    @prospective.update!(last_seen_at: nil)

    notified = capture_message_notifies do
      assert_no_difference -> { PersonMessage.count + PersonMessageMember.count } do
        post me_messages_path, params: { message_form: { callsigns: people.map(&:callsign), subject: "S", body: "B" } }
      end
    end

    assert_response :unprocessable_entity
    assert_empty notified
    assert_select "#form-error-summary", text: /#{@prospective.callsign}: You can't message that callsign\./
    assert_select "#form-error-summary li", count: 1
  end

  test "a crafted form cannot name more callsigns than the cap" do
    callsigns = Array.new(MessageForm::MAX_CALLSIGNS + 1) { |index| "Nobody#{index}" }

    assert_no_difference -> { PersonMessage.count } do
      post me_messages_path, params: { message_form: { callsigns:, subject: "S", body: "B" } }
    end
    assert_select "#form-error-summary", text: /A message can go to #{MessageForm::MAX_CALLSIGNS} callsigns at most\./
  end

  test "a Cadre's messageable members make the thread, the sender included once" do
    cadre = teams(:green_dot_cadre)
    [@recipient, @sender].each { |member| PersonTeam.find_or_create_by!(person: member, team: cadre) }
    gone = person(:deceased_ranger)
    PersonTeam.find_or_create_by!(person: gone, team: cadre)

    notified = capture_group_notifies do
      post me_messages_path, params: { message_form: { team_id: cadre.id, subject: "Sanctuary", body: "Friday?" } }
    end

    top = PersonMessage.order(:id).last
    assert top.group?
    assert_equal cadre.id, top.recipient_team_id
    assert_equal [@sender, @recipient, @prospective].map(&:id).sort, top.members.pluck(:person_id).sort
    assert_equal [@recipient, @prospective].map(&:id).sort, notified.sort
  end

  test "a send to a Cadre marks its members as the team's, and not a callsign named beside it" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)

    post me_messages_path, params: { message_form: { team_id: cadre.id, callsigns: [@recipient.callsign],
                                                     subject: "Sanctuary", body: "Friday?" } }

    assert_equal({ @sender.id => cadre.id, @prospective.id => cadre.id, @recipient.id => nil },
                 team_marks(PersonMessage.order(:id).last))
  end

  test "a reply as the team names the team to a named recipient and its author to the team's members" do
    cadre, top = create_cadre_thread

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On it", as_team_id: cadre.id } },
                                            as: :turbo_stream
    assert_response :success
    reply = top.replies.reload.last
    assert_equal [PersonMessage::SENDER_TYPE_TEAM, cadre.id, @sender.id],
                 [reply.sender_type, reply.sender_team_id, reply.sender_person_id]
    card = "##{ActionView::RecordIdentifier.dom_id(reply, :card)}"
    replied_as = /#{Regexp.escape(@sender.callsign)}\s+Replied as Green Dot Cadre/
    # The author's own card, appended by the form, and the page's
    assert_select card, text: replied_as
    get me_message_path(top)
    assert_select card, text: replied_as

    # The card each member was sent, as they see it (HTML, so the name and the chip are matched apart)
    member = capture_turbo_stream_broadcasts([@prospective, top]).map(&:to_html).join
    assert_match(/>#{Regexp.escape(@sender.callsign)}</, member)
    assert_match(/Replied as Green Dot Cadre/, member)
    outside = capture_turbo_stream_broadcasts([@recipient, top]).map(&:to_html).join
    assert_match(/Green Dot Cadre/, outside)
    assert_no_match(/#{Regexp.escape(@sender.callsign)}/, outside)

    sign_in_as(@recipient)
    get me_message_path(top)
    assert_select card, text: /Green Dot Cadre/
    assert_select card, text: /Replied as/, count: 0
  end

  test "a refused reply keeps the author's own name as chosen, and the form after a sent one is back on the team" do
    cadre, top = create_cadre_thread
    as_team = "input[type=radio][name='message_reply_form[as_team_id]'][value='#{cadre.id}']"
    as_self = "input[type=radio][name='message_reply_form[as_team_id]'][value='']"

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "", as_team_id: "" } }, as: :turbo_stream
    assert_select "#{as_self}[checked]"
    assert_select "#{as_team}:not([checked])"

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Mine", as_team_id: "" } }, as: :turbo_stream
    assert_equal PersonMessage::SENDER_TYPE_PERSON, top.replies.reload.last.sender_type
    assert_select "#{as_team}[checked]"
  end

  test "someone who left the team cannot reply as it, and their own reply says they left" do
    cadre, top = create_cadre_thread
    PersonTeam.where(person: @sender, team: cadre).delete_all

    assert_no_difference -> { PersonMessage.count } do
      post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On it", as_team_id: cadre.id } },
                                              as: :turbo_stream
    end
    assert_response :success
    assert_match(/Only a current member of an active Cadre or Delegation in this conversation can reply as it\./, response.body)
    assert_select "input[name='message_reply_form[as_team_id]']", count: 0

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Still here" } }, as: :turbo_stream
    reply = top.replies.reload.last
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply, :card)}", text: /Former Green Dot Cadre Member/
    get me_message_path(top)
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply, :card)} .badge", text: "Former Green Dot Cadre Member"
  end

  test "the Reply As choice is offered to a team thread's current team members alone, the team checked" do
    cadre, top = create_cadre_thread
    get me_message_path(top)
    assert_select "#messages-reply-form", text: /Reply As/
    assert_select "input[type=radio][name='message_reply_form[as_team_id]'][value='#{cadre.id}'][checked]"
    assert_select "input[type=radio][name='message_reply_form[as_team_id]'][value='']:not([checked])"
    assert_select "#messages-reply-form", text: /The team's members still see your callsign\./

    plain = create_group_thread(@sender, @recipient, @prospective)
    get me_message_path(plain)
    assert_select "input[name='message_reply_form[as_team_id]']", count: 0

    sign_in_as(@recipient)
    get me_message_path(top)
    assert_select "input[name='message_reply_form[as_team_id]']", count: 0
  end

  test "a thread sent as a team reads From the team to a recipient outside it, and To the team and the others to its members" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)
    top = create_group_thread(@sender, @recipient, as_team: cadre)

    get me_message_path(top)
    assert_party "To: Green Dot Cadre, #{@recipient.callsign}"

    sign_in_as(@recipient)
    get me_message_path(top)
    assert_party "From: Green Dot Cadre"
    get me_messages_path, headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "##{ActionView::RecordIdentifier.dom_id(top, :conversation)} .text-heading", text: /\A\s*From:\s+Green Dot Cadre\s*\z/
  end

  # Review finding: "From:" stood before the whole party, so the To team and
  # every co-recipient read as senders.
  test "a thread sent as a team to a team and two people reads From that team alone to everyone outside it" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)
    echelon = group_recipients.last
    council_member = person(:retired_ranger)
    join_team(council_member, teams(:council_cadre))
    top = create_team_thread(@sender, teams(:council_cadre), @recipient, echelon, as_team: cadre)
    card = "##{ActionView::RecordIdentifier.dom_id(top, :card)}"

    get me_message_path(top)
    assert_match(/\ATo: Green Dot Cadre, Council Cadre, /, party_text)
    assert_select card, text: /#{Regexp.escape(@sender.callsign)}\s+Sent as Green Dot Cadre/
    [@recipient, council_member].each do |viewer|
      sign_in_as(viewer)
      get me_message_path(top)
      assert_party "From: Green Dot Cadre"
      assert_select card, text: /Sent as|#{Regexp.escape(@sender.callsign)}/, count: 0
    end
  end

  # Review finding: the label read the member row's mark, the reveal the roster.
  test "the From and To label follows the roster: a joiner reads To, a leaver From" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)
    top = create_group_thread(@sender, @recipient, as_team: cadre)

    card = "##{ActionView::RecordIdentifier.dom_id(top, :card)}"
    join_team(@recipient, cadre)
    sign_in_as(@recipient)
    get me_message_path(top)
    assert_match(/\ATo: Green Dot Cadre/, party_text)
    assert_select card, text: /#{Regexp.escape(@sender.callsign)}\s+Sent as Green Dot Cadre/

    PersonTeam.find_by!(person: @prospective, team: cadre).destroy!
    sign_in_as(@prospective)
    get me_message_path(top)
    assert_party "From: Green Dot Cadre"
    assert_select card, text: /Sent as|#{Regexp.escape(@sender.callsign)}/, count: 0
  end

  # Review finding: a team deleted since made every row written as it raise.
  test "a thread whose team was deleted still opens, naming the team by its id" do
    cadre, top = create_cadre_thread
    reply = create_group_reply(top, @sender, as_team: cadre)
    TeamManagement.destroy(cadre)

    get me_message_path(top)
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply, :card)}", text: /Deleted Team ##{cadre.id}/
    assert_party "To: Deleted Team ##{cadre.id}, #{@recipient.callsign}"
    get me_messages_path, headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "##{ActionView::RecordIdentifier.dom_id(top, :conversation)}", text: /Deleted Team ##{cadre.id}/
  end

  # Review finding: Reply As offered a deactivated Cadre the model then refused.
  test "a deactivated Cadre is not offered in Reply As, and a crafted reply as it is refused" do
    cadre, top = create_cadre_thread
    cadre.update!(active: false)

    get me_message_path(top)
    assert_select "input[name='message_reply_form[as_team_id]']", count: 0
    assert_no_difference -> { PersonMessage.count } do
      post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On it", as_team_id: cadre.id } },
                                              as: :turbo_stream
    end
    assert_match(/Only a current member of an active Cadre or Delegation in this conversation can reply as it\./, response.body)
  end

  test "a message sent as a Cadre to one callsign is a group thread the Cadre is in, read From the Cadre" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)

    notified = capture_group_notifies do
      post me_messages_path, params: { message_form: { sender_team_id: cadre.id, callsigns: [@recipient.callsign],
                                                       subject: "From the dots", body: "Hello" } }
    end

    top = PersonMessage.order(:id).last
    assert_redirected_to me_message_path(top)
    assert_equal [PersonMessage::SENDER_TYPE_TEAM, cadre.id, @sender.id, true],
                 [top.sender_type, top.sender_team_id, top.sender_person_id, top.group?]
    assert_equal({ @sender.id => cadre.id, @prospective.id => cadre.id, @recipient.id => nil }, team_marks(top))
    assert_equal [@recipient, @prospective].map(&:id).sort, notified.sort
    assert_includes PersonMessage.retrieve_for_person(@sender.id, PersonMessage::FOLDER_SENT), top

    sign_in_as(@recipient)
    get me_message_path(top)
    assert_select "#messages-panel-header", text: /From:\s+Green Dot Cadre/
    assert_select "#messages-reply-form form"
  end

  test "the From choice is offered to a Cadre or Delegation member alone, and a non-member's is refused" do
    get new_me_message_path
    assert_select "select[name='message_form[sender_team_id]'] option[value='']", text: @sender.callsign
    assert_select "select[name='message_form[sender_team_id]'] option[value='#{teams(:council_cadre).id}']", text: "Council Cadre"

    sign_in_as(@recipient)
    get new_me_message_path
    assert_select "select[name='message_form[sender_team_id]']", count: 0
    assert_no_difference -> { PersonMessage.count } do
      post me_messages_path, params: { message_form: { sender_team_id: teams(:council_cadre).id, callsigns: [@sender.callsign],
                                                       subject: "S", body: "B" } }
    end
    assert_select "#form-error-summary", text: /Choose an active Cadre or Delegation you're a member of\./
  end

  # Review finding: "not a member" was false for a member whose Cadre was
  # deactivated after the form was drawn.
  test "sending as a Cadre deactivated since the form was drawn is refused for being inactive" do
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)
    cadre.update!(active: false)

    assert_no_difference -> { PersonMessage.count } do
      post me_messages_path, params: { message_form: { sender_team_id: cadre.id, callsigns: [@recipient.callsign],
                                                       subject: "S", body: "B" } }
    end
    assert_select "#form-error-summary", text: /Choose an active Cadre or Delegation you're a member of\./
  end

  test "a send that would reach nobody names its team once, beside the Cadre select" do
    cadre = teams(:mentor_cadre) # @sender is its only member
    assert_no_difference -> { PersonMessage.count } do
      post me_messages_path, params: { message_form: { sender_team_id: cadre.id, team_id: cadre.id, subject: "S", body: "B" } }
    end
    assert_response :unprocessable_entity
    assert_select "#message_form_team_id_hint[role=alert]", text: /\ANobody in the Mentor Cadre can be messaged\.\z/
  end

  test "a plain team, an inactive cadre or a missing one is refused" do
    [teams(:dirt_team), teams(:inactive_cadre)].map(&:id).push(0).each do |team_id|
      assert_no_difference -> { PersonMessage.count } do
        post me_messages_path, params: { message_form: { team_id:, subject: "S", body: "B" } }
      end
      assert_select "#form-error-summary", text: /Choose an active Cadre or Delegation\./
    end
  end

  test "a member's reply reaches every other member and leaves its author read" do
    people = group_recipients
    top = create_group_thread(people.first, @sender, *people.drop(1))

    notified = capture_group_notifies do
      post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On my way" } }, as: :turbo_stream
    end

    assert_response :success
    reply = top.replies.reload.last
    assert reply.group?
    assert_equal [@sender.id, @sender.id], [reply.person_id, reply.sender_person_id]
    assert_equal people.map(&:id).sort, notified.sort
    assert top.reload.thread_read?(@sender.id)
    people.drop(1).each { |person| assert_includes PersonMessage.unread_for_person(person.id), top }
    assert_includes PersonMessage.unread_for_person(people.first.id), top
  end

  test "opening, marking and archiving a group thread change only the viewer's member row" do
    people = group_recipients
    top = create_group_thread(people.first, @sender, *people.drop(1))

    get me_message_path(top)
    assert_response :success
    assert top.reload.thread_read?(@sender.id)
    assert_not top.thread_read?(people.second.id)

    post toggle_archive_me_message_path(top), as: :turbo_stream
    assert top.reload.archived?(@sender.id)
    assert_not top.archived?(people.second.id)
    assert_includes PersonMessage.retrieve_for_person(@sender.id, PersonMessage::FOLDER_ARCHIVED), top
    assert_includes PersonMessage.retrieve_for_person(people.second.id, PersonMessage::FOLDER_INBOX), top

    post toggle_read_me_message_path(top), as: :turbo_stream
    assert_includes PersonMessage.unread_for_person(@sender.id), top
    assert_not top.reload.thread_read?(@sender.id)
  end

  test "a group thread's row and header name the other members" do
    people = group_recipients
    top = create_group_thread(people.first, @sender, *people.drop(1))
    others = people.map(&:callsign).sort_by(&:downcase).join(", ")

    get me_message_path(top)

    assert_select "#messages-panel-header", text: /To:\s+#{Regexp.escape(others)}/
    get me_messages_path, headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "##{ActionView::RecordIdentifier.dom_id(top, :conversation)}", text: /To:\s+#{Regexp.escape(others)}/
  end

  # Owner's ruling 2026-10-19 (review finding 9): the reply goes to the thread,
  # and a member whose status now bars messages is skipped.
  test "a member whose status now bars messages is not told of a group reply, nor does it count unread for them" do
    people = group_recipients
    top = create_group_thread(@sender, *people)
    barred = people.second
    barred.update_column(:status, Person::RESIGNED)

    notified = nil
    told = capture_turbo_stream_broadcasts barred do
      notified = capture_group_notifies do
        post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Radios at 6." } },
                                                as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal [people.first, people.third].map(&:id).sort, notified.sort
    assert_empty told
    assert_not_includes PersonMessage.unread_for_person(barred.id), top
    assert top.reload.replies.last.read?(barred.id)
    [people.first, people.third].each { |member| assert_includes PersonMessage.unread_for_person(member.id), top }
  end

  test "a group message the model refuses says why" do
    original = PersonMessage.instance_method(:validate_reply)
    PersonMessage.define_method(:validate_reply) { errors.add(:base, "The Cadre was retired a moment ago.") && false }
    PersonMessage.send(:private, :validate_reply)

    assert_no_difference "PersonMessage.count" do
      post me_messages_path, params: { message_form: { callsigns: group_recipients.map(&:callsign), subject: "S", body: "B" } }
    end
    assert_response :unprocessable_entity
    assert_select "#form-error-summary", text: /The Cadre was retired a moment ago\./
    assert_select "#form-error-summary", text: /An error occurred/, count: 0
  ensure
    PersonMessage.define_method(:validate_reply, original)
    PersonMessage.send(:private, :validate_reply)
  end

  # Review finding 10: a reply marked read every reply loaded after its save,
  # one the author never saw included (its live card missed in a cable drop).
  test "a reply marks its author read only through what the page showed" do
    top = create_message(@recipient, @sender, "Radios", "Who has them?")
    get me_message_path(top)
    assert_select "input[name='message_reply_form[shown_through]'][value='#{top.id}']"
    unseen = create_message(@recipient, @sender, "Radios", "Two at the window.", reply_to_id: top.id)

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "On my way.", shown_through: top.id } },
                                            as: :turbo_stream

    assert_response :success
    own = PersonMessage.order(:id).last
    top.reload
    assert unseen.unread?(@sender.id)
    assert own.read?(@sender.id)
    assert_includes PersonMessage.unread_for_person(@sender.id), top
    # The form drawn after the send still says what the page showed.
    assert_select "input[name='message_reply_form[shown_through]'][value='#{top.id}']"
  end

  test "a group reply marks its author read only through what the page showed" do
    people = group_recipients
    top = create_group_thread(people.first, @sender, *people.drop(1))
    seen = create_group_reply(top, people.second, created_at: 1.minute.ago + 10.seconds)
    unseen = create_group_reply(top, people.third, created_at: 1.minute.ago + 20.seconds)

    capture_group_notifies do
      post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Here.", shown_through: seen.id } },
                                              as: :turbo_stream
    end

    top.reload
    assert seen.read?(@sender.id)
    assert unseen.unread?(@sender.id)
    assert_includes PersonMessage.unread_for_person(@sender.id), top
  end

  test "a reply never marks its author back past what they had read" do
    top = create_message(@recipient, @sender, "Radios", "Who has them?")
    live = create_message(@recipient, @sender, "Radios", "Two at the window.", reply_to_id: top.id)
    # A live card marked read after the page was drawn (thread_live_controller).
    post mark_read_me_message_path(top), as: :turbo_stream

    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Thanks.", shown_through: top.id } },
                                            as: :turbo_stream

    assert live.read?(@sender.id)
    assert_not_includes PersonMessage.unread_for_person(@sender.id), top
  end

  # Review finding 8: the app's own utilities, posted in a body, covered the
  # reader's screen. Rich (the editor's HTML) and plain bodies render alike.
  test "a message body's classes cannot cover the page" do
    overlay = %(class="fixed inset-0 z-50 bg-base-100 p-8")
    ["<p #{overlay}>Session expired. <a href=\"https://example.com/login\">Sign in</a></p>",
     "Session expired. <span #{overlay}>Sign in at https://example.com/login</span>"].each do |body|
      message = PersonMessage.create!(person: @sender, sender_person: @recipient, creator_person: @recipient, subject: "Login",
                                      body:, sender_type: PersonMessage::SENDER_TYPE_PERSON)
      get me_message_path(message)

      assert_select "#messages-thread", text: /Sign in/
      assert_select "#messages-thread .fixed", count: 0
    end
  end

  # Review finding 7: nothing removed a deleted person's member rows, and every
  # other member's list, pane and reply 500'd on them.
  test "deleting a person removes their member rows" do
    people = group_recipients
    top = create_group_thread(@sender, *people)
    gone = people.last

    assert_difference -> { top.members.count }, -1 do
      gone.destroy!
    end
  end

  # The member row goes with the person (person_message_member.person_id is a
  # foreign key); the thread the others share lists, opens and takes a reply
  # without them.
  test "a group thread lists, opens and takes a reply after a member's account is deleted" do
    people = group_recipients
    top = create_group_thread(@sender, *people)
    people.last.destroy!
    remaining = people.first(2).map(&:callsign).sort_by(&:downcase).join(", ")

    get me_messages_path, headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "##{ActionView::RecordIdentifier.dom_id(top, :conversation)}", text: /To:\s+#{Regexp.escape(remaining)}/
    get me_message_path(top)
    assert_select "#messages-panel-header", text: /To:\s+#{Regexp.escape(remaining)}/

    notified = capture_group_notifies do
      post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Still here?" } }, as: :turbo_stream
    end
    assert_response :success
    assert_equal people.first(2).map(&:id).sort, notified.sort
  end

  # A deleted person's messages stay (person_message has no foreign key to
  # person), with no name or photo left: they read as
  # LinkHelper#person_display_name names a person no longer there.
  test "a deleted person's thread lists and opens, naming them by id" do
    from_gone = create_message(@recipient, @sender, "From the Gone", "Body")
    to_gone = create_message(@sender, @recipient, "To the Gone", "Body")
    @recipient.destroy!
    deleted = Regexp.escape("Deleted ##{@recipient.id}")

    get me_messages_path, headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_select "##{ActionView::RecordIdentifier.dom_id(from_gone, :conversation)}", text: /#{deleted}/
    assert_select "##{ActionView::RecordIdentifier.dom_id(to_gone, :conversation)}", text: /To:\s+#{deleted}/
    get me_message_path(from_gone)
    assert_select "#messages-panel-header", text: /#{deleted}/
    assert_select "#messages-thread article", text: /#{deleted}/
  end

  test "someone outside a group thread cannot open, reply to or mark it" do
    people = group_recipients
    top = create_group_thread(people.first, *people.drop(1))

    get me_message_path(top)
    assert_redirected_to me_messages_path
    post create_reply_me_message_path(top), params: { message_reply_form: { reply: "Hi" } }, as: :turbo_stream
    assert_redirected_to me_messages_path
    post toggle_read_me_message_path(top), as: :turbo_stream
    assert_redirected_to me_messages_path
    assert_not top.members.exists?(person_id: @sender.id)
  end

  private

  # The pane header's party line, as one string of text.
  def party_text
    css_select("#messages-panel-header .text-lg").first.text.squish
  end

  def assert_party(expected)
    assert_equal expected, party_text
  end

  # A thread sent to the Green Dot Cadre: @sender and @prospective (a fixture
  # member) are on it, @recipient is named beside it.
  def create_cadre_thread
    cadre = teams(:green_dot_cadre)
    join_team(@sender, cadre)
    [cadre, create_team_thread(@sender, cadre, @recipient)]
  end

  # Three people a group message can go to, besides @sender.
  def group_recipients
    echelon = person(:echelon_ranger)
    echelon.update!(last_seen_at: 1.day.ago)
    [@recipient, @prospective, echelon]
  end

  def create_message(sender, recipient, subject, body, reply_to_id: nil)
    message = PersonMessage.create!(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: recipient.id,
      creator_person_id: sender.id,
      sender_person_id: sender.id,
      sender_type: PersonMessage::SENDER_TYPE_PERSON,
      subject: subject,
      body: body,
      reply_to_id: reply_to_id
    )
    # Reload to ensure associations are loaded
    message.reload
    message
  end

  # A broadcast, walk-up or team message as Clubhouse stores it: no sender_person_id.
  # A team sender must be a Cadre or Delegation, not TYPE_TEAM.
  def create_senderless(recipient, sender_type, expires_at: nil)
    PersonMessage.create!(
      person_id: recipient.id,
      creator_person_id: @sender.id,
      sender_type:,
      sender_team: (teams(:council_cadre) if sender_type == PersonMessage::SENDER_TYPE_TEAM),
      message_from: "Ranger HQ",
      subject: "#{sender_type} message",
      body: "Body",
      expires_at:
    )
  end

  # The Unread tab badge counts exactly the threads the Unread folder lists.
  def assert_unread_threads(*messages)
    assert_equal messages.size, PersonMessage.count_unread(@sender.id)
    unread = PersonMessage.retrieve_for_person(@sender.id, PersonMessage::FOLDER_UNREAD)
    assert_equal messages.map(&:id).sort, unread.map(&:id).sort
  end
end
