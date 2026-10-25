# frozen_string_literal: true

# One event year of meal and shower pogs, counted for the Pog Dashboard.
#
# A pog belongs to the year and the day it was handed over (issued_at, through
# PersonPog.issued_in). A day is the calendar date of the stored clock, so a
# pog issued at 00:05 counts for the new day, as its timestamp reads.
#
# A cancelled pog was recorded by mistake and never handed over, so it is left
# out of every count but its own: the type totals, the days, both top lists and
# the linked share all read the pogs actually issued. A redeemed pog was issued
# first, so it counts as issued too.
#
# Every section reads the same rows: those whose type and status PersonPog
# knows. Clubhouse 2 stored both unchecked, and a row only some sections
# counted would make a day's cells disagree with its total.
class PogStatsReport
  TOP_LIMIT = 10

  # One pog type. issued includes the redeemed ones; cancelled stands apart.
  TypeCount = Data.define(:pog, :issued, :redeemed, :cancelled) do
    def label = PersonPog::POG_LABELS.fetch(pog)
  end

  # One day of the year, with the pogs issued on it by type.
  Day = Data.define(:date, :counts) do
    def total = counts.values.sum
    def count_for(pog) = counts.fetch(pog, 0)
  end

  # One row of a top list. person is nil when the person no longer exists.
  Tally = Data.define(:person_id, :person, :total)

  # busiest_day: the earliest of the days tied for the most pogs; nil when none
  # were issued.
  Result = Data.define(:types, :days, :busiest_day, :issuers, :recipients, :issuer_count,
                       :recipient_count, :linked) do
    def empty? = types.empty?
    def issued = types.sum(&:issued)
    def redeemed = types.sum(&:redeemed)
    def cancelled = types.sum(&:cancelled)

    # The types issued at least once: the by-day table's columns.
    def issued_types = types.select { |type| type.issued.positive? }

    def type_share(type) = percent(type.issued, issued)
    def day_share(day) = percent(day.total, busiest_day.total)
    def linked_percent = percent(linked, issued)

    private

    # Rounded, but never to 0% while there is something, nor to 100% while
    # something is missing: a bar or a tile must not read none or all when it
    # is neither.
    def percent(part, whole)
      return 0 if part.zero? || whole.zero?

      (part * 100.0 / whole).round.clamp(1, part < whole ? 99 : 100)
    end
  end

  def self.execute(year:) = new(year).execute

  def initialize(year)
    @all = PersonPog.issued_in(year).where(pog: PersonPog::POGS, status: PersonPog::STATUSES)
    @issued = @all.where.not(status: PersonPog::STATUS_CANCELLED)
  end

  def execute
    issuer_counts = @issued.group(:issued_by_id).count
    recipient_counts = @issued.group(:person_id).count

    days = self.days

    Result.new(types:, days:, busiest_day: days.max_by(&:total),
               issuers: top(issuer_counts), recipients: top(recipient_counts),
               issuer_count: issuer_counts.size, recipient_count: recipient_counts.size,
               linked: @issued.where.not(timesheet_id: nil).count)
  end

  private

  # In PersonPog::POGS order, and only the types the year holds at all.
  def types
    counts = @all.group(:pog, :status).count.each_with_object(Hash.new(0)) do |((pog, status), count), sums|
      sums[[canonical(pog), canonical(status)]] += count
    end

    PersonPog::POGS.filter_map do |pog|
      issued = counts[[pog, PersonPog::STATUS_ISSUED]]
      redeemed = counts[[pog, PersonPog::STATUS_REDEEMED]]
      cancelled = counts[[pog, PersonPog::STATUS_CANCELLED]]
      next if (issued + redeemed + cancelled).zero?

      TypeCount.new(pog:, issued: issued + redeemed, redeemed:, cancelled:)
    end
  end

  def days
    @issued.group("DATE(person_pog.issued_at)", :pog).count
           .group_by { |(date, _pog), _count| date }
           .sort_by(&:first)
           .map do |date, entries|
             counts = entries.each_with_object(Hash.new(0)) { |((_date, pog), count), sums| sums[canonical(pog)] += count }
             Day.new(date:, counts:)
           end
  end

  # A grouped value as the constants spell it. The columns' collation matched
  # "Meal" and "issued " to them, and a group comes back spelled as one of its
  # rows was, which would miss every lookup by the constant.
  def canonical(value) = value.to_s.strip.downcase

  # The cut is made by id among ties, so the same ten come back on every read;
  # the ten are then shown by callsign within a tie, a deleted person last, as
  # CorrectionStatsReport orders them.
  def top(counts)
    ranked = counts.sort_by { |id, total| [-total, id] }.first(TOP_LIMIT)
    people = Person.basic_info.where(id: ranked.map(&:first)).index_by(&:id)

    ranked.map { |id, total| Tally.new(person_id: id, person: people[id], total:) }
          .sort_by { |row| [-row.total, row.person ? [0, row.person.callsign.downcase] : [1, row.person_id]] }
  end
end
