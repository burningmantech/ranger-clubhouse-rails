# frozen_string_literal: true

class PersonMotd < ApplicationRecord
  self.table_name = "person_motd"
  self.primary_key = [:person_id, :motd_id]

  belongs_to :person
  belongs_to :motd

  validates :person_id, presence: true
  validates :motd_id, presence: true

  def self.toggle_read!(person_id, motd_id)
    if (record = find_by(person_id:, motd_id:))
      record.destroy!
      false
    else
      record = new(person_id:, motd_id:, read_at: Current.time)
      record.save!
      true
    end
  end
end
