# frozen_string_literal: true

# The online-course progress report (Laravel Lib/Reports/OnlineCourseReport):
# everyone enrolled in the year's Moodle course for a training position, with
# enrollment and completion timestamps. A NULL enrolled_at is a "direct
# enrollment" -- created in Moodle rather than via the Clubhouse, so the date
# is unknown; a NULL completed_at means still in progress.
#
# Deliberate delta from upstream: the query takes the position from the URL's
# training rather than hardcoding In-Person the way the Ember client did.
# Identical for the only position that has ever had course data, and an ART
# URL reports its own (empty) course instead of borrowing Dirt's.
class Training::OnlineCourseProgressReport
  # How a row can sit in the pipeline, keyed by the page's progress-filter
  # param values (Training::OnlineCourseProgressHelper::PROGRESS_FILTERS
  # labels them). "completed"/"in-progress" partition the list; "direct"
  # overlaps both sides.
  PROGRESS_TESTS = {
    "completed" => ->(poc) { poc.completed_at.present? },
    "in-progress" => ->(poc) { poc.completed_at.nil? },
    "direct" => ->(poc) { poc.enrolled_at.nil? }
  }.freeze

  attr_reader :enrollments

  # @param training [Position] the training position
  # @param year [Integer]
  # @return [Training::OnlineCourseProgressReport]
  def self.execute(training, year)
    new(PersonOnlineCourse.where(year:, position_id: training.id)
                          .includes(:person).joins(:person)
                          .order("person.callsign").to_a)
  end

  # @param enrollments [Array<PersonOnlineCourse>] with person loaded
  def initialize(enrollments)
    @enrollments = enrollments
  end

  # Does the row match the progress-filter key? Unknown keys (including the
  # filter bar's "all") match everything.
  # @return [Boolean]
  def matches_progress?(poc, key)
    test = PROGRESS_TESTS[key]
    test.nil? || test.call(poc)
  end

  # Memoized so the CSV path, which renders no summary, never pays for them.
  # @return [Hash{String => Integer}] people per PROGRESS_TESTS key
  def progress_counts
    @progress_counts ||= PROGRESS_TESTS.transform_values { |test| enrollments.count(&test) }
  end

  # @return [Integer]
  def completed_count = progress_counts["completed"]

  # @return [Hash{String => Integer}] people per Person status
  def status_counts
    @status_counts ||= enrollments.map { |poc| poc.person.status }.tally
  end
end
