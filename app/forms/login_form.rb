# frozen_string_literal: true

class LoginForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  attribute :password, :string
  validates :password, presence: true, length: { minimum: 6, maximum: 100 }
end
