# frozen_string_literal: true

# Every account banner in the Clubhouse, gathered on one page. Banners are
# written and removed on each person's own Banners page; this page is where they
# are read together, so a note left over from an old event gets noticed.
class Communication::PersonBannersController < ApplicationController
  layout "communication"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or VC role required to review account banners."

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  TYPE_FILTERS = %w[permanent event].freeze

  def index
    @filter_params = filter_params

    banners = PersonBanner.find_for_query(include_person: true)

    @total_count = banners.size
    @permanent_count = banners.count(&:is_permanent?)
    @event_count = @total_count - @permanent_count
    @people_count = banners.map(&:person_id).uniq.size
    @years = posted_years(banners)

    @banners = filtered(banners)
    @permanent_banners = @banners.select(&:is_permanent?)
    @event_banners = @banners.reject(&:is_permanent?)
  end

  private

  # known_filter drops anything the page does not actually apply, so a stale
  # bookmark cannot draw a chip claiming a filter that narrows nothing. It also
  # rejects a param that arrives as a list or a nested hash rather than a value.
  #
  # The year is checked for shape rather than against the years currently on
  # file. Deleting the last banner of some year must not quietly turn a link to
  # that year into a link to every year -- better to keep the filter and say
  # nothing matched.
  def filter_params
    { type: UiComponents::FilterBarHelper.known_filter(params[:type], TYPE_FILTERS),
      year: year_filter,
      callsign: callsign_filter }
  end

  def year_filter
    year = params[:year]
    year.is_a?(String) && year.match?(/\A\d{4}\z/) ? year : ALL_FILTER
  end

  def callsign_filter
    params[:callsign].is_a?(String) ? params[:callsign].strip : ""
  end

  # The years to offer in the filter, taken from the whole list rather than the
  # filtered one so that choosing a year never removes the other years from the
  # menu.
  def posted_years(banners)
    banners.filter_map { |banner| banner.created_at&.year }.uniq.sort.reverse
  end

  # find_for_query hands back a sorted Array, not a relation, so the filters are
  # applied in Ruby. It does accept `year:` and `is_permanent:`, but its year
  # lands rows in buckets the machine clock decides, while the dates on this
  # page are shown in the Clubhouse's own timezone -- filtering here keeps the
  # year a reader picks and the year a card prints as the same year.
  def filtered(banners)
    case @filter_params[:type]
    when "permanent" then banners = banners.select(&:is_permanent?)
    when "event" then banners = banners.reject(&:is_permanent?)
    end

    year = @filter_params[:year]
    banners = banners.select { |banner| banner.created_at&.year.to_s == year } unless year == ALL_FILTER

    callsign = @filter_params[:callsign]
    return banners if callsign.blank?

    needle = callsign.downcase
    banners.select { |banner| banner.person&.callsign.to_s.downcase.include?(needle) }
  end
end
