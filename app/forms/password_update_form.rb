# frozen_string_literal: true

class PasswordUpdateForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :token, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  # Came from the welcome email (?welcome=1): the page reads as a welcome, not a
  # reset. Wording only -- the token is checked the same way either way.
  attribute :welcome, :boolean

  validates :token, presence: true
  validates :password, presence: true, confirmation: true, length: { minimum: 8, maximum: 80 }
  validates :password_confirmation, presence: true
end
