# frozen_string_literal: true

# The audit log written by the very first version of the Clubhouse. Entries run
# from 16 July 2008 to 24 October 2019 and nothing has been added since; the log
# is kept for historical and investigative reading only.
#
# Each row holds a whole sentence in its `event` column rather than a code and a
# payload, so searching means matching text.
class Clubhouse1Log < ApplicationRecord
  self.table_name = "log"

  # The database fills in `occurred`, and there are no created_at/updated_at
  # columns.
  self.record_timestamps = false

  PAGE_SIZE_DEFAULT = 50

  # The event column stores three-byte characters only, so no entry can hold an
  # emoji or any other four-byte character. Comparing one against the column
  # makes the database refuse the whole search, and the honest answer is that
  # nothing matches.
  FOUR_BYTE_CHARACTER = /[\u{10000}-\u{10FFFF}]/

  # Nothing writes here. The log closed in 2019.
  def readonly?
    true
  end

  belongs_to :user_person, class_name: "Person", optional: true
  belongs_to :current_person, class_name: "Person", optional: true

  class << self
    include Pagy::Method

    # Find log entries matching the given criteria.
    #
    # @param user_person_id [Integer, nil] the person who acted
    # @param current_person_id [Integer, nil] the person acted upon
    # @param start_time [Time, nil] occurred on or after
    # @param end_time [Time, nil] occurred on or before
    # @param event_prefixes [Array<String>] match an event starting with any of these
    # @param event_text [String, nil] match an event containing this anywhere
    # @param sort ["asc", "desc"] oldest or newest first
    # @param page [Integer] page number, 1 or higher
    # @param page_size [Integer] rows per page
    # @return [Array] the page's Pagy (countless) and its rows
    def find_for_query(user_person_id: nil, current_person_id: nil, start_time: nil, end_time: nil,
                       event_prefixes: [], event_text: nil, sort: "desc", page: 1,
                       page_size: PAGE_SIZE_DEFAULT)
      page = [page.to_i, 1].max
      page_size = page_size.to_i
      page_size = PAGE_SIZE_DEFAULT if page_size <= 0

      scope = all
      scope = scope.where(user_person_id:) if user_person_id.present?
      scope = scope.where(current_person_id:) if current_person_id.present?
      scope = scope.where("occurred >= ?", start_time) if start_time.present?
      scope = scope.where("occurred <= ?", end_time) if end_time.present?
      scope = scope.where(event_prefix_condition(event_prefixes)) if event_prefixes.present?
      if event_text.present?
        scope = if event_text.match?(FOUR_BYTE_CHARACTER)
                  scope.none
                else
                  scope.where_like("event", "%#{sanitize_sql_like(event_text)}%")
                end
      end

      # The timestamp keeps whole seconds only and the first Clubhouse wrote in
      # bursts, so the id breaks ties. Without it the order within a second is
      # undefined, and one row could sit on two pages while another appears on
      # none.
      direction = (sort.to_s == "asc") ? :asc : :desc
      scope = scope.order(occurred: direction, id: direction).includes(:user_person, :current_person)

      # Pagy's countless mode: one row past the page is what tells the reader a
      # next page exists. The `event` column carries no index, so counting the
      # matches would mean a second scan of all 2.4 million rows for a number
      # the page never shows.
      pagy(:countless, scope, page:, limit: page_size, request: { params: {} })
    end

    private

    # Matches an event beginning with any of the given prefixes.
    #
    # The prefixes are escaped like any other search text: `!EDBM_E_ERROR`
    # holds a literal underscore, which LIKE would otherwise read as
    # "any single character" and quietly widen the match.
    def event_prefix_condition(prefixes)
      table = arel_table

      prefixes.map { |prefix| table[:event].matches("#{sanitize_sql_like(prefix)}%") }
              .reduce { |combined, condition| combined.or(condition) }
    end
  end
end
