# frozen_string_literal: true

# Shared setup for the Ranger Broadcast System tests: the permissions that open
# each page, and Rangers a broadcast can actually reach.
module RbsTestHelper
  # The two on-playa permissions are only held while this setting is on.
  def enable_on_playa_roles
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED)
           .update!(value: "true")
    Rails.cache.clear
  end

  def ensure_rbs_roles
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ensure_role(Role::MEGAPHONE, "Megaphone Full Access")
    ensure_role(Role::MEGAPHONE_TEAM_ONPLAYA, "Megaphone Team On Playa")
    ensure_role(Role::MEGAPHONE_EMERGENCY_ONPLAYA, "Megaphone Emergency On Playa")
  end

  # A Ranger a broadcast can reach. Copied from the fixture rather than built
  # from scratch: an account carries more required detail than a broadcast cares
  # about, and none of it is what these tests are checking.
  def rbs_person(callsign, status: Person::ACTIVE, on_site: false, sms: nil, verified: true)
    @rbs_counter = (@rbs_counter || 0) + 1
    copy = person(:active_ranger).dup
    copy.assign_attributes(
      callsign:, callsign_normalized: callsign.downcase, callsign_soundex: callsign.upcase,
      first_name: callsign, last_name: "Test", email: "#{callsign.downcase}@example.com",
      bpguid: "#{callsign}-GUID", status:, status_date: Current.today, on_site:,
      sms_number: sms.nil? ? "+1415555#{format("%04d", @rbs_counter)}" : sms,
      sms_verified: verified, sms_stopped: false
    )
    copy.save!(validate: false) unless copy.save
    copy
  end

  # A Ranger holding one position, which is the smallest audience a broadcast
  # can be aimed at.
  def rbs_holder(callsign, position)
    holder = rbs_person(callsign)
    PersonPosition.create!(person_id: holder.id, position_id: position.id)
    holder
  end

  # The values the compose form sends for a broadcast to one position.
  def rbs_position_params(position, **overrides)
    { broadcast: {
      alert_id: Alert::SHIFT_MUSTER,
      statuses: ["", Person::ACTIVE],
      position_ids: ["", position.id],
      position_signed_up: Rbs::SIGNED_UP_ANY,
      send_sms: "1", send_email: "1", send_clubhouse: "0",
      sms_message: "Muster at HQ now",
      subject: "Muster",
      message: "Please come in.",
      expires_at: (Current.time + 12.hours).strftime("%Y-%m-%d %H:%M")
    }.merge(overrides) }
  end

  # A broadcast that has already gone out, with a message per person.
  def rbs_broadcast(sender:, alert_id: Alert::SHIFT_MUSTER, failed: false, created_at: Current.time,
                    person: nil)
    broadcast = Broadcast.create!(
      sender_id: sender.id, alert_id:, sms_message: "A broadcast", subject: "A broadcast",
      email_message: "The body", recipient_count: 1, sent_sms: true, sent_email: false,
      sent_clubhouse: false, sms_failed: failed ? 1 : 0, created_at:
    )
    if person
      BroadcastMessage.create!(broadcast_id: broadcast.id, person_id: person.id,
                               address_type: "sms", address: person.sms_number,
                               direction: "outbound",
                               status: failed ? Broadcast::STATUS_SERVICE_FAIL : Broadcast::STATUS_SENT)
    end
    broadcast
  end
end
