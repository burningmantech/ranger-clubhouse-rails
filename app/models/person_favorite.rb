# frozen_string_literal: true

# A menu link or category the person has starred in the mega menu. Links are
# keyed by their resolved URL path (e.g. "/me/timesheet"), categories by
# "category:<panel key>" (MegaMenu.category_key). Keys that no longer match a
# visible link or category are pruned when the menu is built.
class PersonFavorite < ApplicationRecord
  self.table_name = "person_favorite"

  belongs_to :person

  validates :path, presence: true

  # Drop the person's favorites that are no longer among the given visible
  # keys. Returns the keys removed.
  def self.prune_stale!(person_id, visible_paths, favorited_paths)
    stale = favorited_paths.reject { |path| visible_paths.include?(path) }
    where(person_id:, path: stale).delete_all if stale.any?
    stale
  end

  # Star / unstar a path. Returns true when the path is now favorited.
  def self.toggle!(person_id, path)
    if (record = find_by(person_id:, path:))
      record.destroy!
      false
    else
      create!(person_id:, path:)
      true
    end
  rescue ActiveRecord::RecordNotUnique
    # Concurrent double-toggle lost the insert race; the row exists, so the
    # path is favorited either way.
    true
  end
end
