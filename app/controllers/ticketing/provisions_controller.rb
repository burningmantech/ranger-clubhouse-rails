# frozen_string_literal: true

# Every current provision — meal passes, shower passes, and event radios — for
# the ticketing crew (Ember vc/access-documents/provisions port).
#
# Upstream loaded the whole list once and filtered it in the browser; here the
# three filters are ordinary GET params applied server-side, so a narrowed view
# is a shareable URL and the CSV export carries the same query string.
#
# Editing and deleting come from ProvisionCrudConcern. Creating does not: a new
# provision needs a person chosen first, which is the person pages' job.
class Ticketing::ProvisionsController < ApplicationController
  include CsvExportConcern
  include ProvisionCrudConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to administer provisions."

  # The upstream CSV_COLUMNS, in order.
  CSV_HEADER = ["Provision ID", "Person", "Type", "Status", "Item Count", "Allocated?", "Source Year"].freeze

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # The allocated filter is a tri-state, so it travels as a string like the
  # other two rather than as a boolean param.
  ALLOCATED_VALUES = TicketsProvisionsHelper::PROVISION_ALLOCATED_OPTIONS.map(&:last).freeze

  def index
    load_provisions

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-current-provisions.csv") }
    end
  end

  private

  # One filtered read feeds both formats, so an export can never disagree with
  # the table it was taken from.
  def load_provisions
    @filter_params = filter_params
    @index_params = active_filters
    @provisions = Provision.find_for_query(provisions_query)
    @filtered_count = @provisions.size
    # "Showing X of Y": Y is the whole current set, so it holds still while the
    # filters narrow X.
    @total_count = Provision.current.count
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  #
  # Memoized because the CRUD actions read the filters back to rebuild the
  # return URL, where load_provisions never runs.
  def filter_params
    @filters ||= begin
      type = params[:type].presence
      status = params[:status].presence
      allocated = params[:allocated].presence

      {
        type: Provision::ALL_TYPES.include?(type) ? type : ALL_FILTER,
        status: Provision::CURRENT_STATUSES.include?(status) ? status : ALL_FILTER,
        allocated: ALLOCATED_VALUES.include?(allocated) ? allocated : ALL_FILTER
      }
    end
  end

  # The filters worth putting in a URL: chips, the CSV link, and the round trip
  # through the edit page all carry exactly these.
  def active_filters
    UiComponents::FilterBarHelper.active_filters(filter_params)
  end

  # No status filter means the four current statuses, passed explicitly rather
  # than leaning on find_for_query's blank-status default: the two agree today,
  # but only this page's list is meant to define what "current" shows.
  def provisions_query
    status = filter_params[:status]
    type = filter_params[:type]
    allocated = filter_params[:allocated]

    query = { include_person: true }
    query[:status] = status == ALL_FILTER ? Provision::CURRENT_STATUSES : status
    query[:type] = type unless type == ALL_FILTER
    query[:is_allocated] = allocated == "1" unless allocated == ALL_FILTER
    query
  end

  def csv_rows
    rows = [CSV_HEADER]

    @provisions.each do |provision|
      rows << [
        provision.display_ref,
        provision.person&.callsign,
        provision.type_label,
        provision.status,
        # Only event radios carry a count; the table blanks the rest the same way.
        (provision.item_count if provision.item_count&.positive?),
        provision.is_allocated ? "Yes" : "No",
        provision.source_year
      ]
    end

    rows
  end

  def find_provision
    Provision.find(params[:id])
  end

  # Editing returns to the list exactly as the admin left it, so the filters
  # they were reading through survive the round trip.
  def provision_form_path(provision)
    ticketing_provision_path(provision, active_filters)
  end

  def provision_return_path
    ticketing_provisions_path(active_filters)
  end

  def provision_return_label
    "Provisions"
  end
end
