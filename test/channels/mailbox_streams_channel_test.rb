# frozen_string_literal: true

require "test_helper"

# A mailbox stream's signed name never expires, so each subscription asks
# again whether the viewer may still see the mailbox (owner's ruling
# 2026-10-19).
class MailboxStreamsChannelTest < ActionCable::Channel::TestCase
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    @owner = person(:active_ranger)
    @viewer = person(:ranger_with_custom_gender)
    @thread = PersonMessage.create!(person: @owner, sender_person: @viewer, creator_person: @viewer, subject: "Radios",
                                    body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
  end

  test "the owner hears their own mailbox, and no one else hears it as theirs" do
    assert listens?(@owner, [@owner, :messages, "me"])
    assert listens?(@owner, [@owner, @thread])
    assert_not listens?(@viewer, [@owner, :messages, "me"])
    assert_not listens?(@viewer, [@owner, @thread])
  end

  test "a Person viewer hears the mailbox while Event Management is theirs" do
    grant_role(@viewer, Role::EVENT_MANAGEMENT)
    assert listens?(@viewer, [@owner, :messages, "person"])
    assert listens?(@viewer, [@owner, @thread])
    assert_not listens?(@viewer, [@owner, :messages, "hq"])

    PersonRole.where(person_id: @viewer.id, role_id: Role::EVENT_MANAGEMENT).delete_all
    RoleManager.purge_person(@viewer.id)
    assert_not listens?(@viewer, [@owner, :messages, "person"])
    assert_not listens?(@viewer, [@owner, @thread])
  end

  test "an HQ viewer hears the mailbox with Shift Management while the window is on" do
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)
    assert listens?(@viewer, [@owner, :messages, "hq"])
    assert listens?(@viewer, [@owner, @thread])
    assert_not listens?(@viewer, [@owner, :messages, "person"])

    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")
    assert_not listens?(@viewer, [@owner, :messages, "hq"])
  end

  test "a name not signed by the app is refused" do
    stub_connection current_user: @owner
    subscribe signed_stream_name: "forged"
    assert subscription.rejected?
  end

  private

  def listens?(person, streamables)
    stub_connection current_user: person
    subscribe signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamables)
    subscription.confirmed?
  end
end
