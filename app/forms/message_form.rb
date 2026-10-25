# frozen_string_literal: true

class MessageForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :subject, :string
  validates :subject, presence: true, length: { maximum: 255 }

  attribute :body, :string
  validates :body, message_text: true

  # The recipients chip field's callsigns (on the HQ window's relay,
  # MessageDirectionConcern "to", the one sender's), and a Cadre or Delegation
  # to send to. Each callsign is a lookup, so a crafted form cannot name
  # thousands.
  MAX_CALLSIGNS = 25
  attribute :callsigns, default: -> { [] }
  validates :callsigns, length: { maximum: MAX_CALLSIGNS, message: "A message can go to #{MAX_CALLSIGNS} callsigns at most." }
  attribute :team_id, :integer
  # The Cadre or Delegation the message is sent as, one the sender is on
  # (MessagesConcern#message_sender_team), or nil for their own name.
  attribute :sender_team_id, :integer

  # Addressed somehow: a callsign, a team to send to, or a team to send as (to
  # the team itself, then).
  validate :addressed

  # Every callsign named, each once, as typed.
  def recipient_callsigns
    callsigns.map { |value| value.to_s.strip }.compact_blank.uniq(&:downcase)
  end

  private

  def addressed
    return if recipient_callsigns.any? || team_id.present? || sender_team_id.present?

    errors.add(:callsigns, "Please enter a callsign")
  end
end
