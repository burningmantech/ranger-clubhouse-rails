# frozen_string_literal: true

class MessageReplyForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :reply, :string
  # The newest message the thread showed when the form was drawn: a reply
  # marks its author read through it and no further (review finding 10), so a
  # reply that landed unseen since, a live card the cable dropped, stays New.
  attribute :shown_through, :integer
  # The team the reply is written as, one of the thread's the author is on now
  # (MessagesConcern#reply_team), or nil for their own name. Drawn with the
  # team chosen (MessagesConcern#new_reply_form).
  attribute :as_team_id, :integer
  validates :reply, message_text: true
end
