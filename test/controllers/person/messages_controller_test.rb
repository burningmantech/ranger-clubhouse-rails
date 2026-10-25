# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class Person::MessagesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include GroupMessageTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    Current.reset

    @target = person(:active_ranger)              # the person being administered
    @other = person(:ranger_with_custom_gender)   # third-party ranger for lookups
    @manager = person(:echelon_ranger)            # granted EVENT_MANAGEMENT below

    # messaging_permitted? requires last_seen_at
    @target.update!(last_seen_at: 1.day.ago)
    @other.update!(last_seen_at: 1.day.ago)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::EVENT_MANAGEMENT_ON_PLAYA, "Event Management On Playa")

    grant_role(@manager, Role::EVENT_MANAGEMENT)
    sign_in_as(@manager)
    Current.person = @manager
  end

  teardown do
    Current.reset
  end

  # --- Team threads (.scratch/team-messaging/PRD.md, ruling R2) ---------------

  test "a team member's mailbox shows the manager who wrote a reply as the team, and offers the choice" do
    cadre = teams(:green_dot_cadre)
    [@target, @other].each { |member| join_team(member, cadre) }
    top = create_team_thread(@other, cadre)
    reply = create_group_reply(top, @other, as_team: cadre)

    get person_message_path(@target, top)
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply, :card)}",
                  text: /#{Regexp.escape(@other.callsign)}\s+Replied as Green Dot Cadre/
    assert_select "input[type=radio][name='message_reply_form[as_team_id]'][value='#{cadre.id}']"
  end

  # --- Access control ---------------------------------------------------------

  test "event management holder can view the mailbox" do
    get person_messages_path(@target)
    assert_response :success
  end

  test "event management on playa holder can view the mailbox while the on-playa setting is on" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    emop = person(:retired_ranger)
    grant_role(emop, Role::EVENT_MANAGEMENT_ON_PLAYA)
    sign_in_as(emop)

    get person_messages_path(@target)
    assert_response :success
  end

  # RoleManager drops the raw role off-season rather than let it past the gate
  # without the NDA check Event Management gets.
  test "event management on playa holder is denied off-season" do
    emop = person(:retired_ranger)
    grant_role(emop, Role::EVENT_MANAGEMENT_ON_PLAYA)
    sign_in_as(emop)

    get person_messages_path(@target)
    assert_redirected_to me_root_path
    assert_match(/Event Management permission/, flash[:error])
  end

  test "plain admin without event management is denied" do
    admin = person(:auditor_ranger)
    grant_role(admin, Role::ADMIN)
    sign_in_as(admin)

    get person_messages_path(@target)
    assert_redirected_to me_root_path
    assert_match(/Event Management permission/, flash[:error])
  end

  test "mentor without event management is denied" do
    mentor = person(:auditor_ranger)
    grant_role(mentor, Role::MENTOR)
    sign_in_as(mentor)

    get person_messages_path(@target)
    assert_redirected_to me_root_path
    assert_match(/Event Management permission/, flash[:error])
  end

  test "user without any role is denied" do
    sign_in_as(@other)

    get person_messages_path(@target)
    assert_redirected_to me_root_path
  end

  test "unauthenticated user is redirected to login" do
    sign_out

    get person_messages_path(@target)
    assert_redirected_to root_path
  end

  # --- Index -------------------------------------------------------------------

  test "index shows the person's inbox" do
    create_message(@other, @target, "Hello Target", "A message body")

    get person_messages_path(@target)
    assert_response :success
    assert_match "Hello Target", response.body
    assert_match "Send Message to #{@target.callsign}", response.body
    assert_match "Send Message from #{@target.callsign}", response.body
  end

  test "a thread's page offers both compose buttons too" do
    message = create_message(@other, @target, "Hello Target", "A message body")

    get person_message_path(@target, message)
    assert_response :success
    assert_select "a[href='#{new_person_message_path(@target, direction: "to")}']", text: "Send Message to #{@target.callsign}"
    assert_select "a[href='#{new_person_message_path(@target, direction: "from")}']", text: "Send Message from #{@target.callsign}"
  end

  test "index folders switch via turbo stream" do
    get person_messages_path(@target, folder: PersonMessage::FOLDER_SENT), as: :turbo_stream
    assert_response :success

    get person_messages_path(@target, folder: PersonMessage::FOLDER_UNREAD), as: :turbo_stream
    assert_response :success
  end

  test "index hides the send-to button when the person may not be messaged" do
    @target.update!(last_seen_at: nil)

    get person_messages_path(@target)
    assert_response :success
    assert_no_match "Send Message to #{@target.callsign}", response.body
    assert_match "Send Message from #{@target.callsign}", response.body
  end

  # --- Show / mailbox state (acts as the person) --------------------------------

  test "opening a message does not change the person's read state" do
    message = create_message(@other, @target, "Unread Subject", "Body")
    assert_not message.thread_read?(@target.id)

    get person_message_path(@target, message)
    assert_response :success
    assert_not message.reload.thread_read?(@target.id)
    # Replies land live in the person's view of the thread, and stay unread here.
    assert_select "turbo-cable-stream-source[channel=MailboxStreamsChannel][signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@target, message])
    assert_select "#messages-thread[role=log]"
    assert_select "[data-controller~=thread-live]", count: 0
  end

  test "a thread dates an earlier year's message with its year and this year's without" do
    message = create_message(@other, @target, "Old Subject", "Sent years ago")
    message.update_column(:created_at, Time.local(Current.year - 3, 6, 29, 21, 35))
    create_message(@target, @other, "Re: Old Subject", "Answered today", reply_to_id: message.id)

    get person_message_path(@target, message)
    assert_response :success
    stamps = css_select("#messages-thread article time").map { it.text.strip }
    assert_equal 2, stamps.size
    assert_match(/, #{Current.year - 3} @/, stamps.first)
    assert_no_match(/, \d{4} @/, stamps.last)
  end

  # Slice 6: the HQ window's loop -- hand over, mark read, next.
  test "Next Unread goes through the person's unread threads in the folder's order, then back to the list" do
    older = create_message(@other, @target, "Older", "Body")
    newest = create_message(@other, @target, "Newest", "Body")
    read = create_message(@other, @target, "Read", "Body")
    read.mark_thread_read!(@target.id)

    get person_message_path(@target, newest)
    assert_select "a[data-turbo-frame=messages-pane][href=?]", person_message_path(@target, older, folder: "inbox"),
                  text: /Next Unread/
    # Past the last, round to the first; from a thread no longer unread, the first.
    get person_message_path(@target, older)
    assert_select "a[href=?]", person_message_path(@target, newest, folder: "inbox"), text: /Next Unread/
    get person_message_path(@target, read)
    assert_select "a[href=?]", person_message_path(@target, newest, folder: "inbox"), text: /Next Unread/

    # Marked read in the pane, the header that comes back still knows what is next.
    post toggle_read_person_message_path(@target, newest), params: { folder: "inbox" }, as: :turbo_stream
    assert_select "turbo-stream[target=messages-panel-header] template a[href=?]",
                  person_message_path(@target, older, folder: "inbox"), text: /Next Unread/

    # With no other left, back to the list.
    get person_message_path(@target, older)
    assert_select "a", text: /Next Unread/, count: 0
    assert_select "a[data-turbo-frame=_top][href=?]", person_messages_path(@target, folder: "inbox"), text: /Back to Messages/
  end

  test "a thread the person does not participate in is rejected" do
    message = create_message(@other, @manager, "Private", "Not target's thread")

    get person_message_path(@target, message)
    assert_redirected_to person_messages_path(@target)
  end

  test "toggle read flips the person's read state" do
    message = create_message(@other, @target, "Toggle Me", "Body")

    post toggle_read_person_message_path(@target, message), as: :turbo_stream
    assert_response :success
    assert message.reload.thread_read?(@target.id)
  end

  test "toggle archive flips the person's archive state" do
    message = create_message(@other, @target, "Archive Me", "Body")

    post toggle_archive_person_message_path(@target, message), as: :turbo_stream
    assert_response :success
    assert message.reload.archived?(@target.id)
  end

  # --- Compose direction handling ------------------------------------------------

  test "new requires a valid direction" do
    get new_person_message_path(@target)
    assert_redirected_to person_messages_path(@target)
    assert_match(/Unknown message direction/, flash[:error])

    get new_person_message_path(@target, direction: "sideways")
    assert_redirected_to person_messages_path(@target)
  end

  test "new send-to is blocked when the person may not be messaged" do
    @target.update!(last_seen_at: nil)

    get new_person_message_path(@target, direction: "to")
    assert_redirected_to person_messages_path(@target)
    assert_match(/may not be messaged/, flash[:error])
  end

  test "new renders the compose form for both directions" do
    get new_person_message_path(@target, direction: "to")
    assert_response :success
    assert_match "Send Message to #{@target.callsign}", response.body
    # The relay's one sender: the chip field capped at one, Find Sender for a phone.
    assert_select "label[for=message_form_callsigns]", text: "From"
    assert_select "[data-controller=callsign-chips][data-callsign-chips-max-value=1] " \
                  "input#message_form_callsigns[placeholder='Choose a callsign…']:not([aria-label])"
    assert_select ".lg\\:hidden a", text: "Find Sender"
    assert_select "select[name='message_form[team_id]']", count: 0

    get new_person_message_path(@target, direction: "from")
    assert_response :success
    assert_match "Send Message from #{@target.callsign}", response.body
    assert_select "label[for=message_form_callsigns]", text: "To"
    assert_select "[data-controller=callsign-chips]:not([data-callsign-chips-max-value])"
    assert_select ".lg\\:hidden a", text: "Find Recipient"
  end

  test "find recipient modal carries the direction" do
    get find_recipient_person_messages_path(@target, direction: "to"), as: :turbo_stream
    assert_response :success
    assert_match "Find Sender", response.body
    assert_match "direction=to", response.body
  end

  test "a Find choice on the relay replaces its one sender; from the person it joins the chips" do
    { "to" => "update", "from" => "append" }.each do |direction, action|
      post select_callsign_person_messages_path(@target, direction:), params: { callsign: @other.callsign },
                                                                       as: :turbo_stream
      assert_select "turbo-stream[action=#{action}][target=message_form_callsigns_chips] template " \
                    "input[name='message_form[callsigns][]'][value=?]", @other.callsign
    end
  end

  test "a relay sent without a subject comes back with its sender's chip" do
    post person_messages_path(@target, direction: "to"),
         params: { message_form: { callsigns: [@other.callsign], subject: "", body: "Relay" } }
    assert_response :unprocessable_entity
    assert_select "#message_form_callsigns_chips input[name='message_form[callsigns][]'][value=?]", @other.callsign
  end

  test "select callsign tells a manager why a callsign can't be used" do
    post select_callsign_person_messages_path(@target, direction: "from"),
         params: { callsign: person(:deceased_ranger).callsign }, as: :turbo_stream
    assert_response :success
    assert_match "Person is deceased.", response.body
  end

  # --- Create ---------------------------------------------------------------------

  test "send-to creates a message to the person from the looked-up sender" do
    assert_difference -> { PersonMessage.count }, 1 do
      post person_messages_path(@target, direction: "to"),
           params: { message_form: { callsigns: [@other.callsign], subject: "Relay", body: "HQ window relay" } }
    end

    message = PersonMessage.order(:id).last
    assert_equal @target.id, message.person_id
    assert_equal @other.id, message.sender_person_id
    assert_equal @manager.id, message.creator_person_id
    assert_redirected_to person_message_path(@target, message)
  end

  test "send-from creates a message from the person to the looked-up recipient" do
    assert_difference -> { PersonMessage.count }, 1 do
      post person_messages_path(@target, direction: "from"),
           params: { message_form: { callsigns: [@other.callsign], subject: "Outbound", body: "Sent as the person" } }
    end

    message = PersonMessage.order(:id).last
    assert_equal @other.id, message.person_id
    assert_equal @target.id, message.sender_person_id
    assert_equal @manager.id, message.creator_person_id
    assert_redirected_to person_message_path(@target, message)
  end

  test "create with an unknown callsign re-renders the form" do
    assert_no_difference -> { PersonMessage.count } do
      post person_messages_path(@target, direction: "to"),
           params: { message_form: { callsigns: ["no such callsign"], subject: "Relay", body: "Body" } }
    end
    assert_response :unprocessable_entity
  end

  # --- Replies (sent as the person) -----------------------------------------------

  test "reply in a thread is sent as the person" do
    message = create_message(@other, @target, "Thread Top", "Body")

    post create_reply_person_message_path(@target, message),
         params: { message_reply_form: { reply: "Replying as the person" } }
    assert_redirected_to person_message_path(@target, message)

    reply = message.replies.reload.last
    assert_equal @target.id, reply.sender_person_id
    assert_equal @other.id, reply.person_id
    assert_equal @manager.id, reply.creator_person_id
  end

  # --- The Mail Desk workspace ---------------------------------------------------

  test "a pane frame request answers the pane alone and leaves the thread unread" do
    message = create_message(@other, @target, "Framed", "Body")

    get person_message_path(@target, message), headers: { "Turbo-Frame" => "messages-pane" }
    assert_response :success
    assert_select "turbo-frame#messages-pane [data-review-id='#{message.id}']"
    assert_select "h1", count: 0
    assert_select "[role=tablist]", count: 0
    assert_not message.reload.thread_read?(@target.id), "a frame request must not mark the person's thread read"
    assert_select "turbo-stream", count: 0
  end

  test "the list frame marks the open thread's row current in the person's list" do
    message = create_message(@other, @target, "Selected", "Body")

    get person_messages_path(@target, folder: PersonMessage::FOLDER_INBOX, selected: message.id),
        headers: { "Turbo-Frame" => "messages-conversation-list" }
    assert_response :success
    assert_select "a.review-line[aria-current=true][href=?]",
                  person_message_path(@target, message, folder: PersonMessage::FOLDER_INBOX)
  end

  # Viewing never marks read here, so the cards show what the person has not read.
  test "a card is chipped New only on a row the person has not read" do
    message = create_message(@other, @target, "Unread Subject", "Their message")
    create_message(@target, @other, "Re: Unread Subject", "The person's reply", reply_to_id: message.id)

    get person_message_path(@target, message)
    assert_response :success
    assert_select "#messages-thread article", count: 2
    assert_select "#messages-thread article .badge", text: "New", count: 1
    assert_select "#messages-thread article[class*='bg-warning/10']", count: 1 do
      assert_select ".badge", text: "New"
      assert_match "Their message", @selected.first.text
    end
  end

  # The hits are the person_message fixtures: the full-text index sees no row a test creates.
  test "a search lists the person's hits, linking inside the namespace" do
    owner = person(:inactive_ranger)

    get person_messages_path(owner, q: "dirt shift")

    assert_response :success
    assert_select "a.review-line", count: 2
    assert_select "a.review-line[href=?]",
                  person_message_path(owner, person_message(:search_dirt_swap), folder: PersonMessage::FOLDER_INBOX, q: "dirt shift")
    assert_select "mark.search-hit", text: "Dirt"
  end

  # --- Group threads ---------------------------------------------------------

  test "sending from the person may address several people as one shared thread" do
    third = person(:retired_ranger)
    third.update!(last_seen_at: 1.day.ago)

    notified = capture_group_notifies do
      post person_messages_path(@target, direction: "from"),
           params: { message_form: { callsigns: [@other.callsign, third.callsign], subject: "Crew", body: "Sent as them" } }
    end

    top = PersonMessage.order(:id).last
    assert top.group?
    assert_equal [@target.id, @target.id, @manager.id], [top.person_id, top.sender_person_id, top.creator_person_id]
    assert_equal [@target, @other, third].map(&:id).sort, top.members.pluck(:person_id).sort
    assert_equal [@other, third].map(&:id).sort, notified.sort
  end

  test "sending from the person may be sent as a Cadre they are on; the relay never is" do
    cadre = teams(:council_cadre) # @target is on it by fixture
    post person_messages_path(@target, direction: "from"),
         params: { message_form: { sender_team_id: cadre.id, callsigns: [@other.callsign], subject: "Crew", body: "As them" } }
    top = PersonMessage.order(:id).last
    assert_equal [PersonMessage::SENDER_TYPE_TEAM, cadre.id, @target.id, @manager.id, true],
                 [top.sender_type, top.sender_team_id, top.sender_person_id, top.creator_person_id, top.group?]

    get new_person_message_path(@target, direction: "to")
    assert_select "select[name='message_form[sender_team_id]']", count: 0
    assert_no_difference -> { PersonMessage.count } do
      post person_messages_path(@target, direction: "to"),
           params: { message_form: { sender_team_id: cadre.id, callsigns: [@other.callsign], subject: "Relay", body: "B" } }
    end
    assert_select "#form-error-summary", text: /A relayed message comes from one sender\./
  end

  # Review finding: the sync marked only messageable members, so an author who
  # never signed in stood beside the team they wrote as.
  test "a message sent as a Cadre for someone who never signed in names the Cadre alone to its recipient" do
    cadre = teams(:green_dot_cadre)
    PersonTeam.find_or_create_by!(person: @target, team: cadre)
    @target.update!(last_seen_at: nil)

    post person_messages_path(@target, direction: "from"),
         params: { message_form: { sender_team_id: cadre.id, callsigns: [@other.callsign], subject: "Crew", body: "As them" } }
    top = PersonMessage.order(:id).last
    assert_equal cadre.id, top.member(@target.id).team_id

    get person_message_path(@target, top)
    assert_equal "To: Green Dot Cadre, #{@other.callsign}", css_select("#messages-panel-header .text-lg").first.text.squish
    sign_in_as(@other)
    get me_message_path(top)
    assert_equal "From: Green Dot Cadre", css_select("#messages-panel-header .text-lg").first.text.squish
  end

  test "a relay to the person stays one-to-one" do
    third = person(:retired_ranger)
    third.update!(last_seen_at: 1.day.ago)

    assert_no_difference -> { PersonMessage.count } do
      post person_messages_path(@target, direction: "to"),
           params: { message_form: { callsigns: [@other.callsign, third.callsign], subject: "Relay", body: "B" } }
    end
    assert_select "#form-error-summary", text: /A relayed message comes from one sender\./
  end

  test "a group thread the person is not in cannot be opened from their mailbox" do
    top = create_group_thread(@other, person(:retired_ranger))

    get person_message_path(@target, top)
    assert_redirected_to person_messages_path(@target)
  end

  test "a manager reads a person's group thread without marking it read" do
    top = create_group_thread(@other, @target)

    get person_message_path(@target, top)
    assert_response :success
    assert_nil top.member(@target.id).reload.last_read_message_id
  end

  # A live reply replaces the row and the Unread count in each mailbox list
  # (PersonMessage#announce_to_recipient); this page listens to the person's.
  test "the mailbox listens on the person's list stream for this namespace" do
    get person_messages_path(@target)
    assert_select "turbo-cable-stream-source[signed-stream-name=?]",
                  Turbo::StreamsChannel.signed_stream_name([@target, :messages, "person"])
  end

  # A reply written here as the person marks nothing read for them (ruling D3),
  # as opening the thread here marks nothing: the row its broadcast sends them
  # is still unread.
  test "a group reply written as the person leaves the thread unread for them" do
    third = person(:plate_collision_ranger)
    top = create_group_thread(@other, @target, third)

    notified = capture_group_notifies do
      post create_reply_person_message_path(@target, top), params: { message_reply_form: { reply: "On it." } }
    end
    assert_equal [@other, third].map(&:id).sort, notified.sort

    # Without a block: everything the stream was sent.
    row = capture_turbo_stream_broadcasts([@target, :messages, "person"]).first.at_css("template a.review-line")
    assert_equal person_message_path(@target, top), row["href"]
    assert_includes row.classes, "messages-conversation-unread"
  end

  # Owner's ruling 2026-10-19 (review finding 9): a group row's author is not
  # checked, as a one-to-one sender never is. Both were refused before.
  test "a group reply written as a suspended Ranger is posted, as a one-to-one one is" do
    third = person(:plate_collision_ranger)
    top = create_group_thread(@other, @target, third)
    @target.update_column(:status, Person::SUSPENDED)

    assert_difference -> { top.replies.count }, 1 do
      capture_group_notifies do
        post create_reply_person_message_path(@target, top), params: { message_reply_form: { reply: "On it." } },
                                                             as: :turbo_stream
      end
    end
    assert_equal @target.id, top.replies.last.sender_person_id
  end

  test "a group message sent as a suspended Ranger is sent" do
    third = person(:plate_collision_ranger)
    third.update!(last_seen_at: 1.day.ago)
    @target.update_column(:status, Person::SUSPENDED)

    capture_group_notifies do
      post person_messages_path(@target, direction: "from"),
           params: { message_form: { callsigns: [@other.callsign, third.callsign], subject: "Radios", body: "Who has them?" } }
    end

    top = PersonMessage.order(:id).last
    assert_redirected_to person_message_path(@target, top)
    assert top.group?
    assert_equal [@target, @other, third].map(&:id).sort, top.members.pluck(:person_id).sort
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end

  def create_message(sender, recipient, subject, body, reply_to_id: nil)
    PersonMessage.create!(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: recipient.id,
      creator_person_id: sender.id,
      sender_person_id: sender.id,
      sender_type: PersonMessage::SENDER_TYPE_PERSON,
      subject: subject,
      body: body,
      reply_to_id: reply_to_id
    ).reload
  end
end
