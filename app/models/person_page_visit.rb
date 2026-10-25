# frozen_string_literal: true

# Tracks the most recent visit to each mega-menu page per person. Rows are
# unique on [person_id, path], so the table is inherently bounded by the
# number of menu links — no pruning needed.
class PersonPageVisit < ApplicationRecord
  self.table_name = "person_page_visit"

  belongs_to :person

  validates :path, presence: true

  # Record a visit, bumping visited_at when the row already exists.
  # Callback-free by design; called on every tracked page view.
  def self.record(person_id, path)
    upsert({ person_id:, path:, visited_at: Current.time })
  end
end
