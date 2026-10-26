# frozen_string_literal: true

# Every request the Clubhouse answered: who asked, what they asked for, what
# came back, and how long it took.
class RequestLog < ApplicationRecord
  self.table_name = "request_log"

  # The database fills in created_at, and there is no updated_at column.
  self.record_timestamps = false

  PAGE_SIZE_DEFAULT = 50
  EXPIRE_DAYS_DEFAULT = 7

  # Old rows are removed in chunks this size so one statement never locks the
  # whole table.
  EXPIRE_BATCH_SIZE = 5_000

  # A rejected request can answer with a whole page of HTML. Keep enough to
  # see what happened without carrying the page around.
  PAYLOAD_LIMIT = 16 * 1024

  # What the status filter offers. Searching by range rather than by exact
  # code is what the reader actually wants -- "show me the failures" -- and it
  # matches the (status, created_at) index.
  STATUS_CLASSES = {
    "2xx" => 200..299,
    "3xx" => 300..399,
    "4xx" => 400..499,
    "5xx" => 500..599
  }.freeze

  STATUS_CLASS_OPTIONS = [
    ["Succeeded (2xx)", "2xx"],
    ["Redirected (3xx)", "3xx"],
    ["Rejected (4xx)", "4xx"],
    ["Failed (5xx)", "5xx"]
  ].freeze

  HTTP_METHODS = %w[GET POST PATCH PUT DELETE].freeze

  belongs_to :person, optional: true

  # The Live mode's reads. The id orders the rows, as find_for_query explains:
  # the timestamp keeps whole seconds, and requests arrive in bursts.
  scope :newest_first, -> { order(id: :desc).includes(:person) }
  scope :after_id, ->(id) { where(id: id.to_i.next..) }

  # The address the request came from. Rows written before the Clubhouse
  # answered its own requests hold the whole forwarded-for chain, and the
  # client is the last address in it.
  def client_ip
    ips.to_s.split(",").last&.strip.presence
  end

  class << self
    include Pagy::Method

    # Find request log records matching the given criteria, newest first.
    #
    # @param person_id [Integer, nil] only this person's requests
    # @param status_class [String, nil] one of STATUS_CLASSES ("4xx")
    # @param http_method [String, nil] GET, POST, and so on
    # @param start_time [Time, nil] recorded on or after
    # @param end_time [Time, nil] recorded on or before
    # @param ip [String, nil] any part of the address
    # @param page [Integer] page number, 1 or higher, held to a page that exists
    # @return [Array(Pagy::Offset, Array<RequestLog>)] the page, and its rows
    def find_for_query(person_id: nil, status_class: nil, http_method: nil,
                       start_time: nil, end_time: nil, ip: nil, page: 1)
      scope = all
      scope = scope.where(person_id:) if person_id.present?
      scope = scope.where(status: STATUS_CLASSES[status_class]) if STATUS_CLASSES.key?(status_class)
      scope = scope.where(method: http_method) if http_method.present?
      scope = scope.where("created_at >= ?", start_time) if start_time.present?
      scope = scope.where("created_at <= ?", end_time) if end_time.present?
      scope = scope.where_like("ips", "%#{sanitize_sql_like(ip)}%") if ip.present?

      # Requests arrive in bursts and the timestamp keeps whole seconds only,
      # so the id breaks ties. Without it the order within a second is
      # undefined, and one row could sit on two pages while another appears on
      # none.
      scope = scope.order(created_at: :desc, id: :desc).includes(:person)

      paging = { limit: PAGE_SIZE_DEFAULT, request: { params: {} } }
      pagy, records = pagy(:offset, scope, page:, **paging)
      # Held to a page that exists. A bookmarked or hand-typed number would
      # otherwise ask for rows far past the end and leave the reader on an
      # empty table labelled as though it were full.
      pagy, records = pagy(:offset, scope, page: pagy.last, count: pagy.count, **paging) if pagy.page > pagy.last

      [pagy, records.to_a]
    end

    # Record one answered request.
    #
    # @param completion_time [Float] elapsed milliseconds
    def record(person_id:, ips:, url:, status:, method:, response_size:, completion_time:,
               request_payload: nil, response_payload: nil)
      create!(
        person_id:,
        ips:,
        url:,
        status:,
        method:,
        response_size:,
        completion_time: completion_time.round(2),
        request_payload: truncate_payload(request_payload),
        response_payload: truncate_payload(response_payload)
      )
    end

    # Remove records older than the retention window.
    #
    # @return [Integer] how many rows were removed
    def expire(days = EXPIRE_DAYS_DEFAULT)
      where("created_at <= ?", days.days.ago)
        .in_batches(of: EXPIRE_BATCH_SIZE)
        .sum(&:delete_all)
    end

    private

    def truncate_payload(payload)
      payload&.to_s&.truncate_bytes(PAYLOAD_LIMIT, omission: "")
    end
  end
end
