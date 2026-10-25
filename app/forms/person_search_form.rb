# frozen_string_literal: true

# The criteria on the People Search page: current or as-of-a-year status,
# years rangered, photo status, and this year's online course / in-person
# training / ticketing progress. Every field is optional and the criteria
# combine with AND -- an empty form matches everyone, which is why the
# controller runs a warn-then-confirm step before it search on one.
class PersonSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  STATUS_OPTIONS = Person::ALL_STATUSES

  YEARS_OP_OPTIONS = [
    ["Exactly", "eq"],
    ["At Least", "gte"],
    ["At Most", "lte"]
  ].freeze

  PHOTO_STATUS_OPTIONS = [
    ["Any", ""],
    ["approved", "approved"],
    ["missing", "missing"],
    ["rejected", "rejected"]
  ].freeze

  ONLINE_COURSE_OPTIONS = [
    ["Any", ""],
    ["Missing Course", "missing"],
    ["Started Course", "started"],
    ["Completed Course", "completed"]
  ].freeze

  TRAINING_STATUS_OPTIONS = [
    ["Any", ""],
    ["No Sign-Up", "missing"],
    ["Signed-Up", "signed-up"],
    ["Passed", "passed"],
    ["Not Passed/No Show", "failed"]
  ].freeze

  TICKETING_OPTIONS = [
    ["Any", ""],
    ["Started", "started"],
    ["Not Started", "not-started"],
    ["Finished", "finished"],
    ["Not Finished", "not-finished"],
    ["Not Finished w/Claimed", "not-finished-claimed"]
  ].freeze

  # The six extra-column checkboxes. Each key is also what a show_*? method
  # below checks columns for directly.
  COLUMN_OPTIONS = [
    ["years_worked", "Years Rangered"],
    ["photo_status", "Photo Status"],
    ["online_course", "Online Course"],
    ["training_status", "In-Person Training Status"],
    ["ticketing_info", "Ticketing Info"],
    ["created_at", "Account Creation Date"]
  ].freeze

  EARLIEST_STATUS_YEAR = 1996
  EARLIEST_CREATED_YEAR = 2011
  # The year_created sentinel: accounts from before the Clubhouse recorded a
  # creation date at all.
  CREATED_PRIOR_SENTINEL = 1
  CREATED_PRIOR_LABEL = "Prior to 2010"

  attribute :status_year, :integer, default: 0
  attribute :years_worked, :string
  attribute :years_worked_op, :string, default: "eq"
  attribute :photo_status, :string, default: ""
  attribute :online_course_status, :string, default: ""
  attribute :training_status, :string, default: ""
  attribute :ticketing_status, :string, default: ""
  attribute :year_created, :integer, default: 0

  attr_reader :statuses, :columns

  def initialize(attributes = {})
    super(attributes)
    self.statuses = attributes&.[](:statuses) || attributes&.[]("statuses")
    self.columns = attributes&.[](:columns) || attributes&.[]("columns")
  end

  def statuses=(values)
    @statuses = Array(values).flatten.filter_map { |value| value.to_s.strip.presence }.uniq
  end

  # Only a whole number is a number of years. Anything else is dropped rather
  # than left to read as zero, which would answer a question no one asked and
  # label the answer with what was typed.
  def years_worked=(value)
    text = value.to_s.strip
    super(/\A\d+\z/.match?(text) ? text : nil)
  end

  def columns=(values)
    @columns = Array(values).flatten.filter_map { |value| value.to_s.strip.presence }.uniq
  end

  def persisted?
    false
  end

  # A filter always turns its own column on, even when the matching
  # checkbox was never ticked -- searching on a value and then not being
  # shown it would be stranger than showing it unasked.
  def show_years_worked? = columns.include?("years_worked") || years_worked.present?
  def show_photo_status? = columns.include?("photo_status") || photo_status.present?
  def show_online_course? = columns.include?("online_course") || online_course_status.present?
  def show_training_status? = columns.include?("training_status") || training_status.present?
  def show_ticketing_info? = columns.include?("ticketing_info") || ticketing_status.present?
  def show_created_at? = columns.include?("created_at") || year_created.to_i.positive?

  def status_year_mode? = status_year.to_i.positive?

  # How many criteria the reader has set in each category. The panel opens the
  # categories carrying something and names the count on the ones it leaves
  # closed, so re-opening it after a search shows what was asked for rather
  # than all 90-odd controls again.
  def status_criteria_count = statuses.size + (status_year_mode? ? 1 : 0)

  def experience_criteria_count
    [years_worked, photo_status, online_course_status, training_status].count(&:present?)
  end

  def account_criteria_count
    (year_created.to_i.positive? ? 1 : 0) + (ticketing_status.present? ? 1 : 0)
  end

  def columns_criteria_count = columns.size

  def any_criteria? = query_params.any?

  # Drives the warn-then-confirm gate: no status checked means the search
  # would scan every account the Clubhouse has ever had.
  def blank_search? = statuses.blank?

  # Each option says what picking it means: the select chooses WHICH status
  # question the checkboxes answer, so a bare year ("2024") under a label that
  # sounded like a year picker read as neither.
  def status_year_options
    [["Current Status", 0]] +
      Current.year.downto(EARLIEST_STATUS_YEAR).map { |year| ["Updated During #{year}", year] }
  end

  def year_created_options
    [["Any", 0]] +
      Current.year.downto(EARLIEST_CREATED_YEAR).map { |year| [year.to_s, year] } +
      [[CREATED_PRIOR_LABEL, CREATED_PRIOR_SENTINEL]]
  end

  # The current criteria as a flat filter[] hash, minus anything at its
  # default -- used both to build the filter-chip URLs and to carry the
  # search forward onto the "Search anyway" confirmation link.
  def query_params
    values = {
      status_year: (status_year if status_year_mode?),
      years_worked: years_worked.presence,
      years_worked_op: (years_worked_op if years_worked.present?),
      photo_status: photo_status.presence,
      online_course_status: online_course_status.presence,
      training_status: training_status.presence,
      ticketing_status: ticketing_status.presence,
      year_created: (year_created if year_created.to_i.positive?)
    }.compact
    values[:statuses] = statuses if statuses.any?
    values[:columns] = columns if columns.any?

    return {} if values.empty?

    { PARAM_SCOPE => values }
  end
end
