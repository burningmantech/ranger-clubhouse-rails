# frozen_string_literal: true

# Ticket holders who have not finished what the ticket was for
# (Ember vc/access-documents/claimed-with-no-signups port).
#
# The page is retitled: upstream called this "Claimed Tickets With No Sign Ups",
# but sign-ups were never a filter. See the report class for the actual rule.
# The route keeps the old name so the two codebases stay searchable together.
class Ticketing::ClaimedWithNoSignupsController < ApplicationController
  include CsvExportConcern

  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing reports."

  CSV_HEADER = ["Callsign", "Status", "Email", "First Name", "Last Name", "Preferred Name",
                "Tickets", "OC Completed?", "Has Sign-Ups?", "Rangered?", "Trained?",
                "Training Sessions"].freeze

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so this page reads short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # Every filter this page offers answers one of the table's yes/no columns —
  # which is the whole point of the report, so there is nothing else to filter
  # on. Ticket type is deliberately absent: a row can now carry both an SPT and
  # a staff credential, so "type" has no single answer.
  BOOLEAN_FILTERS = {
    course: { label: "Online Course", reader: :oc_completed },
    signup: { label: "Signed Up", reader: :has_signups },
    rangered: { label: "Rangered", reader: :rangered },
    trained: { label: "Trained", reader: :trained? }
  }.freeze

  def index
    load_rows

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{Current.year}-claimed-tickets-no-signups.csv") }
    end
  end

  private

  # One read feeds the counts, the table, and the CSV, so an export can never
  # disagree with the table it was taken from.
  def load_rows
    all_rows = ClaimedTicketsWithNoSignupsReport.execute(Current.year)

    # The header counts describe the whole report, so they hold still while the
    # filters narrow the table below them.
    @total_count = all_rows.size
    @no_course_count = all_rows.count { |row| !row.oc_completed }
    @not_rangered_count = all_rows.count { |row| !row.rangered }

    @filter_params = filter_params
    @index_params = UiComponents::FilterBarHelper.active_filters(@filter_params)
    @rows = apply_filters(all_rows)
    @filtered_count = @rows.size
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # bogus label in the filter bar.
  def filter_params
    BOOLEAN_FILTERS.keys.index_with do |key|
      value = params[key].presence
      %w[yes no].include?(value) ? value : ALL_FILTER
    end
  end

  # Filtering happens here rather than in the query because the header counts
  # need the whole report anyway: narrowing in SQL would mean a second read to
  # recompute them.
  def apply_filters(rows)
    @filter_params.reduce(rows) do |scope, (key, value)|
      next scope if value == ALL_FILTER

      reader = BOOLEAN_FILTERS.fetch(key)[:reader]
      scope.select { |row| row.public_send(reader) == (value == "yes") }
    end
  end

  def csv_rows
    rows = [CSV_HEADER]

    @rows.each do |row|
      person = row.person
      rows << [
        person.callsign,
        person.status,
        person.email,
        person.first_name,
        person.last_name,
        person.preferred_name,
        row.documents.map { |document| ticket_summary(document) }.join("; "),
        csv_yes_no(row.oc_completed),
        csv_yes_no(row.has_signups),
        csv_yes_no(row.rangered),
        csv_yes_no(row.trained?),
        # Upstream put the dates and the statuses in two columns joined by
        # embedded newlines, where a reader had to line them up by hand.
        row.trainings.map { |session| "#{session.begins_label} #{session.status}" }.join("; ")
      ]
    end

    rows
  end

  # The same "RAD-123 SPT claimed" shorthand the table shows.
  def ticket_summary(document)
    "#{document.display_ref} #{document.short_type_label} #{document.status}"
  end
end
