# frozen_string_literal: true

class ErrorLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a SQL OFFSET,
  # and an unbounded one overflows the database's limit rather than simply
  # coming back empty.
  MAX_PAGE = 100_000

  attribute :person_callsign, :string
  attribute :error_type, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :last_day, :boolean, default: false
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
  end

  def persisted?
    false
  end

  def parsed_start_time
    UiComponents::FilterBarHelper.filter_time(start_time)
  end

  def parsed_end_time
    UiComponents::FilterBarHelper.filter_time(end_time)
  end

  # Only the filters actually being applied. A date that could not be read
  # narrows nothing, so it is left out rather than drawn as a chip claiming
  # a time bound the results do not have.
  def query_params(page: nil)
    values = {
      person_callsign: person_callsign.presence,
      error_type: error_type.presence,
      start_time: (start_time.presence if parsed_start_time),
      end_time: (end_time.presence if parsed_end_time),
      last_day: last_day.presence
    }.compact
    values[:page] = page if page.present? && page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end
end
