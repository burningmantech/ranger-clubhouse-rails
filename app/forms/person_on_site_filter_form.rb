# frozen_string_literal: true

# The filters across the top of a person's site log.
class PersonOnSiteFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"
  SORT_OPTIONS = [["Newest first", "desc"], ["Oldest first", "asc"]].freeze
  # The creator filter's value for changes no one was signed in to make.
  NO_CREATOR = "none"
  # The days a date filter may name (1998 is the app's year floor, as in
  # ApplicationController.year_floor); the date inputs offer no others. A year
  # outside them is a typo that MariaDB would not refuse: it truncates the
  # datetime, so created_at >= '99999-01-01' matches every row and
  # created_at < '10000-01-01' (Through 9999-12-31) matches none.
  DATE_RANGE = Date.new(1998, 1, 1)..Date.new(2100, 12, 31)

  attribute :starts_on, :date # a date it cannot read comes out nil
  attribute :ends_on, :date
  # "marked", never "action": Rails overwrites params[:action] with the
  # action's own name, so a filter by that name would never apply.
  attribute :marked, :string
  attribute :creator, :string
  attribute :sort, :string

  # The creator filter's value for a creator_person_id.
  def self.creator_value(id) = id.nil? ? NO_CREATOR : id.to_s

  # creator_ids: the creator_person_id values this person's history holds, nil
  # for a change no one was signed in to make.
  def initialize(attributes = {}, creator_ids:)
    super(attributes)
    # Anything else -- the "all" a bare Apply sends, a typo -- filters nothing,
    # so it must not draw a chip claiming it did.
    self.starts_on = nil unless DATE_RANGE.cover?(starts_on)
    self.ends_on = nil unless DATE_RANGE.cover?(ends_on)
    self.marked = nil unless PersonOnSite::ACTIONS.include?(marked)
    self.creator = nil unless creator_ids.map { self.class.creator_value(it) }.include?(creator)
    self.sort = "desc" unless SORT_OPTIONS.rassoc(sort)
  end

  def apply(scope)
    scope = apply_all_but_creator(scope)
    creator ? scope.where(creator_person_id: creator_id) : scope
  end

  # Every filter except the creator: what the Marked By counts are taken under,
  # so each option promises the rows choosing it would show.
  def apply_all_but_creator(scope)
    # Whole days on the machine's local clock, which is how the database stores
    # times (see where_year): a Time.zone bound would land an hour off.
    scope = scope.where(created_at: starts_on.to_time..) if starts_on
    scope = scope.where(created_at: ...(ends_on + 1).to_time) if ends_on
    marked ? scope.where(action: marked) : scope
  end

  # The creator_person_id the creator filter names; nil for NO_CREATOR, and
  # while the filter is off.
  def creator_id = creator == NO_CREATOR ? nil : creator&.to_i

  # The filters actually narrowing the list, as the chips read them.
  def active
    { starts_on:, ends_on:, marked:, creator:, sort: (sort unless sort == "desc") }.compact
  end
end
