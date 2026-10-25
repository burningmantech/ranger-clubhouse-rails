# frozen_string_literal: true

class RequestLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a SQL OFFSET,
  # and an unbounded one overflows the database's limit rather than simply
  # coming back empty.
  MAX_PAGE = 100_000

  attribute :person_callsign, :string
  attribute :status_class, :string
  attribute :http_method, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :ip, :string
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
  end

  def persisted?
    false
  end

  def parsed_start_time
    parse_time(start_time)
  end

  def parsed_end_time
    parse_time(end_time)
  end

  # Only values the query understands. A hand-typed status or verb narrows
  # nothing, so it is dropped rather than drawn as a chip promising a filter
  # the results do not have.
  def selected_status_class
    status_class if RequestLog::STATUS_CLASSES.key?(status_class)
  end

  def selected_http_method
    http_method if RequestLog::HTTP_METHODS.include?(http_method)
  end

  # Only the filters actually being applied, so chips and pager links carry
  # the search forward without collecting empty values.
  def query_params(page: nil)
    values = {
      person_callsign: person_callsign.presence,
      status_class: selected_status_class,
      http_method: selected_http_method,
      start_time: (start_time.presence if parsed_start_time),
      end_time: (end_time.presence if parsed_end_time),
      ip: ip.presence
    }.compact
    values[:page] = page if page.present? && page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end

  private

  # A whole date is required. Time.zone.parse fills in whatever the text
  # leaves out -- "26" becomes the 26th of this month, "August" the 1st -- so
  # a partial entry would silently filter by a date no one asked for.
  def parse_time(value)
    return nil if value.blank?
    return nil unless Date._parse(value).values_at(:year, :mon, :mday).all?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end
end
