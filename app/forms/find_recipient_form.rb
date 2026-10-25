# frozen_string_literal: true

class FindRecipientForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :query, :string
  validates :query, presence: true, length: { minimum: 2, maximum: 100 }
end
