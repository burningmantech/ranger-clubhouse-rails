# frozen_string_literal: true

class PasswordResetForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
end
