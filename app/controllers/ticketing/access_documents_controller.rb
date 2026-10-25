# frozen_string_literal: true

# Access documents — tickets, vehicle passes, and setup access passes — for the
# ticketing crew (Ember vc/access-documents index port).
#
# The Ember page's two tabs became two pages: #index summarizes every current
# holder one row at a time, and #records lists the documents themselves with
# type and status filters plus a CSV export.
class Ticketing::AccessDocumentsController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing records."

  # The upstream CSV_COLUMNS, in order.
  CSV_HEADER = ["RAD", "Person", "Type", "Arrival", "S.O. Name", "Source Year", "Expires", "Comments"].freeze

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # The summary's counted selects, in panel order.
  SUMMARY_SELECTS = %i[status type person_status arrival].freeze

  # The lib also returns the allowable arrival-day window, but every error
  # string already names the window it broke, so the page has no use for it.
  #
  # The filters narrow the built rows rather than the query: the page reads
  # every current document anyway, and the person-level checks (arrival,
  # Weird Stuff) only exist once a row is built.
  def index
    rows = TicketingManagement.retrieve_current_by_person[:people].map do |entry|
      AccessDocumentSummaryRow.new(person: entry[:person],
                                   documents: entry[:documents],
                                   errors: entry[:errors])
    end
    @total_count = rows.size

    # What the whole page holds, per select: the choices each one offers, and
    # for Arrival the URL values that are valid at all. Built before the
    # params are vetted for that reason.
    @held_counts = SUMMARY_SELECTS.to_h { |key| [key, summary_tally(rows, key)] }
    @filter_params = summary_filter_params
    @index_params = UiComponents::FilterBarHelper.active_filters(@filter_params)

    # Each choice's count is the roster it delivers under the OTHER active
    # filters -- a select must not narrow itself -- so the numbers shrink as
    # filters stack while the choices on offer hold still.
    @matching_counts = SUMMARY_SELECTS.to_h do |key|
      others = summary_filters(except: key)
      [key, summary_tally(rows.select { |row| row.matches?(**others) }, key, others)]
    end

    filters = summary_filters
    @rows = rows.select { |row| row.matches?(**filters) }
  end

  def records
    load_records

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-access-documents.csv") }
    end
  end

  private

  # --- summary filters -------------------------------------------------------

  # Every value is checked against the list the page offers, the same way
  # filter_params below does for the records page.
  def summary_filter_params
    helper = Ticketing::AccessDocumentsHelper
    bar = UiComponents::FilterBarHelper

    {
      status: bar.known_filter(params[:status], AccessDocument::CURRENT_STATUSES),
      type: bar.known_filter(params[:type], helper::SUMMARY_TICKET_TYPES),
      person_status: bar.known_filter(params[:person_status], Person::ALL_STATUSES),
      arrival: bar.known_filter(params[:arrival], @held_counts[:arrival].keys),
      issues: bar.known_filter(params[:issues], [helper::ISSUES_ONLY])
    }
  end

  # The active filters as AccessDocumentSummaryRow#matches? takes them: only
  # the ones in play, the Arrival cell value in place of its URL name, and
  # Weird Stuff as a flag. `except:` leaves one select's own choice out, for
  # its counts.
  def summary_filters(except: nil)
    active = @index_params.except(except)

    active.slice(:status, :type, :person_status).merge(
      arrival_value: (helpers.arrival_filter_value(active[:arrival]) if active[:arrival]),
      issues_only: active.key?(:issues)
    )
  end

  # {value => people} for one select over `rows`, each row filing once under
  # every value it holds. `filters` are the other active filters, which
  # narrow the documents that count for Status and Ticket Type.
  def summary_tally(rows, key, filters = {})
    rows.flat_map { |row| summary_row_values(row, key, filters) }.tally
  end

  def summary_row_values(row, key, filters)
    case key
    when :status then row.document_statuses(type: filters[:type])
    when :type then row.document_types(status: filters[:status])
    when :person_status then [row.person.status]
    when :arrival then [helpers.arrival_filter_choice(row)].compact
    end
  end

  # One filtered read feeds both formats, so an export can never disagree with
  # the table it was taken from.
  def load_records
    @filter_params = filter_params
    @index_params = UiComponents::FilterBarHelper.active_filters(@filter_params)
    @documents = AccessDocument.find_for_query(records_query)
    @filtered_count = @documents.size
    # "Showing X of Y": Y is the whole current set, so it holds still while the
    # filters narrow X.
    @total_count = AccessDocument.current.count
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  def filter_params
    type = params[:type].presence
    status = params[:status].presence

    {
      type: AccessDocument::TYPE_LABELS.key?(type) ? type : ALL_FILTER,
      status: AccessDocument::CURRENT_STATUSES.include?(status) ? status : ALL_FILTER
    }
  end

  # No status filter means the four current statuses, passed explicitly.
  # find_for_query's blank-status default keeps turned_down, which this page
  # deliberately drops; other pages rely on that default, so it stays put.
  def records_query
    status = @filter_params[:status]
    type = @filter_params[:type]

    query = { include_person: true }
    query[:status] = status == ALL_FILTER ? AccessDocument::CURRENT_STATUSES : status
    query[:type] = type unless type == ALL_FILTER
    query
  end

  def csv_rows
    rows = [CSV_HEADER]

    @documents.each do |document|
      rows << [
        document.display_ref,
        document.person&.callsign,
        document.type_label,
        # The table renders the same label; [1] is its styling flag, unused here.
        helpers.arrival_label(document).first,
        (document.name if document.type == AccessDocument::SAPSO),
        document.source_year,
        document.expiry_date&.year,
        document.comments
      ]
    end

    rows
  end
end
