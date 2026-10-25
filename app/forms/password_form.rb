# frozen_string_literal: true

class PasswordForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :old_password, :string
  attribute :password, :string

  validates :old_password, presence: true
  validates :password, presence: true, confirmation: true, length: { minimum: 8, maximum: 80 }
end
