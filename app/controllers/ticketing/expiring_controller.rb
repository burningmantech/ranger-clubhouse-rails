# frozen_string_literal: true

# Tickets that lapse at the end of the coming event
# (Ember vc/access-documents/expiring port).
#
# Upstream called the page "Unclaimed Expiring Tickets" while the query also
# returned banked tickets, which are the opposite of unclaimed. Here the two
# statuses are counted separately and filterable, and tickets that lapsed in an
# earlier year are flagged as the data cleanup they are rather than blending in
# with the people worth chasing.
class Ticketing::ExpiringController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing reports."

  # The upstream CSV_COLUMNS, in order. The last one carried a full date
  # upstream; it matches the table now and carries the year alone.
  CSV_HEADER = ["Callsign", "Status", "Email", "RAD", "Ticket Type", "Ticket Status", "Expires After"].freeze

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  def index
    load_rows

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-expiring-access-documents.csv") }
    end
  end

  private

  # One read feeds the counts, the table, the email list, and the CSV, so an
  # export can never disagree with the table it was taken from.
  def load_rows
    all_rows = ExpiringTicketsReport.execute(Current.year)

    # The header counts describe the whole report, so they hold still while the
    # filters narrow the table below them.
    @total_count = all_rows.size
    @expired_count = all_rows.count(&:expired)
    @expiring_count = @total_count - @expired_count

    @filter_params = filter_params
    @index_params = UiComponents::FilterBarHelper.active_filters(@filter_params)
    @rows = apply_filters(all_rows)
    @filtered_count = @rows.size
    # Upstream's <EmailList>: one address per person, in the order shown.
    @emails = @rows.filter_map { |row| row.person.email.presence }.uniq
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  def filter_params
    status = params[:status].presence
    type = params[:type].presence
    expired = params[:expired].presence

    {
      status: ExpiringTicketsReport::STATUSES.include?(status) ? status : ALL_FILTER,
      type: AccessDocument::REGULAR_TICKET_TYPES.include?(type) ? type : ALL_FILTER,
      expired: %w[yes no].include?(expired) ? expired : ALL_FILTER
    }
  end

  # Filtering happens here rather than in the query because the header counts
  # need the whole report anyway: narrowing in SQL would mean a second read to
  # recompute them.
  def apply_filters(rows)
    status = @filter_params[:status]
    type = @filter_params[:type]
    expired = @filter_params[:expired]

    rows = rows.select { |row| row.document.status == status } unless status == ALL_FILTER
    rows = rows.select { |row| row.document.type == type } unless type == ALL_FILTER
    rows = rows.select { |row| row.expired == (expired == "yes") } unless expired == ALL_FILTER
    rows
  end

  def csv_rows
    rows = [CSV_HEADER]

    @rows.each do |row|
      document = row.document
      rows << [
        row.person.callsign,
        row.person.status,
        row.person.email,
        document.display_ref,
        document.type_label,
        document.status,
        document.expiry_date.year
      ]
    end

    rows
  end
end
