# frozen_string_literal: true

require "test_helper"

class Communication::RbsBroadcastsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include RbsTestHelper
  include ActiveJob::TestHelper
  include SesTestHelper
  include EmailSuppressionTestHelper

  setup do
    Rails.cache.clear
    Current.reset
    ActionMailer::Base.deliveries.clear
    ensure_rbs_roles

    @admin = person(:active_ranger)
    @team_lead = person(:retired_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@team_lead, Role::MEGAPHONE_TEAM_ONPLAYA)
    enable_on_playa_roles

    @position = positions(:ood_position)
    @holder = rbs_holder("Holder", @position)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # ==========================================================================
  # Access
  # ==========================================================================

  test "denies access without a broadcasting role" do
    sign_in_as(@outsider)

    get communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)

    assert_redirected_to me_root_path
  end

  test "a kind the reader may not send is refused" do
    sign_in_as(@team_lead)

    get communication_rbs_new_broadcast_path(Broadcast::TYPE_EMERGENCY)

    assert_redirected_to me_root_path
    assert_equal "You are not authorized to send that kind of broadcast.", flash[:error]
  end

  test "a kind that does not exist goes back to the launchpad" do
    get communication_rbs_new_broadcast_path("nonsense")

    assert_redirected_to communication_rbs_root_path
    assert_equal "That kind of broadcast does not exist.", flash[:error]
  end

  test "the kind sent from the shift editor has no page of its own" do
    get communication_rbs_new_broadcast_path(Broadcast::TYPE_SLOT_EDIT)

    assert_redirected_to communication_rbs_root_path
  end

  # ==========================================================================
  # The form
  # ==========================================================================

  test "the form offers the alert types this kind may be sent under" do
    get communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)

    assert_response :success
    assert_select "select#broadcast_alert_id option[value=?]", Alert::SHIFT_MUSTER.to_s
    assert_select "select#broadcast_alert_id option[value=?]", Alert::EMERGENCY_BROADCAST.to_s, false
  end

  test "a short broadcast asks for one message and no channels" do
    get communication_rbs_new_broadcast_path(Broadcast::TYPE_EMERGENCY)

    assert_response :success
    assert_select "textarea#broadcast_sms_message"
    assert_select "input#broadcast_send_clubhouse", false
  end

  test "the form starts on the active status" do
    get communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)

    assert_select "input[name=?][value=?][checked=checked]", "broadcast[statuses][]", Person::ACTIVE
  end

  # Turbo throws away a 200 sent back to a form, so a redraw returned as a
  # fresh page never reaches the reader.
  test "a redraw answering a POST is not returned as a fresh page" do
    post communication_rbs_edit_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position)

    assert_response :unprocessable_entity
    assert_select "textarea#broadcast_sms_message"
    # The picker's count comes back rendered, and announced when it changes.
    assert_select "[data-position-picker-target=count][aria-live=polite]",
                  text: "1 of #{css_select("[data-position-picker-target=checkbox]").size} selected"
  end

  test "the form itself is a plain page" do
    get communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)

    assert_response :success
  end

  test "choosing a position brings back its shifts with everything else kept" do
    slot = Slot.create!(position: @position, begins: Current.time + 2.days,
                        ends: Current.time + 2.days + 8.hours, description: "Morning",
                        max: 10, begins_year: Current.year, active: true)
    PersonSlot.create!(person_id: @holder.id, slot_id: slot.id)

    post communication_rbs_edit_broadcast_path(Broadcast::TYPE_SLOT),
         params: { broadcast: { slot_position_id: @position.id, alert_id: Alert::SHIFT_CHANGE,
                                sms_message: "kept" } }

    assert_response :unprocessable_entity
    assert_select "select#broadcast_slot_id option[value=?]", slot.id.to_s
    assert_select "textarea#broadcast_sms_message", text: "kept"
  end

  # ==========================================================================
  # Reviewing
  # ==========================================================================

  test "reviewing lists the recipients and sends nothing" do
    assert_no_difference "Broadcast.count" do
      post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(@position)
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: /Team or Position/
    assert_match @holder.callsign, response.body
  end

  test "reviewing carries every value forward as a hidden field" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position)

    assert_select "input[type=hidden][name=?][value=?]", "broadcast[sms_message]", "Muster at HQ now"
    assert_select "input[type=hidden][name=?][value=?]", "broadcast[position_ids][]", @position.id.to_s
  end

  test "reviewing without a message shows the error and no recipients" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, sms_message: "", subject: "", message: "")

    assert_response :unprocessable_entity
    assert_select "#form-error-summary"
    assert_match "Enter the text message to send.", response.body
  end

  test "a text longer than one message is refused" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, sms_message: "x" * (Rbs::SMS_LIMIT + 1))

    assert_response :unprocessable_entity
    assert_match "The text message is longer than one message allows.", response.body
  end

  test "a broadcast that reaches no one says so rather than sending" do
    empty_position = Position.create!(title: "No one Holds This", active: true, count_hours: false)

    assert_no_difference "Broadcast.count" do
      post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(empty_position)
    end

    assert_response :unprocessable_entity
    assert_match "No one matches what you chose", response.body
  end

  # Read as position 0, junk used to pass the check for a chosen position and
  # then find no one.
  test "position ids that are not ids count as none chosen" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, position_ids: ["", "abc", "7x"])

    assert_response :unprocessable_entity
    assert_match "Choose at least one position.", response.body
    assert_no_match "No one matches what you chose", response.body
  end

  # The label fits a bounce and a spam report alike: the record does not say
  # which. The person's page does.
  test "reviewing names an address that bounced or was reported as spam, and leaves it out of the emails" do
    suppress_email(@holder.email)

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION), params: rbs_position_params(@position)

    assert_response :unprocessable_entity
    assert_select "tr:has(th[scope=row]) td .text-stone-subtle", text: "bounce or spam report on file", count: 1
    assert_select ".box-warning", text: /1 by text, 0 by email/
  end

  # A channel the broadcast doesn't use says so in every row, rather than
  # giving reasons for an email that was never going out.
  test "reviewing a broadcast that sends no email reads not used in the Email column" do
    suppress_email(@holder.email)

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, send_email: "0")

    assert_response :unprocessable_entity
    assert_select "tr:has(th[scope=row]) td .text-stone-subtle", text: "not used", count: 1
    assert_not_includes response.body, "bounce or spam report on file"
    assert_select "tr:has(th[scope=row]) td", text: /yes/, count: 1
    assert_select ".box-warning", text: /1 by text, 0 by email/
  end

  test "reviewing a Clubhouse-message-only broadcast reads not used in both channel columns" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, send_sms: "0", send_email: "0", send_clubhouse: "1")

    assert_response :unprocessable_entity
    rows = css_select("tr:has(th[scope=row])").size

    assert_operator rows, :>=, 1
    assert_select "tr:has(th[scope=row]) td .text-stone-subtle", text: "not used", count: rows * 2
    assert_select "tr:has(th[scope=row]) td", text: /yes/, count: 0
    assert_select ".box-warning", text: /0 by text, 0 by email, and \d+ by Clubhouse message/
  end

  # On site with no number, and an address that bounced: an emergency lists
  # them, and neither channel reaches them. The setup's Rangers are not on site,
  # so an emergency lists only the people a test puts there.
  def alone_on_site
    rbs_person("Alone", on_site: true, sms: "").tap { |alone| suppress_email(alone.email) }
  end

  test "reviewing an emergency counts only the people it reaches, and names the rest" do
    rbs_person("Heard", on_site: true)
    alone_on_site

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_EMERGENCY), params: { broadcast: { sms_message: "All hands" } }

    assert_response :unprocessable_entity
    assert_select ".box-warning", text: /Sending reaches 1 person:\s+1 by text, 1 by email\.\s+1 person on the list can.t be reached by text or email: Alone\./
    assert_select "input[type=submit][value=?]", "Send to 1 person"
    assert_match "Recipients (2)", response.body
  end

  # Nothing stops it: the list isn't empty, so "No one matches" would be untrue.
  test "an emergency that reaches no one on its list still goes to review, to send to 0 people" do
    alone_on_site

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_EMERGENCY), params: { broadcast: { sms_message: "All hands" } }

    assert_response :unprocessable_entity
    assert_no_match "No one matches what you chose", response.body
    assert_select "input[type=submit][value=?]", "Send to 0 people"
    assert_select ".box-warning", text: /1 person on the list can.t be reached by text or email: Alone\./
  end

  # Neither text nor email reaches the one person listed, but the Clubhouse
  # message does, so the review counts them and names no one.
  test "reviewing a Clubhouse-message-only broadcast counts everyone on the list, and names no one" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, send_sms: "0", send_email: "0", send_clubhouse: "1")

    assert_response :unprocessable_entity
    assert_select ".box-warning", text: /Sending reaches 1 person:/
    assert_select "input[type=submit][value=?]", "Send to 1 person"
    assert_not_includes response.body, "reached by text or email"
  end

  # ==========================================================================
  # Sending
  # ==========================================================================

  test "sending records the broadcast and reports what was queued" do
    assert_difference "Broadcast.count", 1 do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(@position)
    end

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match @holder.callsign, response.body

    broadcast = Broadcast.order(id: :desc).first

    assert_equal @admin.id, broadcast.sender_id
    assert_equal "Muster at HQ now", broadcast.sms_message
    assert_equal 1, BroadcastMessage.where(broadcast_id: broadcast.id).count
  end

  test "the sent page names an address that bounced or was reported as spam" do
    suppress_email(@holder.email, reason: EmailSuppression::COMPLAINT)

    post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION), params: rbs_position_params(@position)

    assert_response :unprocessable_entity
    assert_select "td .text-stone-subtle", text: "bounce or spam report on file", count: 1
  end

  # The fixtures start with every sandbox on, so the text is recorded sent and
  # the success callout shows.
  test "the sent page counts only the people an emergency reached, and names the rest" do
    rbs_person("Heard", on_site: true)
    alone_on_site

    assert_difference "Broadcast.count", 1 do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_EMERGENCY), params: { broadcast: { sms_message: "All hands" } }
    end

    assert_response :unprocessable_entity
    assert_select ".box-success", text: /Broadcast sent\s+to 1 person\./
    assert_select ".box-success", text: /1 person on the list can.t be reached by text or email: Alone\./
    assert_match "Delivery (2)", response.body
    assert_equal 2, Broadcast.order(id: :desc).first.recipient_count, "the stored count stays the list"
  end

  test "sending an invalid broadcast writes nothing" do
    assert_no_difference "Broadcast.count" do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(@position, sms_message: "", subject: "", message: "")
    end

    assert_response :unprocessable_entity
  end

  test "a team lead may not send to a position they do not manage" do
    sign_in_as(@team_lead)

    assert_no_difference "Broadcast.count" do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(@position)
    end

    assert_response :unprocessable_entity
    assert_match "a team you manage", response.body
  end

  # The review names every recipient, so reaching it for someone else's team
  # hands over the roster whether or not the send that follows is refused.
  test "a team lead may not review a position they do not manage" do
    sign_in_as(@team_lead)

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position)

    assert_response :unprocessable_entity
    assert_match "a team you manage", response.body
    assert_no_match(/#{@holder.callsign}/, response.body)
  end

  # A shift reaches a team without ever naming its position, so the shift has to
  # be checked too.
  test "a team lead may not send to a shift whose position they do not manage" do
    slot = Slot.create!(position: @position, begins: Current.time + 2.days,
                        ends: Current.time + 2.days + 8.hours, description: "Morning",
                        max: 10, begins_year: Current.year, active: true)
    PersonSlot.create!(person_id: @holder.id, slot_id: slot.id)
    sign_in_as(@team_lead)

    assert_no_difference "Broadcast.count" do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_SLOT),
           params: { broadcast: { alert_id: Alert::SHIFT_CHANGE, slot_id: slot.id,
                                  slot_position_id: @position.id,
                                  send_sms: "1", send_email: "0", send_clubhouse: "0",
                                  sms_message: "The shift moved",
                                  expires_at: (Current.time + 12.hours).strftime("%Y-%m-%d %H:%M") } }
    end

    assert_response :unprocessable_entity
    assert_match "a team you manage", response.body
  end

  # The integer attribute reads a muster position of "abc" as 0, and 0 is what
  # fails the guard's count. Read as an id list, it would be no positions, and
  # no positions managed out of none passes.
  test "a team lead's muster position that is not an id is refused" do
    sign_in_as(@team_lead)

    assert_no_difference "Broadcast.count" do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_RECRUIT_POSITION),
           params: { broadcast: { position_id: "abc",
                                  send_sms: "1", send_email: "0", send_clubhouse: "0",
                                  sms_message: "Muster at HQ now",
                                  expires_at: (Current.time + 12.hours).strftime("%Y-%m-%d %H:%M") } }
    end

    assert_response :unprocessable_entity
    assert_match "a team you manage", response.body
  end

  test "a team lead may send to a position on a team they manage" do
    team = Team.create!(title: "Broadcast Test Team", type: Team::TYPE_TEAM)
    @position.update!(team_id: team.id)
    TeamManager.create!(team_id: team.id, person_id: @team_lead.id)
    sign_in_as(@team_lead)

    assert_difference "Broadcast.count", 1 do
      post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
           params: rbs_position_params(@position)
    end

    assert_response :unprocessable_entity
  end

  test "nothing is delivered while the sandbox is on" do
    with_ses do |calls|
      perform_enqueued_jobs do
        post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
             params: rbs_position_params(@position, send_email: "1")
      end

      assert_empty calls
    end
  end

  # ==========================================================================
  # What the sender is told about sandboxes and the test address
  # ==========================================================================

  def sandboxes_off
    sandbox_off(Setting::BROADCAST_SMS_SANDBOX, Setting::BROADCAST_MAIL_SANDBOX, Setting::BROADCAST_CLUBHOUSE_SANDBOX)
  end

  test "reviewing with the sandbox on says what is recorded but not delivered" do
    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION), params: rbs_position_params(@position)

    assert_includes response.body, "Sandbox Mode Is On"
    assert_includes response.body, "Text messages, emails, and Clubhouse messages are recorded but not delivered."
  end

  test "reviewing with a test address says where the emails go" do
    sandboxes_off
    set_test_address("test+?@example.com")

    post communication_rbs_review_broadcast_path(Broadcast::TYPE_POSITION), params: rbs_position_params(@position)

    assert_response :unprocessable_entity
    assert_includes response.body, "Emails Go to the Test Address"
    assert_includes response.body, "<strong>test+?@example.com</strong>"
    assert_not_includes response.body, "recorded but not delivered",
                        "a test address delivers, so it must not read as a sandbox"
  end

  test "the sent page says the emails go to the test address" do
    sandboxes_off
    set_test_address("test+?@example.com")

    post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION),
         params: rbs_position_params(@position, send_sms: "0")

    assert_response :unprocessable_entity
    assert_match(/Emails go to <strong>test\+\?@example\.com<\/strong>/, response.body)
    assert_not_includes response.body, "recorded but not delivered"
  end

  test "the sent page with the sandbox on says what was recorded but not delivered" do
    post communication_rbs_broadcasts_path(Broadcast::TYPE_POSITION), params: rbs_position_params(@position)

    assert_includes response.body, "Text messages, emails, and Clubhouse messages were recorded but not delivered."
  end

  test "the form says where emails go while a test address is set, and that the rest goes out" do
    sandboxes_off
    set_test_address("test+?@example.com")

    get communication_rbs_new_broadcast_path(Broadcast::TYPE_POSITION)

    assert_includes response.body, "<strong>test+?@example.com</strong>"
    assert_includes response.body, "Anything else you send goes out for real.",
                    "a sender who reads \"test\" must not assume the texts are one too"
  end
end
