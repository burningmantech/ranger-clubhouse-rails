# frozen_string_literal: true

# Advanced search across every account: current or as-of-a-year status, years
# rangered, photo status, and this year's online course, in-person training,
# and ticketing progress. Read only, with a CSV export of the same rows.
#
# A bare visit shows the criteria panel with nothing searched yet -- the
# search only runs once the form has actually been submitted, which is what
# the presence of the filter param means (a submission with every field left
# at its default still carries filter[status_year]=0 and the rest, so the key
# itself is what tells the two apart).
#
# The HTML render is paginated -- a wide search matches thousands of accounts,
# and one document carrying all of them is unreadable on a desk and undeliverable
# on playa -- while the CSV export always carries the whole match, whatever page
# the reader was on.
class People::SearchController < ApplicationController
  include CsvExportConcern
  include Pagy::Method

  layout "people"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to search all accounts."

  CSV_HEADER = ["Callsign", "First Name", "Last Name", "Email"].freeze

  # Paged in memory, as Asset History is: the report's year/course/training
  # filters run after the person query, so the full match is in hand anyway.
  PAGE_SIZE = 100

  def index
    @searched = params.key?(PersonSearchForm::PARAM_SCOPE)
    # Kept for the links this page draws back to itself: they have to carry the
    # criteria forward, and only the fields the search actually reads. The
    # confirmation travels with them, or an export taken after a confirmed
    # wide search would be stopped by the very warning it already answered.
    @filter = filter_params.to_h
    @confirmed = params[:confirmed].presence
    @form = PersonSearchForm.new(@filter)
    @people = []
    @error = nil
    @needs_confirmation = false
    @page_rows = []

    run_search if @searched

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "people-search.csv") }
    end
  end

  private

  def filter_params
    scoped_params(PersonSearchForm::PARAM_SCOPE,
                  :status_year, :years_worked, :years_worked_op, :photo_status,
                  :online_course_status, :training_status, :ticketing_status, :year_created,
                  statuses: [], columns: [])
  end

  # Guards run before the report ever sees the form: a status-change year with
  # no statuses checked is meaningless (mirrors upstream's error dialog, but as
  # a page rather than a raise); a years-rangered value that is not a whole
  # number is named rather than silently dropped; and no statuses at all would
  # scan every account the Clubhouse has ever had -- which needs a second click
  # to confirm rather than running on the first submit.
  def run_search
    if @form.status_year_mode? && @form.blank_search?
      @error = "Check the statuses you are interested in — a status change year needs at least one status checked."
      return
    end

    if years_worked_invalid?
      @error = "Years rangered must be a whole number."
      return
    end

    if @form.blank_search? && params[:confirmed].blank?
      @needs_confirmation = true
      return
    end

    @people = PeopleSearchReport.call(@form)
    @count_label = "Found #{helpers.number_with_delimiter(@people.size)} " \
                   "#{"person".pluralize(@people.size)}."
    paginate_people
  end

  # The form nils anything that is not a whole number so the report never sees
  # it -- but a criterion the reader typed vanishing without a word reads as a
  # search that lied. Present-but-unparsed means an error, not a shrug.
  def years_worked_invalid?
    @filter["years_worked"].to_s.strip.present? && @form.years_worked.nil?
  end

  # A page past the last is the last: Pagy answers it empty. to_s first: a
  # page[] param arrives as an Array, which has no to_i.
  def paginate_people
    paging = { limit: PAGE_SIZE, request: { params: {} } }
    @pagy, @page_rows = pagy(:offset, @people, page: [params[:page].to_s.to_i, 1].max, **paging)
    return if @pagy.page <= @pagy.last

    @pagy, @page_rows = pagy(:offset, @people, page: @pagy.last, count: @pagy.count, **paging)
  end

  def csv_rows
    columns = helpers.people_search_columns(@form)
    [CSV_HEADER + columns.map { |column| column[:heading] }] +
      @people.map { |row| csv_row(row, columns) }
  end

  def csv_row(row, columns)
    [row.person.callsign, row.person.first_name, row.person.last_name, row.person.email] +
      columns.map { |column| helpers.people_search_csv_value(row, column[:key]) }
  end
end
