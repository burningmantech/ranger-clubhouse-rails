# frozen_string_literal: true

# What the message log is being narrowed to: a person, a direction, a set of
# outcomes, and which page of the results.
class RbsMessageLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a database
  # offset, and an unbounded one overflows that limit rather than simply coming
  # back empty.
  MAX_PAGE = 100_000

  DIRECTIONS = %w[inbound outbound].freeze

  attribute :callsign, :string
  attribute :direction, :string
  attribute :page, :integer, default: 1

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
    self.direction = nil unless DIRECTIONS.include?(direction)
  end

  # Held as its own reader rather than a typed attribute: a checkbox group
  # sends nothing when every box is cleared.
  def status
    Array(@status).compact_blank & Broadcast::MESSAGE_STATUSES
  end

  def status=(values)
    @status = Array(values)
  end

  # Only the filters actually narrowing the list, so page links and chips carry
  # the search forward without collecting empty values.
  def query_params(to_page: nil)
    values = { callsign: callsign.presence, direction: direction.presence, status: status.presence }.compact
    values[:page] = to_page if to_page.present? && to_page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end

  # The filters as chips read them: one entry per filter that is narrowing.
  def active
    { callsign: callsign.presence, direction: direction.presence,
      status: status.presence&.join(", ") }.compact
  end

  def any?
    active.any?
  end
end
