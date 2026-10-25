# frozen_string_literal: true

# One year of timesheet correction activity, counted rather than listed (Ember
# reports/timesheet-correction-stats port).
#
# Two kinds of request are decided by Timesheet Management: a *correction* to an
# entry that exists, and a *missing-entry* request for one that was never turned
# in. This report answers how each kind was decided, which positions and rangers
# generate them, and how the review load split across reviewers. Its sibling
# CorrectionRequestsReport lists the ones still waiting; this one counts the ones
# already settled.
#
# Ported from app/Lib/Reports/TimesheetCorrectionsStatisticsReport.php. The two
# sides are counted from different tables and, deliberately, on different clocks
# -- see YEAR SEMANTICS below.
#
# == YEAR SEMANTICS (upstream's, kept)
#
# Corrections and deletions are scoped by the *log's* `created_at` year: they
# measure review work done during a calendar year. Missing-entry requests and the
# entry total are scoped by the *shift's* `on_duty` year: they measure an event.
# So a January 2025 review of a 2024 entry is 2025 correction work, while a 2024
# missing-entry request filed in January 2025 stays 2024. Both are defensible on
# their own and upstream never reconciled them; changing either would silently
# restate every historical number, so neither is changed here.
#
# TimesheetLog also carries a `year` column, but it holds the *event* year, not
# the year the log was written. It is not what upstream counts and is not used.
class CorrectionStatsReport
  # Upstream's limit on each "top" list.
  TOP_LIMIT = 20

  # A review only counts once it lands on a decision. An entry moved to pending,
  # verified, or unverified has not been approved or rejected by anybody.
  COUNTED_STATUSES = [Timesheet::STATUS_APPROVED, Timesheet::STATUS_REJECTED].freeze

  MISSING_STATUSES = [TimesheetMissing::STATUS_APPROVED,
                      TimesheetMissing::STATUS_REJECTED].freeze

  # One decided review, flattened out of a timesheet_log row. person_id is the
  # ranger whose entry it is; reviewer_id is whoever decided it.
  Review = Data.define(:position_id, :person_id, :reviewer_id, :status)

  # One row of a "top positions" list. A deleted position leaves the title nil --
  # the Laravel-shared schema carries no foreign keys, so the id can outlive it.
  PositionTally = Data.define(:position_id, :title, :total) do
    def label = title || "Deleted position ##{position_id}"
  end

  # One row of a "top submitters" list. person is nil for a deleted ranger; the
  # view renders it through person_display_link, which spells that case itself.
  PersonTally = Data.define(:person_id, :person, :total)

  # One reviewer's workload across both kinds of request.
  Reviewer = Data.define(:person_id, :person, :corrections_approved,
                         :corrections_rejected, :missing_approved, :missing_rejected) do
    def corrections_total = corrections_approved + corrections_rejected

    def missing_total = missing_approved + missing_rejected

    def grand_total = corrections_total + missing_total
  end

  # One kind of request, counted. `total` is only ever larger than approved +
  # rejected on the missing side, where a request can sit assigned to a reviewer
  # without a decision yet.
  RequestStats = Data.define(:approved, :rejected, :total, :top_positions, :top_people) do
    def decided = approved + rejected

    def undecided = total - decided

    # Each outcome's share, for the card's proportion bar. Measured against
    # `total` rather than `decided` so the bar divides the same population the
    # chips beneath it enumerate: on the missing side a request can reach a
    # reviewer and still be waiting, and a bar normalised over decisions alone
    # would read 100% approved next to a chip saying half are still open.
    #
    # Guarded rather than left to the caller: 0/0 is NaN, and NaN.round(1)
    # returns NaN instead of raising, so an unguarded reader gets
    # "width: NaN%" -- a silently blank bar with nothing in the log.
    def approved_percent = percent_of_total(approved)

    def rejected_percent = percent_of_total(rejected)

    def undecided_percent = percent_of_total(undecided)

    private

    def percent_of_total(count)
      return 0.0 if total.zero?

      (count * 100.0 / total).round(1)
    end
  end

  Report = Data.define(:year, :timesheet_total, :entries_deleted, :corrections,
                       :missing, :reviewers) do
    # Nothing was decided and nothing was asked for. The year's timesheet total
    # is deliberately not part of this: a year can hold thousands of entries and
    # still have no correction activity, which is the good outcome this reports.
    def empty? = corrections.total.zero? && missing.total.zero? && entries_deleted.zero?
  end

  class << self
    def execute(year:)
      reviews = decided_reviews(year)
      missing = missing_scope(year)
      missing_counts = missing.where(review_status: MISSING_STATUSES)
                              .group(:reviewer_person_id, :review_status).count

      # Cut to twenty before anything is looked up, so the page loads the twenty
      # rangers it names rather than every ranger who filed a request this year.
      #
      # Each request is counted once. Upstream seeds every counter at 1 and then
      # adds 1 for that same first row, so all four of its lists read one high
      # per row; that off-by-one is fixed here rather than reproduced, and is
      # the one place this port's numbers differ from Clubhouse 2's on purpose.
      #
      # The two missing lists carry no status filter, as upstream: they ask
      # where requests come from, not how they ended.
      correction_positions = top(reviews.map(&:position_id).tally)
      correction_people = top(reviews.map(&:person_id).tally)
      missing_positions = top(missing.group(:position_id).count)
      missing_people = top(missing.group(:person_id).count)

      positions = load_positions(correction_positions + missing_positions)
      people = load_people(correction_people + missing_people, reviews, missing_counts)

      Report.new(
        year:,
        timesheet_total: Timesheet.all.where_year("on_duty", year).count,
        entries_deleted: deleted_entry_count(year),
        corrections: correction_stats(reviews,
                                      position_tallies(correction_positions, positions),
                                      person_tallies(correction_people, people)),
        missing: missing_stats(missing,
                               position_tallies(missing_positions, positions),
                               person_tallies(missing_people, people)),
        reviewers: build_reviewers(reviews, missing_counts, people)
      )
    end

    private

    # Every review that reached a decision this calendar year.
    #
    # The join is an inner one, as upstream: a review of an entry that has since
    # been deleted is not counted anywhere except the deletion tally below. The
    # LIKE narrows the year's ~20,000 log rows to the ~1,500 that record a
    # review before any of them are deserialized; `data` is a JSON text column,
    # so there is no index to use and no cheaper filter to apply.
    def decided_reviews(year)
      TimesheetLog.joins(:timesheet)
                  .where_year("timesheet_log.created_at", year)
                  .where_like("timesheet_log.data", "%review_status%")
                  .pluck("timesheet_log.data", "timesheet.position_id",
                         "timesheet_log.person_id", "timesheet_log.create_person_id")
                  .filter_map { |row| build_review(*row) }
    end

    def build_review(data, position_id, person_id, reviewer_id)
      # A ranger correcting their own entry is not review work. Written as a
      # Ruby comparison rather than a SQL one on purpose: `person_id !=
      # create_person_id` in SQL also drops the rows where create_person_id is
      # NULL, and upstream counts those (it just cannot name the reviewer -- see
      # build_reviewers).
      return if person_id == reviewer_id

      transition = data.is_a?(Hash) ? data["review_status"] : nil
      # [old, new]. Only the new status decides whether this counts; upstream
      # selects the old one and never reads it.
      return unless transition.is_a?(Array)

      status = transition[1]
      return unless COUNTED_STATUSES.include?(status)

      Review.new(position_id:, person_id:, reviewer_id:, status:)
    end

    # Entries whose logs survive but whose timesheet row is gone.
    #
    # Which year an entry lands in depends on which app deleted it, and neither
    # is the year the reader might assume:
    #
    # - Deleted through Rails, `Timesheet` cascades (`has_many :timesheet_logs,
    #   dependent: :destroy`) and then `after_destroy :log_deletion` writes one
    #   fresh log stamped now. Only that log survives, so the entry counts
    #   against the year it was **deleted**. Its earlier reviews are gone from
    #   `decided_reviews` too, which is why a settled year's correction counts
    #   can shrink after a later deletion.
    # - Deleted by Laravel, which has no cascade and no foreign keys, every log
    #   survives, so the entry counts in **each** calendar year it was logged in
    #   and the yearly figures cannot be summed.
    #
    # Upstream's query, kept unchanged: nothing records when a row was removed,
    # so no year attribution is available that would be right for both paths.
    def deleted_entry_count(year)
      TimesheetLog.left_joins(:timesheet)
                  .where_year("timesheet_log.created_at", year)
                  .with_timesheet
                  .where(timesheet: { id: nil })
                  .distinct
                  .count("timesheet_log.timesheet_id")
    end

    # Missing-entry requests somebody other than the ranger has looked at.
    #
    # The comparison is NULL-unsafe, and upstream's is too: a request no one has
    # picked up yet has no reviewer, so it fails the test and drops out of every
    # number on this side -- roughly a third of a recent year's requests. That is
    # why nothing here is labelled a plain "total"; the page says these are the
    # requests that reached a reviewer, and points at the sibling page for the
    # ones still waiting.
    def missing_scope(year)
      requests = TimesheetMissing.arel_table

      TimesheetMissing.all
                      .where_year("on_duty", year)
                      .where(requests[:reviewer_person_id].not_eq(requests[:person_id]))
    end

    def correction_stats(reviews, top_positions, top_people)
      by_status = reviews.map(&:status).tally
      approved = by_status[Timesheet::STATUS_APPROVED].to_i
      rejected = by_status[Timesheet::STATUS_REJECTED].to_i

      RequestStats.new(
        approved:,
        rejected:,
        # Every counted review is one or the other, so the two are the whole of
        # it -- unlike the missing side, where a request can reach a reviewer and
        # still be waiting.
        total: approved + rejected,
        top_positions:,
        top_people:
      )
    end

    def missing_stats(missing, top_positions, top_people)
      by_status = missing.group(:review_status).count

      RequestStats.new(
        approved: by_status[TimesheetMissing::STATUS_APPROVED].to_i,
        rejected: by_status[TimesheetMissing::STATUS_REJECTED].to_i,
        # Every status, so the pending-but-assigned requests are in the total the
        # way upstream's separate count query had them.
        total: by_status.values.sum,
        top_positions:,
        top_people:
      )
    end

    # The twenty biggest, cut deterministically. Ties are broken by id here so
    # the cut does not need names it has not loaded yet; the displayed order is
    # settled by name once they are. Upstream leaves both to MySQL, so its tail
    # rows can swap places between two reads of the same year.
    def top(counts) = counts.sort_by { |id, total| [-total, id.to_i] }.first(TOP_LIMIT)

    def position_tallies(counts, positions)
      counts.map { |id, total| PositionTally.new(position_id: id, title: positions[id], total:) }
            .sort_by { |row| [-row.total, row.label.downcase] }
    end

    def person_tallies(counts, people)
      counts.map { |id, total| PersonTally.new(person_id: id, person: people[id], total:) }
            .sort_by { |row| [-row.total, sort_name(row.person, row.person_id)] }
    end

    # One row per person who decided anything, either kind. A reviewer whose
    # person row is gone keeps their row here -- their decisions are already
    # counted in the totals above, and dropping the row (as upstream does) loses
    # work the page has just claimed happened.
    def build_reviewers(reviews, missing_counts, people)
      corrections = reviews.map { |review| [review.reviewer_id, review.status] }.tally

      # A nil reviewer id reaches here from the corrections side only: some old
      # logs record a decision with no author, and build_review keeps them so
      # the decision is still counted. (The missing side cannot produce one --
      # missing_scope's NULL-unsafe comparison dropped those rows already.)
      # There is no person to attribute such a decision to, so it gets no row.
      ids = (corrections.keys + missing_counts.keys).filter_map(&:first).uniq

      ids.map { |id| build_reviewer(id, corrections, missing_counts, people[id]) }
         .sort_by { |row| [sort_name(row.person, row.person_id), row.person_id] }
    end

    def build_reviewer(id, corrections, missing_counts, person)
      Reviewer.new(
        person_id: id,
        person:,
        corrections_approved: corrections[[id, Timesheet::STATUS_APPROVED]].to_i,
        corrections_rejected: corrections[[id, Timesheet::STATUS_REJECTED]].to_i,
        missing_approved: missing_counts[[id, TimesheetMissing::STATUS_APPROVED]].to_i,
        missing_rejected: missing_counts[[id, TimesheetMissing::STATUS_REJECTED]].to_i
      )
    end

    # Deleted people sort to the end rather than to the top, where an empty
    # callsign would otherwise put them. The leading 0/1 already separates the
    # two branches, so the id stays an Integer and orders 99 before 100 -- the
    # same way `top` breaks its own ties.
    def sort_name(person, person_id)
      person ? [0, person.callsign.downcase] : [1, person_id]
    end

    # Every person the page can name, in one query: both sets of top submitters
    # and every reviewer on either side.
    #
    # select: the page reads a callsign and nothing else, and `person` is the
    # widest table in the schema -- seven of its columns are LONGTEXT/MEDIUMTEXT
    # JSON blobs. The sibling reports all narrow this the same way.
    def load_people(top_rows, reviews, missing_counts)
      ids = top_rows.map(&:first) +
            reviews.map(&:reviewer_id) +
            missing_counts.keys.map(&:first)

      Person.where(id: ids.compact.uniq).select(:id, :callsign).index_by(&:id)
    end

    # Titles for both sets of top positions, in one query.
    def load_positions(top_rows)
      Position.where(id: top_rows.map(&:first).compact.uniq).pluck(:id, :title).to_h
    end
  end
end
