# frozen_string_literal: true

# The search across the top of the Legacy Clubhouse 1 Log page: the Action
# Logs search, over the columns legacy_log has.
class LegacyLogFilterForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  PARAM_SCOPE = "filter"

  # Far past any real page. The page number is multiplied into a SQL OFFSET,
  # and an unbounded one overflows the database's limit rather than coming
  # back empty.
  MAX_PAGE = 100_000

  # The converted vocabulary, grouped as Action Logs groups its own: the event
  # names or `%` patterns a category stands for, and its label. Unknown is
  # every statement the conversion could not read.
  EVENT_FILTER_LABELS = {
    "person-create,person-update,person-delete" => "Person",
    "person-slot-%" => "Schedule",
    "person-position-%" => "Positions",
    "person-role-%" => "Roles",
    "timesheet-%" => "Timesheets",
    "manual-review-%" => "Manual Review",
    "access-document-%" => "Tickets",
    "asset-%,person-asset-%" => "Assets",
    "slot-%" => "Slots",
    "person-message-%,contact-log-%" => "Messages",
    "broadcast-%,person-alert-%,alert-%" => "Broadcasts",
    "person-mentor-%,trainee-status-%" => "Mentoring",
    "position-%,role-%,xfield-%,xgroup-%,xoption-%,bmid-%,radio-eligible-%" => "Configuration",
    LegacyLog::UNKNOWN => "Unknown"
  }.freeze

  attribute :person_callsign, :string
  attribute :target_person_callsign, :string
  attribute :start_time, :string
  attribute :end_time, :string
  attribute :event_name, :string
  attribute :page, :integer, default: 1
  attribute :event_filters, default: -> { [] }

  def initialize(attributes = {})
    super
    self.page = page.to_i.clamp(1, MAX_PAGE)
  end

  # Only the categories the page offers; anything else in the URL is dropped.
  def event_filters=(values)
    super(Array(values) & EVENT_FILTER_LABELS.keys)
  end

  # The chosen categories' events and the typed event name, any of them
  # matching.
  def events
    (event_filters.flat_map { |value| value.split(",") } + [event_name.to_s])
      .filter_map { |value| value.strip.presence }
      .uniq
  end

  def parsed_start_time
    UiComponents::FilterBarHelper.filter_time(start_time)
  end

  def parsed_end_time
    UiComponents::FilterBarHelper.filter_time(end_time)
  end

  # The search as it belongs in a URL, ready for a chip or a pager link. A
  # time that could not be read is left out: it narrowed nothing.
  def query_params(page: nil)
    values = {
      person_callsign: person_callsign.presence,
      target_person_callsign: target_person_callsign.presence,
      start_time: (start_time.presence if parsed_start_time),
      end_time: (end_time.presence if parsed_end_time),
      event_name: event_name.presence
    }.compact
    values[:event_filters] = event_filters if event_filters.any?
    values[:page] = page if page.to_i > 1
    return {} if values.empty?

    { PARAM_SCOPE => values }
  end
end
