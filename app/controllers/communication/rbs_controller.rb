# frozen_string_literal: true

# The Ranger Broadcast System launchpad: which kinds of broadcast the signed-in
# person may send, and the records of what has been sent.
class Communication::RbsController < ApplicationController
  layout "communication"

  # The Tech Team reads the records but sends nothing, so they are admitted
  # here -- this page is the only way in to the three record pages, and each
  # broadcast still carries its own permission.
  authorize_role Rbs::MEGAPHONE_ROLES + [Role::TECH_NINJA],
                 message: "Admin, a Megaphone role, or Tech Ninja is required to open this page."

  def index
    @types = Rbs.allowed_types
    @during_event = Rbs.during_event?
    @event_start = Rbs.event_dates.first
    @sandboxes, @email_test_address = RbsSandbox.notice
    @show_records = has_role?([Role::ADMIN, Role::TECH_NINJA])

    return unless @show_records

    @broadcast_count = Broadcast.operator.where_year("broadcast.created_at", Current.year).count
    @failed_count = Broadcast.with_failures.where_year("broadcast.created_at", Current.year).count
    @message_count = BroadcastMessage.for_year(Current.year).count
    @number_count = Person.live.where.not(sms_number: [nil, ""]).count
    @unusable_number_count = RbsPhoneNumbers.unusable_count
  end
end
