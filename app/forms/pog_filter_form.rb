# frozen_string_literal: true

# The filters across the top of Pog Administration: who received the pog, who
# issued it, the day, the type and the status.
class PogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # The Status filter's values. Not the stored statuses: "issued" means handed
  # over, a redeemed pog included -- what the Pog Dashboard counts as issued, so
  # a top-ten name there opens exactly the pogs it counts.
  STATUS_ISSUED = PersonPog::STATUS_ISSUED
  STATUS_CANCELLED = PersonPog::STATUS_CANCELLED

  attribute :person_callsign, :string
  attribute :issued_by_id, :string
  attribute :day, :string # ISO 8601, as the Day select's values are
  attribute :pog, :string
  attribute :status, :string
  attribute :page, :integer

  # The Status filter values that cover these stored statuses, in select order.
  def self.status_filters(statuses)
    filters = []
    filters << STATUS_ISSUED if statuses.any? { |status| status != STATUS_CANCELLED }
    filters << STATUS_CANCELLED if statuses.include?(STATUS_CANCELLED)
    filters
  end

  # issuer_ids, days, pogs, statuses: the issuers, dates, types and Status
  # filter values the viewed year holds, which are all the selects offer.
  # Anything else -- a stale bookmark, or a value carried over from another
  # year -- filters nothing, so it must not draw a chip claiming it did.
  def initialize(attributes = {}, issuer_ids:, days:, pogs:, statuses:)
    super(attributes)
    self.person_callsign = person_callsign.to_s.strip.presence
    self.issued_by_id = known_filter(issued_by_id, issuer_ids.map(&:to_s))
    self.day = known_filter(day, days.map(&:iso8601))
    self.pog = known_filter(pog, pogs)
    self.status = known_filter(status, statuses)
    self.page = 1 unless page.to_i.positive?
  end

  def apply(scope)
    scope = scope.where(person_id: recipient_ids) if person_callsign
    scope = scope.where(issued_by_id:) if active.key?(:issued_by_id)
    scope = scope.where(issued_at: day_range) if active.key?(:day)
    scope = scope.where(pog:) if active.key?(:pog)

    case active[:status]
    when STATUS_CANCELLED then scope.where(status: STATUS_CANCELLED)
    when STATUS_ISSUED then scope.where.not(status: STATUS_CANCELLED)
    else scope
    end
  end

  # The filters actually narrowing the list, as the chips read them. The
  # callsign is free text, so any value is a filter, "all" included: it is not a
  # select that could have sent the sentinel active_filters drops.
  def active
    { person_callsign: }.compact.merge(
      UiComponents::FilterBarHelper.active_filters({ issued_by_id:, day:, pog:, status: })
    )
  end

  # The filters, and a page past the first, as URL params.
  def query_params(page: nil)
    values = active
    values = values.merge(page:) if page.to_i > 1
    values.empty? ? {} : { PARAM_SCOPE => values }
  end

  # The filters as the hidden fields that carry them through the year selector.
  def year_selector_keep = active.transform_keys { |key| "#{PARAM_SCOPE}[#{key}]" }

  private

  def known_filter(value, allowed) = UiComponents::FilterBarHelper.known_filter(value, allowed)

  # The person whose callsign this is; failing that, everyone whose callsign
  # matches it once spaces and punctuation are dropped, so "firefly" finds
  # "Fire-Fly". Never one of several picked at random, as
  # Person.find_id_by_callsign would for "Fire-Fly" and "Fire Fly". A callsign
  # no one holds keeps no pogs, rather than dropping the filter and listing
  # everyone's.
  def recipient_ids
    exact = Person.where(callsign: person_callsign).ids
    return exact if exact.any?

    normalized = WordUtils.normalize_word(person_callsign)
    normalized.empty? ? [] : Person.where(callsign_normalized: normalized).ids
  end

  # A whole day on the machine's local clock, which is how the database stores
  # times (see where_year), and the day the dashboard's DATE(issued_at) reads.
  def day_range
    date = Date.iso8601(day)
    date.to_time...(date + 1).to_time
  end
end
