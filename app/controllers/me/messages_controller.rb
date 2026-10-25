# frozen_string_literal: true

# MessagesController handles the modern messages interface.
# Provides inbox, sent, unread, and archive folders with message bubble UI.
# Supports person-to-person and RBS broadcast messages.
# Mailbox behavior lives in MessagesConcern; here the owner is the signed-in
# user, who composes as themselves, and ?to= addresses the compose page.
class Me::MessagesController < ApplicationController
  layout "me"

  include MessagesConcern

  # Only mailbox users (Person#mailbox_user?, the rule behind the Messages menu)
  # start a message; anyone sent one can still read and reply to it.
  before_action :require_mailbox_user, only: %i[new create find_recipient search_callsigns suggest_callsigns select_callsign]

  # /me/messages?to=CALLSIGN opens the compose page addressed to that callsign.
  # The redirect echoes `to` into a header, so it is cut to the longest callsign
  # there can be.
  def index
    if params[:to].present?
      return redirect_to new_message_path(to: params.expect(:to).to_s.first(Person::CALLSIGN_MAX_LENGTH))
    end

    super
  end

  # ?to= only suggests a recipient; create checks it again on send.
  def new
    super
    return if params[:to].blank?

    person, error = validate_person_for_messaging(params.expect(:to))
    @message_form.callsigns = [person.callsign] if person
    @message_form.errors.add(:callsigns, "#{error} Use Find #{lookup_role_label} to choose someone.") if error
  end

  private

  def require_mailbox_user
    not_authorized_redirect("Only Rangers and Echelon volunteers can send messages.") unless current_user.mailbox_user?
  end

  def message_owner
    current_user
  end

  def messages_route_prefix
    "me"
  end
end
