# frozen_string_literal: true

class Award < ApplicationRecord
  self.table_name = "award"

  has_many :person_award, dependent: :delete_all

  validates :title, presence: true
  validates :description, presence: true
end
