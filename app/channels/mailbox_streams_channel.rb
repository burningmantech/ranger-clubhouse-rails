# frozen_string_literal: true

# The mailbox streams (common/messages/_workspace and _messages_panel): the
# list's [owner, :messages, namespace] and an open thread's [owner, thread].
# Turbo's own channel takes any name the app ever signed, and a signed name
# never expires, so a Person or HQ viewer who kept one would hear the
# mailbox's rows and cards after losing the role that showed it to them. Here
# each subscription asks again (owner's ruling 2026-10-19): the owner always,
# a viewer while Person › Messages or HQ › Messages would still open the
# mailbox for them. A subscription already open lasts until the cable
# reconnects.
class MailboxStreamsChannel < Turbo::StreamsChannel
  def subscribed
    stream = verified_stream_name_from_params
    return reject unless stream && may_listen?(stream)

    stream_from stream
  end

  private

  # A thread's name has no namespace: either page may show it.
  def may_listen?(stream)
    owner, _, namespace = stream.split(":")
    owner = GlobalID.parse(owner)
    return false unless owner&.model_name == "Person"
    return true if owner.model_id == current_user.id.to_s && namespace.in?([nil, "me"])

    case namespace
    when "person" then person_viewer?
    when "hq" then hq_viewer?
    when nil then person_viewer? || hq_viewer?
    else false
    end
  end

  # Person::MessagesController's gate, and HqConcern's.
  def person_viewer?
    roles.has_role?([Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA])
  end

  def hq_viewer?
    roles.has_role?([Role::ADMIN, Role::SHIFT_MANAGEMENT]) && Setting.get_value(Setting::HQ_WINDOW_INTERFACE_ENABLED)
  end

  def roles
    @roles ||= RoleManager.retrieve(current_user)
  end
end
