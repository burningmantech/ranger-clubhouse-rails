# frozen_string_literal: true

# What the Add Passkey page collects. It carries no rules of its own: the
# nickname's belong to PersonPasskey, and the password is checked against the
# person who typed it (Passkeys::Registration).
class PasskeyForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :nickname, :string
  attribute :current_password, :string
  # What the device made, put here by the page's script once it has.
  attribute :credential, :string
end
