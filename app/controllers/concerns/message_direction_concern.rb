# frozen_string_literal: true

# The management view of someone else's mailbox — used by person/:id/messages
# and its HQ-window twin. A manager composes in one of two directions: TO the
# person from a looked-up callsign (an HQ-window relay), or FROM the person as
# if they authored it. Replies within a thread are sent as the person, or as a
# Cadre or Delegation of theirs in the thread (PersonMessage#reply_teams_for).
#
# MUST be included after MessagesConcern: these methods override that module's
# hook defaults, and Ruby resolves them in reverse inclusion order.
module MessageDirectionConcern
  extend ActiveSupport::Concern

  DIRECTION_TO = "to"
  DIRECTION_FROM = "from"
  DIRECTIONS = [DIRECTION_TO, DIRECTION_FROM].freeze

  included do
    before_action :set_direction, only: %i[new create find_recipient search_callsigns select_callsign]
  end

  private

  # Viewing must not silently clear the person's unread state; managers mark
  # messages read explicitly with the read toggle.
  def mark_read_on_view?
    false
  end

  def set_direction
    @direction = params[:direction]
    unless DIRECTIONS.include?(@direction)
      redirect_to messages_path, error: "Unknown message direction."
      return
    end

    if @direction == DIRECTION_TO && !message_owner.messaging_permitted?
      redirect_to messages_path, error: "#{message_owner.callsign} may not be messaged."
    end
  end

  def resolve_participants(lookup_person)
    @direction == DIRECTION_TO ? [lookup_person, message_owner] : [message_owner, lookup_person]
  end

  def direction_params
    { direction: @direction }
  end

  # The relay TO the person has one sender; FROM the person may go to several.
  def group_send_allowed?
    @direction == DIRECTION_FROM
  end

  def lookup_label
    @direction == DIRECTION_TO ? "From:" : "To:"
  end

  def lookup_role_label
    @direction == DIRECTION_TO ? "Sender" : "Recipient"
  end

  # Managers see a person's status anyway, so they get the reason.
  def recipient_refusal(reason)
    reason
  end
end
