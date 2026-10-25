# frozen_string_literal: true

class PersonPasswordForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :password, :string
  attribute :password_confirmation, :string

  validates :password, presence: true, confirmation: true, length: { minimum: 8, maximum: 80 }
  validates :password_confirmation, presence: true
end
