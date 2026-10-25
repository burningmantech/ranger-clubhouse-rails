# frozen_string_literal: true

# Where everyone lives. One row per person: their address as it stands today,
# plus two facts about the chosen event year -- did they sign up for a shift,
# and did they ranger.
#
# Only those two columns follow the year. An address is the person's current
# one, so picking a different year never moves anyone to a different country.
class PeopleByLocationReport
  # Statuses left out unless the reader asks for them. These are people who
  # are not Rangers right now -- some have left for good, others have applied
  # but not joined yet -- and a location report is normally about who is
  # around. Each one can be switched back on by itself.
  OPTIONAL_STATUSES = [
    Person::ALPHA,
    Person::AUDITOR,
    Person::BONKED,
    Person::DECEASED,
    Person::DISMISSED,
    Person::PAST_PROSPECTIVE,
    Person::PROSPECTIVE,
    Person::RESIGNED,
    Person::RETIRED,
    Person::UBERBONKED
  ].freeze

  # The participation choices. "All" is the absence of one, and is spelled by
  # the filter bar rather than here.
  SIGNED_UP = "signed-up"
  RANGERED = "rangered"
  BOTH = "both"
  EITHER = "either"
  PARTICIPATION_VALUES = [SIGNED_UP, RANGERED, BOTH, EITHER].freeze

  # Countries this report breaks down by state or province. The same list the
  # person record asks a state of, so a country cannot be one to fill in and
  # the other to ignore.
  STATE_COUNTRIES = Person::COUNTRIES_REQUIRING_STATE

  # The four countries nearly everyone lives in. They lead the index so the
  # reader is not scrolling past forty one-person countries to reach them.
  COMMON_COUNTRIES = %w[US CA GB AU].freeze

  # Stands in for a blank state in a URL, since an empty query value cannot be
  # told apart from one that was never sent. Sixty-odd US records have no state
  # on file.
  #
  # A word rather than a dash: a dash is itself a state somebody typed in, and
  # it also vanishes from a file name, which left the bucket exporting under
  # the name of its whole country.
  NO_STATE = "no-state"

  # The same for a blank country. A route segment cannot be empty, so without
  # this the "not on file" row on the index links nowhere.
  NO_COUNTRY = "no-country"

  # Columns every row needs. Email is added on the end only for readers
  # allowed to see it, so an address never reaches a page that would hide it.
  COLUMNS = [:id, :callsign, :status, :first_name, :preferred_name, :last_name,
             :city, :state, :zip, :country].freeze

  Row = Data.define(:id, :callsign, :status, :first_name, :last_name, :email,
                    :city, :state, :zip, :country, :signed_up, :rangered) do
    def name = [first_name, last_name].compact_blank.join(" ")

    # The buckets this row belongs to, for grouping and for URLs.
    def state_key = state.presence || NO_STATE
    def country_key = country.presence || NO_COUNTRY
  end

  # @param year [Integer] the event year the two year columns ask about
  # @param participation [String, nil] one of PARTICIPATION_VALUES, or nil for everyone
  # @param statuses [Array<String>] which OPTIONAL_STATUSES to put back in
  # @param include_email [Boolean] whether the reader may see email addresses
  # @return [Array<Row>] ordered by callsign
  def self.execute(year:, participation: nil, statuses: [], include_email: false)
    signed_up = signed_up_ids(year)
    rangered = rangered_ids(year)
    columns = include_email ? COLUMNS + [:email] : COLUMNS

    # Bound by name rather than by position: email is only asked for sometimes,
    # and reordering COLUMNS would otherwise slide every later value one field
    # along -- silently, since they are all strings. The name-to-position map is
    # the same for every row, so it is built once instead of per person.
    at = columns.each_with_index.to_h

    rows = people_scope(statuses).pluck(*columns).map do |values|
      Row.new(id: values[at[:id]], callsign: values[at[:callsign]].to_s,
              status: values[at[:status]],
              # A preferred name is the one the person goes by, so it wins
              # whenever they have set one.
              first_name: values[at[:preferred_name]].presence || values[at[:first_name]],
              last_name: values[at[:last_name]], email: (values[at[:email]] if at[:email]),
              city: values[at[:city]], state: values[at[:state]], zip: values[at[:zip]],
              country: values[at[:country]],
              signed_up: signed_up.include?(values[at[:id]]),
              rangered: rangered.include?(values[at[:id]]))
    end

    rows.select! { |row| participation_match?(row, participation) } if participation.present?
    # Callsign is how a reader looks someone up, and every page here has
    # already narrowed to one place, so grouping the rows by address again
    # would only scatter the names.
    rows.sort_by! { |row| row.callsign.downcase }
    rows
  end

  # Whether this country is broken down by state. Asked rather than read off
  # the constant, so the list stays in one place instead of spreading into the
  # controller and the templates.
  def self.states?(country) = STATE_COUNTRIES.include?(country)

  def self.common?(country) = COMMON_COUNTRIES.include?(country)

  # Everyone the report may show, before the year columns are considered.
  def self.people_scope(statuses)
    hidden = OPTIONAL_STATUSES - Array(statuses)
    hidden.empty? ? Person.all : Person.where.not(status: hidden)
  end
  private_class_method :people_scope

  def self.participation_match?(row, participation)
    case participation
    when SIGNED_UP then row.signed_up
    when RANGERED then row.rangered
    when BOTH then row.signed_up && row.rangered
    when EITHER then row.signed_up || row.rangered
    else true
    end
  end
  private_class_method :participation_match?

  # Everyone holding a sign-up for one of the year's shifts.
  #
  # Alpha shifts do not count. They are the walk-through a candidate attends
  # before joining, not a sign-up to ranger the event.
  #
  # @return [Set<Integer>]
  def self.signed_up_ids(year)
    PersonSlot.joins(:slot)
              .where(slot: { begins_year: year })
              .where.not(slot: { position_id: Position::ALPHA })
              .distinct
              .pluck(:person_id)
              .to_set
  end
  private_class_method :signed_up_ids

  # Everyone with at least one timesheet entry in the year.
  #
  # @return [Set<Integer>]
  def self.rangered_ids(year)
    Timesheet.for_year(year).distinct.pluck(:person_id).to_set
  end
  private_class_method :rangered_ids
end
