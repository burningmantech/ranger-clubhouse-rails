# frozen_string_literal: true

class SettingsSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :filter, :string
  validates :filter, presence: true, length: { minimum: 2, maximum: 100 }
end
