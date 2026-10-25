# frozen_string_literal: true

# Unclaimed tickets whose holders have signed up for a late-season shift
# (Ember vc/access-documents/unclaimed-with-signups port).
#
# Upstream drew one flat table and left the reader to scan a Yes/No column for
# the people worth chasing. Here the sign-up split is a pair of counts in the
# header and a filter, so "signed up but still hasn't claimed" is one click.
class Ticketing::UnclaimedWithSignupsController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing reports."

  # The upstream CSV_COLUMNS, in order.
  CSV_HEADER = ["Callsign", "Status", "Email", "Type", "RAD", "Expires", "Has Sign Up"].freeze

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  def index
    load_rows

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-unclaimed-tickets.csv") }
    end
  end

  private

  # One read feeds the counts, the table, and the CSV, so an export can never
  # disagree with the table it was taken from.
  def load_rows
    @cutoff = UnclaimedTicketsWithSignupsReport.signup_cutoff(Current.year)
    all_rows = UnclaimedTicketsWithSignupsReport.execute(Current.year)

    # The header counts describe the whole report, so they hold still while the
    # filters narrow the table below them.
    @total_count = all_rows.size
    @signed_up_count = all_rows.count(&:has_signup)
    @no_signup_count = @total_count - @signed_up_count

    @filter_params = filter_params
    @index_params = UiComponents::FilterBarHelper.active_filters(@filter_params)
    @rows = apply_filters(all_rows)
    @filtered_count = @rows.size
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  def filter_params
    signup = params[:signup].presence
    type = params[:type].presence

    {
      signup: %w[yes no].include?(signup) ? signup : ALL_FILTER,
      type: AccessDocument::REGULAR_TICKET_TYPES.include?(type) ? type : ALL_FILTER
    }
  end

  # Filtering happens here rather than in the query because the header counts
  # need the whole report anyway: narrowing in SQL would mean a second read to
  # recompute them. The type filter joins it so both read the same way.
  def apply_filters(rows)
    signup = @filter_params[:signup]
    type = @filter_params[:type]

    rows = rows.select { |row| row.has_signup == (signup == "yes") } unless signup == ALL_FILTER
    rows = rows.select { |row| row.document.type == type } unless type == ALL_FILTER
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
        document.type_label,
        document.display_ref,
        document.expiry_date&.iso8601,
        row.has_signup ? "Y" : "N"
      ]
    end

    rows
  end
end
