# frozen_string_literal: true

class PersonAsset < ApplicationRecord
  self.table_name = "person_asset"
  self.audit_model = true

  RELATIONSHIPS = [
    :asset,
    :attachment,
    :person,
    :check_out_person,
    :check_in_person
  ].freeze

  belongs_to :asset
  belongs_to :person
  belongs_to :attachment, class_name: "AssetAttachment", optional: true
  belongs_to :check_out_person, class_name: "Person", foreign_key: :check_out_person_id, optional: true
  belongs_to :check_in_person, class_name: "Person", foreign_key: :check_in_person_id, optional: true

  validates :person_id, presence: true
  validates :asset_id, presence: true

  before_validation :normalize_optional_fields

  class << self
    def find_for_query(query = {})
      params = (query || {}).to_h.with_indifferent_access

      scope = includes(RELATIONSHIPS)
      scope = scope.where(person_id: params[:person_id]) if params[:person_id].present?
      scope = scope.where_year("checked_out", params[:year]) if params[:year].present?
      scope.order(:checked_out)
    end

    def retrieve_type_for_person_ids(type, person_ids)
      return {} if person_ids.blank?

      joins(:asset)
        .includes(:asset)
        .where_year("checked_out", Current.year)
        .where(checked_in: nil, person_id: person_ids)
        .where(asset: { type: type })
        .group_by(&:person_id)
    end

    def retrieve_history(asset_id)
      where(asset_id:)
        .includes(:person, :attachment, :check_out_person, :check_in_person)
        .order(:checked_out)
    end

    def find_checked_out_person(asset_id)
      where(asset_id:, checked_in: nil)
        .includes(:person)
        .first
    end

    alias_method :findForQuery, :find_for_query
    alias_method :retrieveTypeForPersonIds, :retrieve_type_for_person_ids
    alias_method :retrieveHistory, :retrieve_history
    alias_method :findCheckedOutPerson, :find_checked_out_person
  end

  def load_relationships
    ActiveRecord::Associations::Preloader.new(records: [self], associations: RELATIONSHIPS).call
  end

  alias_method :loadRelationships, :load_relationships

  def duration
    ((checked_in || Current.time) - (checked_out || Current.time)).abs.to_i
  end

  private

  def normalize_optional_fields
    self.attachment_id = attachment_id.presence
  end
end
