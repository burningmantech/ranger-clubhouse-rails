# frozen_string_literal: true

# Who may earn a shirt for an event year, and the order lines to buy against.
# (Laravel PotentialEarnedShirtsReport / Ember reports/potential-shirts port.)
#
# A candidate is anyone in an active status with either scheduled (sign-up) or
# rangered (timesheet) hours on a counted position that year. Earning is
# decided by rangered hours alone, against the two thresholds the caller reads
# from Settings; scheduled hours are shown so the quartermaster can see who is
# still likely to cross a line.
#
# The hour basis is the FULL calendar year of counted, closed timesheet
# entries -- matching upstream. Note the member-facing
# TicketsAndProvisionsProgress judges the same two thresholds against
# pre-event + event hours only (open entries included), so the two pages can
# disagree near a threshold; that divergence is upstream's and is kept.
#
# People who rangered an Alpha shift that year are excluded entirely, as
# upstream does. First-year shirts are handled through the Alpha pipeline
# (the Alpha Shirts page lists current Prospectives and Alphas), so someone
# who converted to active after their Alpha shift appears on neither page for
# that year -- upstream's policy, carried over deliberately.
#
# Order lines count by full swag title, never by bare size letter: different
# shirt styles share sizes, and merging them would order the wrong products.
# Each line splits into earned (owed now) and pending (candidates short of the
# threshold), and no rolled-up total is computed anywhere -- a grand total
# across styles is not a number anyone can order with.
class PotentialShirtsReport
  # Person records, not value rows: the shirt cells and the order lines both
  # read sizes through ShirtTotals, which walks the swag associations. Only
  # the columns the page reads are selected -- the roster can run to
  # thousands of people, and the rest of person is LONGTEXT ballast here.
  PERSON_COLUMNS = [:id, :callsign, :preferred_name, :first_name, :last_name,
                    :tshirt_swag_id, :tshirt_secondary_swag_id, :long_sleeve_swag_id].freeze

  Row = Data.define(:person, :estimated_hours, :actual_hours, :earned_ss, :earned_ls)

  Kind = Data.define(:name, :param, :reader, :lines)
  Line = Data.define(:title, :earned, :pending)

  # Which threshold earns each shirt kind. The backup follows the t-shirt:
  # upstream flags both short-sleeve columns off the same earned_ss bit.
  EARNED_FLAG = {
    tshirt: :earned_ss,
    tshirt_secondary: :earned_ss,
    long_sleeve: :earned_ls
  }.freeze

  # @param year [Integer]
  # @param threshold_ss [Numeric] hours to earn a t-shirt (and its backup)
  # @param threshold_ls [Numeric] hours to earn a long sleeve
  # @return [Array<Row>] callsign ascending
  def self.execute(year, threshold_ss:, threshold_ls:)
    estimated = estimated_hours(year)
    actual = actual_hours(year)
    # Upstream requires hours above zero, not merely present: a zero-length
    # timesheet entry alone does not make a candidate.
    candidate_ids = (estimated.keys | actual.keys)
                    .select { |id| estimated[id].to_f.positive? || actual[id].to_f.positive? } -
                    alpha_person_ids(year)

    Person.active
          .where(id: candidate_ids)
          .select(*PERSON_COLUMNS)
          .includes(:tshirt_swag, :tshirt_secondary_swag, :long_sleeve_swag)
          .order(:callsign)
          .map do |person|
            hours = actual[person.id] || 0.0
            Row.new(person:,
                    estimated_hours: estimated[person.id] || 0.0,
                    actual_hours: hours,
                    earned_ss: hours >= threshold_ss,
                    earned_ls: hours >= threshold_ls)
          end
  end

  # The three shirt kinds with their per-title earned/pending counts, titles
  # in size-run order with Unknown last -- ShirtTotals owns that ordering, so
  # this page and the Alpha Shirts page read their runs the same way.
  #
  # @param rows [Array<Row>]
  # @return [Array<Kind>]
  def self.order_lines(rows)
    ShirtTotals::KINDS.map do |kind|
      flag = EARNED_FLAG.fetch(kind[:param])
      lines = rows.group_by { |row| ShirtTotals.title_for(row.person, kind[:reader]) }
                  .map { |title, group|
                    earned = group.count { |row| row.public_send(flag) }
                    Line.new(title:, earned:, pending: group.size - earned)
                  }
                  .sort_by { |line| ShirtTotals.title_sort_key(line.title) }

      Kind.new(name: kind[:name], param: kind[:param], reader: kind[:reader], lines:)
    end
  end

  # Hours a person is signed up for on counted, active slots, keyed by person
  # id. Inactive (cancelled or unpublished) slots are excluded -- upstream
  # counted them, but a shift no one can ranger is not a reason to expect a
  # shirt, and every other sign-up query in the app filters them out.
  # begins_year and duration are persisted, maintained columns; parity with
  # the raw begins/ends arithmetic was verified before switching.
  def self.estimated_hours(year)
    to_hours(PersonSlot.joins(slot: :position)
                       .where(position: { count_hours: true })
                       .where(slot: { begins_year: year, active: true })
                       .group(:person_id)
                       .sum("slot.duration"))
  end

  # Hours rangered on counted positions. Entries still on duty (no off_duty)
  # are excluded, as upstream's NULL-propagating sum effectively did.
  def self.actual_hours(year)
    to_hours(Timesheet.joins(:position)
                      .where(position: { count_hours: true })
                      .with_off_duty
                      .for_year(year)
                      .group(:person_id)
                      .sum(Arel.sql("TIMESTAMPDIFF(SECOND, timesheet.on_duty, timesheet.off_duty)")))
  end

  # People who rangered an Alpha shift that year -- excluded from this report
  # entirely; see the class comment for what that means for shiny pennies.
  def self.alpha_person_ids(year)
    Timesheet.for_position(Position::ALPHA)
             .for_year(year)
             .distinct
             .pluck(:person_id)
  end

  def self.to_hours(seconds_by_person)
    seconds_by_person.transform_values { |seconds| (seconds / 3600.0).round(2) }
  end

  private_class_method :estimated_hours, :actual_hours, :alpha_person_ids, :to_hours
end
