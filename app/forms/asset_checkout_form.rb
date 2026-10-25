# frozen_string_literal: true

# Form object backing the asset checkout barcode form.
class AssetCheckoutForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :barcode, :string
  attribute :attachment_id, :string
  attribute :force, :string

  def self.model_name
    ActiveModel::Name.new(self, nil, "PersonAsset")
  end

  def persisted?
    false
  end
end
