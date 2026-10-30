# frozen_string_literal: true

class PositionLineupMember < ApplicationRecord
  self.table_name = "position_lineup_member"
  self.primary_key = :position_id

  belongs_to :position_lineup
  belongs_to :position
end
