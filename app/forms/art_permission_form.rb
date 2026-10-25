# frozen_string_literal: true

# Form object for the tool that mints the set of ART permissions belonging to a
# training position.
class ArtPermissionForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :position_id, :integer

  # errors.format drops the attribute name, so the message stands on its own.
  validates :position_id, presence: { message: "Select the training position to create permissions for." }
end
