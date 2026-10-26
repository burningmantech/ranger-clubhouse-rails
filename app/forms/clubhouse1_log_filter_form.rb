# frozen_string_literal: true

# The search across the top of the Clubhouse 1 Log page.
class Clubhouse1LogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a SQL OFFSET,
  # and an unbounded one overflows the database's limit rather than simply
  # coming back empty.
  MAX_PAGE = 100_000

  # The log opened in 2008 and closed in 2019. A year outside this range is a
  # typo, and the database answers one by ignoring the comparison rather than
  # rejecting it -- so a search for "99999-01-01" would come back with every
  # row instead of none.
  VALID_YEARS = (1900..2100).freeze

  # Every kind of entry the first Clubhouse wrote, grouped into something a
  # reader can pick from: a label, the key that travels in the URL, and the
  # event openings that key stands for.
  #
  # Each opening in the log belongs to exactly one group, so no entry is beyond
  # reach of the checkboxes.
  EVENT_CATEGORIES = [
    { label: "Login/Logout", key: "login", prefixes: ["#login", "#logout"] },
    { label: "Login Failures", key: "login-failure", prefixes: ["!NO-LOGIN", "!SIGNON"] },
    { label: "Password Events", key: "password", prefixes: ["#password-changed"] },
    { label: "Admin Mode", key: "admin", prefixes: ["#admin", "#non-admin"] },
    { label: "Insufficient Role", key: "role", prefixes: ["!ROLE"] },
    { label: "Email Events", key: "email", prefixes: ["#reminder", "#EA"] },
    { label: "Email Failures", key: "email-failure", prefixes: ["!EMAIL", "!MAIL"] },
    { label: "Text Message Failures", key: "sms-failure", prefixes: ["!SMS"] },
    { label: "Invalid Input", key: "invalid", prefixes: ["!INVAL"] },
    { label: "General Errors", key: "error", prefixes: ["!ERR"] },
    { label: "Fatal Events", key: "fatal", prefixes: ["!FATAL"] },
    { label: "Database Errors", key: "database", prefixes: ["!DB"] },
    { label: "Integration Errors", key: "integration", prefixes: ["!CLOUD", "!EDBM_E_ERROR"] },
    { label: "Shift Credits", key: "credit", prefixes: ["#credit"] },
    { label: "Requests", key: "request", prefixes: ["#REQ"] },
    { label: "Database Changes", key: "sql", prefixes: ["+", "-", "="] }
  ].freeze

  CATEGORY_LABELS = EVENT_CATEGORIES.to_h { |category| [category[:key], category[:label]] }.freeze
  CATEGORY_PREFIXES = EVENT_CATEGORIES.to_h { |category| [category[:key], category[:prefixes]] }.freeze

  SORT_OPTIONS = [
    ["Newest first", "desc"],
    ["Oldest first", "asc"]
  ].freeze

  attribute :user_callsign, :string
  attribute :target_callsign, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :event_text, :string
  attribute :sort, :string, default: "desc"
  attribute :page, :integer, default: 1

  attr_reader :event_categories

  def initialize(attributes = {})
    super(attributes)
    self.event_categories = attributes&.[](:event_categories) || attributes&.[]("event_categories")
    self.page = page.to_i.clamp(1, MAX_PAGE)
    self.sort = "desc" unless SORT_OPTIONS.any? { |_label, value| value == sort }
  end

  def event_categories=(values)
    @event_categories = Array(values).flatten.filter_map { |value| value.to_s.strip.presence }
                                     .uniq
                                     .select { |value| CATEGORY_PREFIXES.key?(value) }
  end

  def persisted?
    false
  end

  # The event openings the chosen categories stand for.
  def event_prefixes
    event_categories.flat_map { |key| CATEGORY_PREFIXES.fetch(key) }.uniq
  end

  def parsed_start_time
    parse_time(start_time)
  end

  def parsed_end_time
    parse_time(end_time)
  end

  # The search as it belongs in a URL, ready for a chip or a pager link.
  def query_params(page: nil)
    values = {
      user_callsign: user_callsign.presence,
      target_callsign: target_callsign.presence,
      start_time: (start_time.presence if parsed_start_time),
      end_time: (end_time.presence if parsed_end_time),
      event_text: event_text.presence,
      sort: (sort == "asc") ? "asc" : nil
    }.compact
    values[:event_categories] = event_categories if event_categories.any?
    values[:page] = page if page.present? && page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end

  private

  # A time read by the shared whole-date rule, and inside VALID_YEARS.
  def parse_time(value)
    time = UiComponents::FilterBarHelper.filter_time(value)
    time if time && VALID_YEARS.cover?(time.year)
  end
end
