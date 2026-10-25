# frozen_string_literal: true

class PositionLineup < ApplicationRecord
  self.table_name = "position_lineup"

  has_many :position_lineup_members, dependent: :destroy, class_name: "PositionLineupMember"
  has_many :positions, through: :position_lineup_members

  validates :description, presence: true

  def self.find_for_query(query)
    scope = includes(:positions)
    position_id = query[:position_id]

    if position_id.present?
      scope = scope.joins(:position_lineup_members).where(position_lineup_member: { position_id: })
    end

    scope.order(:description)
  end

  def self.retrieve_associated_positions(position_id)
    lineup_id = PositionLineupMember.where(position_id: position_id).pick(:position_lineup_id)

    return nil unless lineup_id

    positions = Position.joins(:position_lineup_members)
                        .where(position_lineup_member: { position_lineup_id: lineup_id })
                        .where.not(id: position_id)
                        .select("position.id", "position.title")
                        .order(:title)

    positions.empty? ? nil : positions
  end
end
