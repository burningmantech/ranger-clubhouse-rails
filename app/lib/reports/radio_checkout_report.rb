# frozen_string_literal: true

# Radios held too long (Ember reports/radio-checkout port). A chase list: every
# handheld radio checked out for more than fourteen hours in the year, who has
# it, and whether they are allowed to keep it.
#
# Eligibility is the whole point of the report. A Ranger holding an event-radio
# provision may keep a radio for the entire event, so a forty-hour checkout is
# routine for them and a problem for everyone else. Each row carries that
# verdict so the page can split on it.
#
# Upstream's own filter for this is inverted: `if (!$includeQualified &&
# !$eligible) continue;` drops the NON-eligible rows unless the "Include Event
# Radio Eligible" checkbox is ticked, so its default shows only the people who
# are fine and hides everyone who has to be chased -- the opposite of both its
# label and its docblock. Nothing here filters on eligibility; the caller
# receives both cohorts and shows both.
class RadioCheckoutReport
  # Upstream accepts an hour_limit parameter that no client ever sends, so
  # fourteen hours is the only limit the report has ever run with.
  HOUR_LIMIT = 14
  SECONDS_LIMIT = HOUR_LIMIT * 3600

  # checkout carries the people and the asset through its own associations,
  # already eager-loaded. eligible is the provision verdict for THIS year --
  # a person eligible in 2024 need not be in 2025.
  Row = Data.define(:checkout, :eligible) do
    def asset = checkout.asset
    def person = checkout.person
    def duration = checkout.duration
  end

  # @param year [Integer, nil] the event year to report on
  # @param event_summary [Boolean] the after-action view: everything still out,
  #   plus everything already returned that was held past the limit
  # @return [Array<Row>] longest-held first
  def self.execute(year:, event_summary: false)
    new(year:, event_summary:).execute
  end

  def initialize(year:, event_summary: false)
    @year = year
    @event_summary = event_summary
  end

  def execute
    return [] if @year.blank?

    checkouts = reportable_checkouts
    eligible_ids = eligible_person_ids(checkouts.map(&:person_id).uniq)

    checkouts.map { |checkout| Row.new(checkout:, eligible: eligible_ids.include?(checkout.person_id)) }
             .sort_by { |row| [-row.duration, row.person&.callsign.to_s] }
  end

  private

  # Upstream measures the span in SQL against an interpolated now();
  # PersonAsset#duration is the same arithmetic and is already the app's single
  # answer to "how long has this been gone", so the limit is applied in Ruby
  # over the year's radio checkouts. A year holds a couple of thousand of them.
  # preload, not includes: `where(asset: ...)` puts asset in references_values,
  # which would flip includes to eager_load -- one query LEFT OUTER JOINing
  # person three times and selecting all 79 of its columns per join, credentials
  # and PII included, for every checkout of the year. The explicit joins(:asset)
  # is what keeps the where valid without it.
  def reportable_checkouts
    scope = PersonAsset.preload(:person, :asset, :check_out_person, :check_in_person)
                       .joins(:asset)
                       .where(asset: { type: Asset::TYPE_RADIO })
                       .where_year("checked_out", @year)
    # Only the event summary looks at radios that came back, so everything else
    # can be left in the database.
    scope = scope.where(checked_in: nil) unless @event_summary

    scope.select { |checkout| reportable?(checkout) }
  end

  def reportable?(checkout)
    # Still out. The chase list wants it once it is past the limit; the event
    # summary is an after-action audit, so there it counts however briefly it
    # has been gone -- a radio no one has handed back is unaccounted for
    # whatever the clock says.
    return @event_summary || checkout.duration > SECONDS_LIMIT if checkout.checked_in.nil?

    # Returned. PersonAsset#duration is .abs-wrapped, so a row whose timestamps
    # run backwards -- clock skew on an HQ laptop, a correction entered the
    # wrong way round -- would report its gap as a long hold and sort to the top
    # of the list. Upstream's signed SQL subtraction drops it; so does this.
    return false if checkout.checked_in < checkout.checked_out

    checkout.duration > SECONDS_LIMIT
  end

  # An event-radio provision the person could have drawn on for THIS year:
  # one they actually consumed that year, or -- while the year is still running
  # -- one they are holding and could still consume. A past year sees only what
  # was consumed, because a provision still sitting available today says
  # nothing about a radio someone kept two years ago.
  #
  # KNOWN DIVERGENCE, inherited from upstream and left alone on purpose. This is
  # a second answer to "may this Ranger keep an event radio"; HQ site
  # registration asks Provision.retrieve_usable_for_person_ids + build_package
  # (PersonEventInfo#radio_max) instead, and the two disagree at the edges. A
  # provision marked used with consumed_year == the current year drops out of
  # radio_max -- HQ tells the holder to hand the radio back -- while it counts
  # as eligible here; and CAN_USE_STATUSES omits BANKED, which build_package can
  # still allocate from. Upstream spells exactly these three statuses, so
  # reconciling the two is a policy change for the quartermaster to call, not a
  # porting fix. Change both together or not at all.
  def eligible_person_ids(person_ids)
    return Set.new if person_ids.empty?

    provisions = Provision.where(person_id: person_ids, type: Provision::EVENT_RADIO)
    consumed = provisions.where(status: Provision::USED, consumed_year: @year)
    # CAN_USE_STATUSES is available/claimed/submitted -- exactly the list
    # upstream spells out inline for the current year.
    scope = if @year == Current.year
              consumed.or(provisions.where(status: Provision::CAN_USE_STATUSES))
            else
              consumed
            end

    scope.distinct.pluck(:person_id).to_set
  end
end
