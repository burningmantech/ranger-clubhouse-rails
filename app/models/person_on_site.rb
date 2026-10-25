# frozen_string_literal: true

# When a person was marked on site or off site, and by whom. Written by
# Person#log_on_site_change. update_all skips that hook, so a bulk writer of
# on_site calls PersonOnSite.reconcile once it is done, as GroundHogDay and
# RedactDatabase do. PersonOnSiteTest fails a file that writes on_site with
# update_all or its kin and never calls it.
class PersonOnSite < ApplicationRecord
  self.table_name = "person_on_site"

  ON_SITE = "on-site"
  OFF_SITE = "off-site"
  ACTIONS = [ON_SITE, OFF_SITE].freeze

  belongs_to :person

  # The change a save just made to person.on_site. Stamped with the present
  # instant, as the action log is, so a Groundhog Day server records its
  # pinned time on both. creator_person_id is empty when no one was signed in,
  # and may name an account since deleted: the table carries no foreign key.
  def self.record(person, creator_person_id)
    create!(person:, creator_person_id:, action: person.on_site ? ON_SITE : OFF_SITE,
            created_at: Current.time)
  end

  # Ends every history on its person's flag after a bulk change to on_site: one
  # row, dated at and made by creator, for each person whose newest change says
  # otherwise. No history at all reads as off site.
  def self.reconcile(at:, creator: nil)
    latest = order(:created_at, :id).pluck(:person_id, :action).to_h
    on_site = Person.where(on_site: true).pluck(:id).to_set
    rows = (latest.keys | on_site.to_a).filter_map do |person_id|
      action = on_site.include?(person_id) ? ON_SITE : OFF_SITE
      next if latest.fetch(person_id, OFF_SITE) == action

      { person_id:, creator_person_id: creator&.id, action:, created_at: at }
    end
    insert_all(rows) if rows.any?
  end

  # A person's changes, newest first unless told otherwise. Ties broken by
  # id: two changes can share a second.
  def self.history_for(person, direction = :desc)
    where(person:).order(created_at: direction, id: direction)
  end

  # {creator_person_id => changes} for the rows in scope, nil for changes no
  # one was signed in to make. Call it on an unordered relation:
  # history_for's ORDER BY has no place in a GROUP BY.
  def self.creator_counts = group(:creator_person_id).count

  # {id of an off-site change => seconds} from an on-site mark to the off-site
  # mark that ended it, over the whole history, so a filtered page still shows
  # each span. An off-site mark with no on-site mark before it -- the first
  # change, or a yearly reset after a missed mark -- has none.
  def self.on_site_durations(person)
    on_site_at = nil
    history_for(person, :asc).pluck(:id, :action, :created_at).each_with_object({}) do |(id, action, at), spans|
      if action == ON_SITE
        on_site_at ||= at
      elsif on_site_at
        spans[id] = at - on_site_at
        on_site_at = nil
      end
    end
  end

  def on_site? = action == ON_SITE
end
