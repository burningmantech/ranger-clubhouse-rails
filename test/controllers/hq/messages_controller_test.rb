# frozen_string_literal: true

require "test_helper"

# The HQ twin of Person::MessagesControllerTest. The mailbox behaviour itself
# lives in MessagesConcern and the two-way compose in MessageDirectionConcern,
# both already covered by the person test, so the assertions here concentrate
# on what is genuinely new in the HQ port:
#
#   * the widened audience — Shift Management alone reaches this mailbox, where
#     the person page demands Event Management and the sidebar link-out it
#     replaces was invisible to the window operator entirely;
#   * the promise that the operator never leaves /hq, i.e. no page in this
#     namespace links or redirects back into /person;
#   * that the shared behaviour survived being mounted in a second namespace —
#     viewing still does not mark read, and both compose directions still work.
class Hq::MessagesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include GroupMessageTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    # The window operator deliberately holds Shift Management and nothing else.
    @viewer = person(:ranger_with_custom_gender)
    @subject = person(:active_ranger)
    @other = person(:retired_ranger)

    # messaging_permitted? requires last_seen_at
    @subject.update!(last_seen_at: 1.day.ago)
    @other.update!(last_seen_at: 1.day.ago)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # The HQ shell loads PersonEventInfo, whose training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- Access control ---------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_messages_path(@subject)

    assert_redirected_to person_path(@subject)
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject) # holds no roles at all

    get hq_messages_path(@viewer)

    assert_redirected_to me_root_path
  end

  # The whole point of the port: the person page needs Event Management, which
  # the window operator does not hold, so before this existed the HQ sidebar
  # hid Messages from the primary HQ persona.
  test "a shift management only operator reaches every HQ mailbox page" do
    assert_equal [Role::SHIFT_MANAGEMENT], @viewer.person_role.pluck(:role_id),
                 "the viewer must hold Shift Management and nothing else for this test to mean anything"

    message = create_message(@other, @subject, "Hello", "Body")

    [
      hq_messages_path(@subject),
      hq_message_path(@subject, message),
      new_hq_message_path(@subject, direction: "to"),
      new_hq_message_path(@subject, direction: "from")
    ].each do |path|
      get path
      assert_response :success, "#{path} should be reachable with Shift Management alone"
    end
  end

  # --- Staying inside the shell -------------------------------------------------

  test "index renders inside the HQ shell with hq scoped links" do
    create_message(@other, @subject, "Hello Subject", "A message body")

    get hq_messages_path(@subject)

    assert_response :success
    assert_match "Hello Subject", response.body
    # The HTML index must still get the shell chrome — :index is in the
    # skip_before_action list and only gets load_hq_shell back on html.
    assert_select "a[href='#{person_path(@subject)}']", text: /Switch to Person Manage/
    # The back link leaves the mailbox, so it names the HQ home, not the person page.
    assert_select "a[href='#{hq_shift_manage_path(@subject)}']", text: /Shift Check In\/Out/
    assert_select "a[href='#{new_hq_message_path(@subject, direction: "to")}']"
    assert_select "a[href='#{new_hq_message_path(@subject, direction: "from")}']"
    # Scoped to the mailbox: the HQ shell chrome deliberately keeps a "Switch to
    # Person Manage" escape hatch and the Assets / Training link-outs, so a blanket
    # no-/person assertion would pin the shell rather than this page.
    assert_select "a[href^='#{person_messages_path(@subject)}']", false,
                  "the HQ mailbox must not link into the /person mailbox"
  end

  test "the compose and thread pages link back to the HQ mailbox" do
    message = create_message(@other, @subject, "Thread Top", "Body")

    [new_hq_message_path(@subject, direction: "to"), hq_message_path(@subject, message)].each do |path|
      get path
      assert_response :success
      assert_select "a[href='#{hq_messages_path(@subject)}']", text: /#{@subject.callsign} Messages/
      assert_select "a[href='#{person_messages_path(@subject)}']", false,
                    "#{path} must not link back into /person"
    end
  end

  # The folder tabs are turbo-stream links, so this is the hottest path in the
  # page — it deliberately skips the shell loader and must still answer.
  test "folder switching answers turbo streams without the shell" do
    PersonMessage::VALID_FOLDERS.each do |folder|
      get hq_messages_path(@subject, folder:), as: :turbo_stream

      assert_response :success, "the #{folder} folder should answer a turbo stream"
      assert_no_match "Switch to Person Manage", response.body,
                      "the #{folder} turbo stream must not carry the shell chrome"
    end
  end

  # Accept: */* renders the HTML branch but reports request.format == Mime::ALL,
  # so a shell guard written as `if request.format.html?` skips the shell and
  # the page 500s on nil @banners. Anything without an Accept header hits this.
  test "index still renders the shell for a wildcard accept header" do
    get hq_messages_path(@subject), headers: { "Accept" => "*/*" }

    assert_response :success
    assert_match "Switch to Person Manage", response.body
  end

  test "an invalid direction redirects inside the hq namespace" do
    get new_hq_message_path(@subject)

    assert_redirected_to hq_messages_path(@subject)
    assert_match(/Unknown message direction/, flash[:error])
  end

  test "a thread the person does not participate in redirects inside the hq namespace" do
    message = create_message(@other, @viewer, "Private", "Not the subject's thread")

    get hq_message_path(@subject, message)

    assert_redirected_to hq_messages_path(@subject)
  end

  # --- Shared behaviour, mounted in a second namespace ---------------------------

  test "opening a message does not change the person's read state" do
    message = create_message(@other, @subject, "Unread Subject", "Body")
    assert_not message.thread_read?(@subject.id)

    get hq_message_path(@subject, message)

    assert_response :success
    assert_not message.reload.thread_read?(@subject.id)
  end

  test "toggle read flips the person's read state" do
    message = create_message(@other, @subject, "Toggle Me", "Body")

    post toggle_read_hq_message_path(@subject, message), as: :turbo_stream

    assert_response :success
    assert message.reload.thread_read?(@subject.id)
  end

  test "send-to creates a message to the person from the looked-up sender" do
    assert_difference -> { PersonMessage.count }, 1 do
      post hq_messages_path(@subject, direction: "to"),
           params: { message_form: { callsigns: [@other.callsign], subject: "Relay", body: "HQ window relay" } }
    end

    message = PersonMessage.order(:id).last
    assert_equal @subject.id, message.person_id
    assert_equal @other.id, message.sender_person_id
    assert_equal @viewer.id, message.creator_person_id
    assert_redirected_to hq_message_path(@subject, message)
  end

  test "send-from creates a message from the person to the looked-up recipient" do
    assert_difference -> { PersonMessage.count }, 1 do
      post hq_messages_path(@subject, direction: "from"),
           params: { message_form: { callsigns: [@other.callsign], subject: "Outbound", body: "Sent as the person" } }
    end

    message = PersonMessage.order(:id).last
    assert_equal @other.id, message.person_id
    assert_equal @subject.id, message.sender_person_id
    assert_redirected_to hq_message_path(@subject, message)
  end

  test "reply in a thread is sent as the person" do
    message = create_message(@other, @subject, "Thread Top", "Body")

    post create_reply_hq_message_path(@subject, message),
         params: { message_reply_form: { reply: "Replying as the person" } }

    assert_redirected_to hq_message_path(@subject, message)
    reply = message.replies.reload.last
    assert_equal @subject.id, reply.sender_person_id
    assert_equal @other.id, reply.person_id
    assert_equal @viewer.id, reply.creator_person_id
  end

  # The turbo-stream-only actions skip load_hq_shell so they cannot consume the
  # once-per-person entry warning; this pins that they still answer.
  test "find recipient modal carries the direction" do
    get find_recipient_hq_messages_path(@subject, direction: "to"), as: :turbo_stream

    assert_response :success
    assert_match "Find Sender", response.body
    assert_match "direction=to", response.body
  end

  # A row's link loads the pane's frame alone; like the folder streams, that
  # request must not pay for the shell or consume the entry warning, while the
  # thread page itself still gets the shell.
  test "the pane frame request answers without the shell" do
    message = create_message(@other, @subject, "Framed", "Body")

    get hq_message_path(@subject, message), headers: { "Turbo-Frame" => "messages-pane" }

    assert_response :success
    assert_select "turbo-frame#messages-pane [data-review-id='#{message.id}']"
    assert_no_match "Switch to Person Manage", response.body
    assert_nil session[:hq_warned_person_id], "the frame request must not consume the entry warning"
    assert_not message.reload.thread_read?(@subject.id), "the frame request must not mark the person's thread read"
    # Replies land live in the person's view of the thread, and stay unread here.
    assert_select "turbo-frame#messages-pane turbo-cable-stream-source[signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@subject, message])
    assert_select "[data-controller~=thread-live]", count: 0
    assert_select "turbo-frame#messages-pane a", text: /Back to Messages/

    get hq_message_path(@subject, message)

    assert_response :success
    assert_match "Switch to Person Manage", response.body
    assert_equal @subject.id, session[:hq_warned_person_id]
    # A live reply replaces the row and the Unread count in the person's list here.
    assert_select "turbo-cable-stream-source[channel=MailboxStreamsChannel][signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@subject, :messages, "hq"])
  end

  # Turbo submits a form accepting turbo-stream first, and the GET that follows
  # create's redirect keeps that Accept. The thread page has no stream answer,
  # so it renders the page, which needs the shell.
  test "sending from the HQ window lands on the thread page inside the shell" do
    turbo_accept = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    post hq_messages_path(@subject, direction: "to"),
         params: { message_form: { callsigns: [@other.callsign], subject: "Relay", body: "HQ window relay" } },
         headers: turbo_accept
    assert_response :redirect

    get response.location, headers: turbo_accept

    assert_response :success
    assert_match "Switch to Person Manage", response.body
  end

  test "the index keeps its shell whatever frame a request names" do
    get hq_messages_path(@subject), headers: { "Turbo-Frame" => "messages-pane" }

    assert_response :success
    assert_match "Switch to Person Manage", response.body
  end

  test "the thread page's list frame answers without the shell" do
    create_message(@other, @subject, "Listed", "Body")

    get hq_messages_path(@subject, folder: PersonMessage::FOLDER_INBOX),
        headers: { "Turbo-Frame" => "messages-conversation-list" }

    assert_response :success
    assert_select "turbo-frame#messages-conversation-list a.review-line"
    assert_no_match "Switch to Person Manage", response.body
    assert_nil session[:hq_warned_person_id]
  end

  # The hits are the person_message fixtures: the full-text index sees no row a test creates.
  test "a search of the person's mail answers the list frame without the shell" do
    owner = person(:inactive_ranger)

    get hq_messages_path(owner, q: "khaki"), headers: { "Turbo-Frame" => "messages-conversation-list" }

    assert_response :success
    assert_select "a.review-line", count: 1
    assert_select "a.review-line[href=?]",
                  hq_message_path(owner, person_message(:search_khaki_notes), folder: PersonMessage::FOLDER_INBOX, q: "khaki")
    assert_no_match "Switch to Person Manage", response.body
  end

  test "the search field's suggestions answer as JSON, without the shell" do
    owner = person(:inactive_ranger)

    get suggest_hq_messages_path(owner, q: "ran")
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal %w[ran RANGER1], response.parsed_body["items"].pluck("value")
    assert_nil session[:hq_warned_person_id]
  end

  test "a thread that cannot be shown is refused in the pane, without the shell" do
    message = create_message(@other, @viewer, "Private", "Not the subject's thread")

    get hq_message_path(@subject, message), headers: { "Turbo-Frame" => "messages-pane" }

    assert_response :success
    assert_select "turbo-frame#messages-pane [role=status]", text: /Invalid message id/
    assert_no_match "Switch to Person Manage", response.body
  end

  test "a group thread the person is not in is refused inside the hq namespace" do
    top = create_group_thread(@other, @viewer)

    get hq_message_path(@subject, top)
    assert_redirected_to hq_messages_path(@subject)

    get hq_message_path(@subject, top), headers: { "Turbo-Frame" => "messages-pane" }
    assert_response :success
    assert_select "#messages-pane", text: /Invalid message id/
  end

  test "a reply from the HQ window in a group thread is the person's, to every other member" do
    top = create_group_thread(@other, @subject, @viewer)

    notified = capture_group_notifies do
      post create_reply_hq_message_path(@subject, top), params: { message_reply_form: { reply: "At the window" } }
    end

    reply = top.replies.reload.last
    assert_equal [@subject.id, @subject.id, @viewer.id], [reply.person_id, reply.sender_person_id, reply.creator_person_id]
    assert_equal [@other, @viewer].map(&:id).sort, notified.sort
    # Written as the person, it leaves their unread alone (ruling D3): they never read the thread.
    assert_nil top.member(@subject.id).reload.last_read_message_id
    assert_includes PersonMessage.unread_for_person(@subject.id), top
  end

  private

  def create_message(sender, recipient, subject, body)
    PersonMessage.create!(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: recipient.id,
      creator_person_id: sender.id,
      sender_person_id: sender.id,
      sender_type: PersonMessage::SENDER_TYPE_PERSON,
      subject: subject,
      body: body
    ).reload
  end
end
