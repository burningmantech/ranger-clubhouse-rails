# frozen_string_literal: true

# Where everyone lives, one country at a time.
#
# The index counts people by country. A country drills into its states when it
# has them on file, and into its people either way. Every level exports what it
# is showing.
class People::PeopleByLocationController < ApplicationController
  include CsvExportConcern

  layout "people"

  # The four roles that plan, train, and recruit -- the people who need to know
  # where the Rangers are coming from.
  authorize_role [Role::ADMIN, Role::MENTOR, Role::TRAINER, Role::VC],
                 message: "Admin, Mentor, Trainer, or VC role required to view people by location."

  before_action :setup_year
  before_action :setup_filters
  before_action :load_rows

  def index
    respond_to do |format|
      # The groupings are the page, so an export does not stop to build them.
      format.html do
        @counts = country_counts(@rows)
        @common_counts, @other_counts =
          @counts.partition { |code, _count| PeopleByLocationReport.common?(code) }
      end
      format.csv { send_csv(csv_rows(@rows), filename: csv_filename) }
    end
  end

  def country
    @country = params[:country].to_s
    # Only a plain string is a state. Sent as ?state[]=NV it arrives as an array
    # and as ?state[a]=b a Parameters object, and either one used to travel all
    # the way to the page, where it printed itself as the name of a place.
    @state = params[:state].is_a?(String) ? params[:state].presence : nil
    # A country with states on file shows them first, unless the reader has
    # already picked one.
    @show_states = PeopleByLocationReport.states?(@country) && @state.nil?

    people = @rows.select { |row| row.country_key == @country }
    @people = @state ? people.select { |row| row.state_key == @state } : people

    respond_to do |format|
      format.html { @counts = state_counts(@people) if @show_states }
      format.csv { send_csv(csv_rows(@people), filename: csv_filename) }
    end
  end

  private

  def setup_filters
    @participation = UiComponents::FilterBarHelper.known_filter(
      params[:participation], PeopleByLocationReport::PARTICIPATION_VALUES
    )
    @statuses = requested_statuses
    # An empty page means two different things -- the filters matched no one, or
    # there is no one there at all -- and only this tells them apart.
    #
    # The status boxes do not count. They only ever add people, so an empty page
    # is never their doing, and blaming them would send the reader off to undo
    # the one control that could have helped.
    @filtered = @participation != UiComponents::FilterBarHelper::ALL_FILTER
  end

  # Which of the hidden statuses to put back. Kept in the report's own order so
  # the chips read the same way every time, and narrowed to statuses this page
  # actually hides -- anything else would draw a chip that filtered nothing.
  #
  # A scalar arrives from ?statuses=retired and an array from ?statuses[]=retired;
  # ?statuses[a]=b arrives as neither and is dropped whole.
  def requested_statuses
    values = params[:statuses]
    values = [values] if values.is_a?(String)
    return [] unless values.is_a?(Array)

    PeopleByLocationReport::OPTIONAL_STATUSES & values.grep(String)
  end

  def load_rows
    @rows = PeopleByLocationReport.execute(
      year: @year,
      participation: (@participation unless @participation == UiComponents::FilterBarHelper::ALL_FILTER),
      statuses: @statuses,
      include_email: Current.can_view_email?
    )
  end

  # Counted in Ruby off the rows already on the page, so a heading and the list
  # under it can never disagree about how many people there are.
  def country_counts(rows)
    rows.group_by(&:country_key)
        .transform_values(&:size)
        .sort_by { |code, _count| sort_key(helpers.people_by_location_country_label(code)) }
  end

  # The bucket for people with no region on file sorts last rather than under
  # its own first letter, where it would read as one more state.
  def state_counts(rows)
    rows.group_by(&:state_key)
        .transform_values(&:size)
        .sort_by do |state, _count|
          [state == PeopleByLocationReport::NO_STATE ? 1 : 0,
           sort_key(helpers.people_by_location_state_label(@country, state))]
        end
  end

  # Place names carry accents, and raw string order puts every one of them after
  # Zimbabwe.
  def sort_key(label) = ActiveSupport::Inflector.transliterate(label).downcase

  # Names the slice being exported, so a reader who exports three of these does
  # not end up with three files of the same name.
  def csv_filename
    parts = ["#{@year}-people-by-location", @country, @state]
    "#{parts.compact_blank.map { |part| filename_part(part) }.join("-")}.csv"
  end

  # A value that is all punctuation, or written in another alphabet, comes back
  # from parameterize empty -- which used to leave a slice exporting under the
  # name of everything above it. The bytes stand in so the name stays distinct.
  def filename_part(part)
    part.to_s.parameterize.presence || part.to_s.unpack1("H*")
  end

  def csv_rows(rows)
    show_email = Current.can_view_email?
    header = ["Callsign", "First Name", "Last Name"]
    header << "Email" if show_email
    header.concat(["Status", "City", "State", "Postal Code", "Country",
                   "#{@year} Signed Up", "#{@year} Rangered"])

    [header] + rows.map do |row|
      cells = [row.callsign, row.first_name, row.last_name]
      cells << row.email if show_email
      cells.concat([row.status, row.city, row.state, row.zip,
                    helpers.people_by_location_country_label(row.country),
                    csv_yes_no(row.signed_up), csv_yes_no(row.rangered)])
    end
  end
end
