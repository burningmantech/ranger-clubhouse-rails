# frozen_string_literal: true

# Shirt sizes for everyone who is a Prospective or an Alpha, plus the size runs
# the quartermaster orders against. (Ember reports/alpha-shirts port.)
#
# Deliberately NOT year-scoped: upstream's query filters on status alone, so
# this is a snapshot of who holds those statuses right now. Only the export
# filenames carry a year, matching upstream's `${year}-alpha-shirts.csv`.
class Quartermaster::AlphaShirtsController < ApplicationController
  include CsvExportConcern
  include ShirtFilterConcern # kind selects + missing checkbox, shared with Potential Shirts

  layout "quartermaster"

  authorize_role [Role::ADMIN, Role::QUARTERMASTER, Role::MENTOR],
                 message: "Admin, Quartermaster, or Mentor role required to view Alpha shirt sizes."

  ROSTER_HEADER = ["Callsign", "Status", "First Name", "Last Name", "Email",
                   "T-Shirt", "T-Shirt Backup", "Long Sleeve Shirt"].freeze

  COUNTS_HEADER = ["Shirt Type", "Size", "Count"].freeze

  def index
    load_report

    respond_to do |format|
      format.html
      format.csv { send_csv(roster_rows, filename: "#{Current.year}-alpha-shirts.csv") }
    end
  end

  # Upstream downloaded one file per shirt kind, an artifact of its tabbed
  # layout. One file naming its kind per row opens as one sheet instead.
  def counts
    load_report

    send_csv(counts_rows, filename: "#{Current.year}-alpha-shirt-counts.csv")
  end

  private

  def load_report
    @people = Person.where(status: [Person::ALPHA, Person::PROSPECTIVE])
                    .includes(:tshirt_swag, :tshirt_secondary_swag, :long_sleeve_swag)
                    .order(:callsign)
                    .to_a

    @kinds = ShirtTotals.for_people(@people)
    @status_counts = @people.group_by(&:status).transform_values(&:size)
    @alpha_count = @status_counts.fetch(Person::ALPHA, 0)
    @prospective_count = @status_counts.fetch(Person::PROSPECTIVE, 0)

    # Counted once per person however many of their three sizes are blank --
    # this is a list of people to chase, not of gaps.
    @incomplete_count = @people.count { |person| ShirtTotals.missing_any_size?(person) }

    @filter_params = filter_params
    @filtered_people = filtered(@people)
  end

  # Status first, then one per shirt kind, then the catch-all -- the order the
  # chips read in. The kind and missing params are normalised by
  # ShirtFilterConcern.
  def filter_params
    { status: params[:status].presence || ALL,
      **shirt_filter_params }
  end

  # Filters narrow the roster in memory: it is a small array already loaded for
  # the totals, and re-querying would only re-derive it. The size runs, the
  # stats, and both exports stay whole on purpose -- they are the order sheet,
  # and filtering to "Unknown" must not make it look like no one needs a shirt.
  def filtered(people)
    people.select do |person|
      status = @filter_params[:status]
      (status == ALL || person.status == status) && shirt_filters_match?(person, @filter_params)
    end
  end

  def roster_rows
    rows = [ROSTER_HEADER]

    @people.each do |person|
      rows << [person.callsign,
               person.status,
               person.desired_first_name,
               person.last_name,
               person.email,
               ShirtTotals.title_for(person, :tshirt_swag),
               ShirtTotals.title_for(person, :tshirt_secondary_swag),
               ShirtTotals.title_for(person, :long_sleeve_swag)]
    end

    rows
  end

  def counts_rows
    rows = [COUNTS_HEADER]

    @kinds.each do |kind|
      kind.sizes.each { |size| rows << [kind.name, size.title, size.count] }
    end

    rows
  end
end
