# frozen_string_literal: true

# A named collection of assets of one type ("Operations", "SITE"), picked on
# the asset form. Groups span years: an asset row is one event year's, its
# group is not. A retired group is marked inactive rather than deleted, so the
# assets of past years keep their group.
class AssetGroup < ApplicationRecord
  self.table_name = "asset_group"
  self.audit_model = true
  self.inheritance_column = :none

  IN_USE = "This group has assets. Mark it inactive, or merge it into another group."
  PROVISIONED = "This group has provisions. Mark it inactive, or merge it into another group."
  TYPE_LOCKED = "The type cannot change while assets use this group."
  TYPE_LOCKED_BY_PROVISIONS = "The type cannot change while provisions use this group."

  has_many :assets
  # Radio group provisions (Provision::RADIO_GROUP) granting a radio from this group.
  has_many :provisions

  normalizes :title, with: ->(title) { title.squish }

  # Only when it changes: a group the backfill made from an asset type no
  # longer on the list can still be renamed and retired.
  validates :type, inclusion: { in: Asset::TYPES, message: "Pick an asset type from the list." }, if: :type_changed?
  validates :title, presence: true, uniqueness: { scope: :type }
  validate :type_stays_while_in_use, on: :update

  before_destroy :refuse_while_in_use

  scope :active, -> { where(active: true) }
  scope :by_title, -> { order(:title) }

  # +groups+ as grouped_options_for_select wants them: "Active" before
  # "Inactive", an empty half left out.
  def self.grouped_options(groups)
    active, inactive = groups.partition(&:active)
    { "Active" => active, "Inactive" => inactive }
      .reject { |_label, list| list.empty? }
      .transform_values { |list| list.map { |group| [group.title, group.id] } }
  end

  # Moves every asset of this group, in any year, and every provision that
  # grants a radio from it, to +target+ and deletes this group. Bulk updates:
  # the action log gets one row for the merge, none per asset or provision.
  # Answers the number of assets moved.
  def merge_into!(target)
    raise ArgumentError, "A group cannot be merged into itself." if target.id == id
    raise ArgumentError, "Both groups must be for the same asset type." if target.type != type

    transaction do
      moved = Asset.where(asset_group_id: id).update_all(asset_group_id: target.id)
      provisions = Provision.where(asset_group_id: id).update_all(asset_group_id: target.id)
      target.update!(notes: [target.notes.presence, notes.presence].compact.join("\n\n")) if notes.present?
      ActionLog.record(Current.person, "asset-group-merge", nil,
                       { from_id: id, from_title: title, into_id: target.id, into_title: target.title, assets: moved,
                         provisions: })
      destroy!
      moved
    end
  end

  private

  def refuse_while_in_use
    message = if assets.exists?
                IN_USE
              elsif provisions.exists?
                PROVISIONED
              end
    return unless message

    errors.add(:base, message)
    throw :abort
  end

  def type_stays_while_in_use
    return unless type_changed?

    errors.add(:type, TYPE_LOCKED) if assets.exists?
    errors.add(:type, TYPE_LOCKED_BY_PROVISIONS) if provisions.exists?
  end
end
