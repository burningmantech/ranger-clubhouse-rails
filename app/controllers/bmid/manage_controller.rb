# frozen_string_literal: true

# BMID (badge) management for a whole event year — the Ember vc/bmid port.
#
# A category filter picks the people whose badges need attention; the listing
# then hands back a badge for every one of them, synthesizing an unsaved
# in-prep row for anyone who does not have one yet (see BmidManagement).
#
# The secondary filters and the sort are deliberately server-side: upstream did
# both in the browser, so a narrowed roster could not be shared or reloaded and
# the CSV export could disagree with the table it was taken from. They run in
# Ruby over the loaded array rather than in SQL because the rows include those
# unsaved records and most of the filterable values are virtual attributes
# assembled by BmidRelationshipLoader.
class Bmid::ManageController < ApplicationController
  include CsvExportConcern
  # A validated @year: the bulk save writes, and an unparseable one would
  # otherwise save badges into year 0. See BmidYearConcern.
  include BmidYearConcern

  layout "bmid"

  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  MEALS_VALUES = Bmid::ManageHelper::MEALS_OPTIONS.map(&:last).freeze
  SHOWERS_VALUES = Bmid::ManageHelper::SHOWERS_OPTIONS.map(&:last).freeze
  QUALIFIED_VALUES = Bmid::ManageHelper::QUALIFIED_OPTIONS.map(&:last).freeze

  UNQUALIFIED = "unqualified"
  SHOWERS_YES = "yes"

  MEALS_ALL_EAT = "all_eat"
  MEALS_EVENT_WEEK = "event_week"
  MEALS_ANY_EAT = "any_eat"

  SORT_COLUMNS = %w[callsign status title1 title2 title3 mvr showers meals sap team notes].freeze
  DEFAULT_SORT = "callsign"
  ASCENDING = "asc"
  DESCENDING = "desc"

  # The upstream CSV_COLUMNS, in order. The page calls the document a SAP, but
  # the export keys are the ones downstream sheets are already built on, so the
  # tenth column keeps its upstream name.
  CSV_HEADER = %w[callsign title1 title2 title3 meals showers mvr team notes wap_status access_date].freeze

  # Combined teams ("Pre/Post", "Gate+Perimeter") are offered as their separate
  # tokens, upstream parity.
  TEAM_SEPARATOR = %r{[+/]}

  # Edit Mode is a value of the mode param rather than a separate page, so it
  # rides on every link the page draws and survives a reload -- upstream lost it
  # on any refresh.
  EDIT_MODE = "edit"

  # What one row of the bulk form may set. person_id and year identify the
  # badge and are never assignable: a synthesized row would otherwise be able to
  # write itself onto somebody else's year.
  ROW_FIELDS = %i[status title1 title2 title3 team notes admission_date].freeze

  # An emptied title or team means the badge does not carry one, not that it
  # carries an empty string.
  BLANK_TO_NIL_FIELDS = %i[title1 title2 title3 team].freeze

  NOTHING_SUBMITTED = "No changes were submitted, so nothing was saved."

  def index
    load_badges

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "bmids-#{@year}-#{category_filter}.csv") }
    end
  end

  # The bulk save. Only the rows the browser marked dirty arrive here (the
  # bulk-edit controller disables the rest), and each one is saved on its own so
  # a single bad value cannot hold back the others -- a partial apply.
  def update
    rows = submitted_rows
    # Worked out before anything is written: the filters are validated against
    # the values the category currently carries, and saving can change those.
    return_params = base_params.merge(active_secondary_filters)

    if rows.empty?
      redirect_to bmid_manage_path(return_params), info: NOTHING_SUBMITTED
      return
    end

    saved, @failed_badges = save_rows(rows)

    if @failed_badges.empty?
      if saved.zero?
        redirect_to bmid_manage_path(return_params), info: NOTHING_SUBMITTED
      else
        redirect_to bmid_manage_path(return_params),
                    success: "#{helpers.pluralize(saved, "badge")} updated."
      end
    else
      @saved_count = saved
      # The rows are the same objects the save just touched, so the reload shows
      # the saved values and leaves the failed rows holding what was submitted.
      load_badges
      flash.now[:error] = "#{helpers.pluralize(@failed_badges.size, "badge")} could not be saved."
      render :index, status: :unprocessable_entity
    end
  end

  private

  # Assign and save one row at a time. A row whose person is not in the category
  # is ignored rather than fatal: the page it came from may simply be stale.
  def save_rows(rows)
    badges = all_badges.index_by(&:person_id)
    saved = 0
    failed = []

    rows.each do |person_id, attributes|
      badge = badges[person_id]
      next if badge.nil?

      attributes = row_changes(badge, attributes)
      next if attributes.empty?

      badge.assign_attributes(attributes)

      if badge.save
        saved += 1
      else
        failed << badge
      end
    end

    [saved, failed]
  end

  # What this row would actually change, compared against the values the badge
  # was loaded with. Everything else is dropped.
  #
  # Only the rows an admin edited are supposed to travel, but that is the
  # browser's doing: bulk_edit_controller disables the pristine rows on submit.
  # Let that fail to connect -- JavaScript off, an earlier error, a missing
  # import -- and one click submits every row on screen. Saving them all would
  # create a badge for every synthesized person in the category, write an audit
  # row for each, and fire the SAP write-back once per person, rewriting access
  # dates on documents no one touched. So the server decides for itself.
  #
  # admission_date has to be compared before it is assigned: it is a pair of
  # virtual attributes rather than a column, so ActiveRecord's own change
  # tracking cannot see it.
  def row_changes(badge, attributes)
    # The grid renders the SAP control disabled on a badge with no pass, or one
    # whose pass has already gone off to be printed, so a date arriving for one
    # of those rows did not come from the page.
    attributes = attributes.except(:admission_date) if badge.sap_disabled?

    attributes.reject { |field, value| same_value?(value, badge.public_send(field)) }
  end

  # A textarea submits CRLF line endings whatever it was handed, so notes that
  # came straight back unedited would otherwise never compare equal.
  def same_value?(submitted, current)
    submitted.to_s.delete("\r") == current.to_s.delete("\r")
  end

  # The submitted rows, keyed by person id. Anything that is not a row of
  # attributes is dropped here rather than raising: this hash comes off the wire.
  def submitted_rows
    rows = params[:bmids]
    return {} unless rows.respond_to?(:each_pair)

    rows.each_pair.filter_map do |person_id, attributes|
      next unless attributes.respond_to?(:permit)

      values = row_attributes(attributes)
      next if values.empty?

      [person_id.to_i, values]
    end.to_h
  end

  def row_attributes(attributes)
    values = attributes.permit(*ROW_FIELDS).to_h.symbolize_keys

    BLANK_TO_NIL_FIELDS.each do |field|
      values[field] = values[field].presence if values.key?(field)
    end

    values
  end

  # One filtered, sorted read feeds both formats, so an export can never
  # disagree with the table it was taken from.
  def load_badges
    @edit_mode = edit_mode?
    # Only Edit Mode needs the SAP date choices, and building them reads a
    # handful of settings.
    @ticketing_info = TicketingInfo.new if @edit_mode
    @title_options = title_options
    @team_options = team_options
    @meals_offered = meals_offered?
    @showers_offered = showers_offered?
    @filter_params = filter_params
    @active_params = active_secondary_filters
    @base_params = base_params
    @index_params = @base_params.merge(@active_params)
    @sort_state = { sort: sort_column, dir: sort_direction, params: @index_params }

    @badges = sort_badges(filter_badges(all_badges))
    @provisions_by_person = provisions_by_person(@badges) if @edit_mode

    # "Showing X of Y": Y is the whole category, so it holds still while the
    # secondary filters narrow X.
    @total_count = all_badges.size
    @filtered_count = @badges.size

    @no_photo_count = @badges.count { |badge| !badge.has_approved_photo }
    @unqualified_count = @badges.count(&:not_qualified_to_print?)
    @unqualified_in_prep = @badges.any? do |badge|
      badge.not_qualified_to_print? && badge.status == Bmid::IN_PREP
    end
  end

  # The whole category, before the secondary filters. Memoized because the
  # title and team select options are drawn from it too.
  def all_badges
    @all_badges ||= begin
      badges = BmidManagement.retrieve_category_to_manage(category_filter, @year)
      preload_photos(badges)
      badges
    end
  end

  # The provisions each meals or showers cell offers to manage, keyed by person.
  # BmidRelationshipLoader reads the same rows to build the package the cells
  # display but keeps only the summary, so Edit Mode reads the records back here
  # rather than hanging another virtual attribute off Bmid. Table View never
  # asks -- it has no buttons to point anywhere.
  #
  # All of a person's usable provisions, not one per type: a person can hold two
  # of a type and the cell's label is the union of them, so the cell's button
  # opens the list rather than any one record. Ordered by id so that list reads
  # the same way every time, including after a save redraws the cell.
  def provisions_by_person(badges)
    Provision.retrieve_usable_for_person_ids(badges.map(&:person_id))
             .order(:id)
             .group_by(&:person_id)
  end

  # has_approved_photo reaches through the person to their current photo. The
  # roster runs to four figures, so the association is loaded once for everyone
  # rather than a query per row.
  def preload_photos(badges)
    people = badges.filter_map(&:person)
    return if people.empty?

    ActiveRecord::Associations::Preloader.new(records: people, associations: :photo).call
  end

  # --- params ---------------------------------------------------------------

  # The category always has a value: an unknown one means the default rather
  # than an empty page.
  def category_filter
    @category ||= begin
      filter = params[:filter].presence
      BmidManagement::FILTERS.include?(filter) ? filter : BmidManagement::DEFAULT_FILTER
    end
  end

  # An unknown value falls back to "all" rather than filtering everything out,
  # so a hand-edited URL cannot leave the page mysteriously empty or park a
  # label in the filter bar that the panel below it does not offer. Titles and
  # teams are data, not vocabulary, so they are checked against the options the
  # loaded category actually presents.
  def filter_params
    @filters ||= begin
      title = params[:title].presence
      team = params[:team].presence
      meals = params[:meals].presence
      showers = params[:showers].presence
      qualified = params[:qualified].presence

      {
        title: title_options.include?(title) ? title : ALL_FILTER,
        team: team_options.include?(team) ? team : ALL_FILTER,
        meals: (meals_offered? && MEALS_VALUES.include?(meals)) ? meals : ALL_FILTER,
        showers: (showers_offered? && SHOWERS_VALUES.include?(showers)) ? showers : ALL_FILTER,
        qualified: QUALIFIED_VALUES.include?(qualified) ? qualified : ALL_FILTER,
        q: params[:q].to_s.strip
      }
    end
  end

  # The secondary filters worth putting in a URL: one chip each. The text
  # search cannot use the "all" sentinel — someone may search for the word
  # "all" — so it is active whenever it is not blank.
  def active_secondary_filters
    active = UiComponents::FilterBarHelper.active_filters(filter_params.except(:q))
    query = filter_params[:q]
    active[:q] = query if query.present?
    active
  end

  # The params that identify the view itself. Unlike the secondary filters
  # these are never dropped: the year and the category always have a value, and
  # a chip or a heading link that lost them would silently change the subject.
  def base_params
    identity = { year: @year, filter: category_filter }
    identity[:sort] = sort_column unless sort_column == DEFAULT_SORT
    identity[:dir] = sort_direction unless sort_direction == ASCENDING
    # Which of the two layouts is on screen is part of the view's identity: a
    # chip or a heading link that dropped it would throw away the edits in
    # progress by quietly returning to Table View.
    identity[:mode] = EDIT_MODE if edit_mode?
    identity
  end

  # A bulk save is Edit Mode by definition -- it is the only layout with a form,
  # and the only one that can show a row its errors -- so a save always returns
  # there whether or not the request bothered to carry the param.
  def edit_mode?
    params[:mode] == EDIT_MODE || action_name == "update"
  end

  def sort_column
    @sort_column ||= begin
      column = params[:sort].presence
      SORT_COLUMNS.include?(column) ? column : DEFAULT_SORT
    end
  end

  def sort_direction
    @sort_direction ||= (params[:dir] == DESCENDING) ? DESCENDING : ASCENDING
  end

  # --- select options -------------------------------------------------------

  # The titles and teams the loaded category actually carries: the selects only
  # ever offer a value that can match something.
  def title_options
    @title_options ||= all_badges.flat_map { |badge| [badge.title1, badge.title2, badge.title3] }
                                 .compact_blank
                                 .uniq
                                 .sort
  end

  def team_options
    @team_options ||= all_badges.filter_map(&:team)
                                .flat_map { |team| team.split(TEAM_SEPARATOR) }
                                .map(&:strip)
                                .compact_blank
                                .uniq
                                .sort
  end

  # Whether the meals and showers selects have anything to narrow. A category
  # where no one eats has no meals filter that can match, and one where no one
  # showers has none that can exclude, so both selects go out disabled and the
  # filter itself is dropped -- the same rule the title and team selects follow,
  # which is what keeps a chip from surviving next to a select that can no
  # longer remove it.
  def meals_offered?
    return @meals_offered if defined?(@meals_offered)

    @meals_offered = all_badges.any? { |badge| !badge.no_meals? }
  end

  def showers_offered?
    return @showers_offered if defined?(@showers_offered)

    @showers_offered = all_badges.any? { |badge| badge.showers_granted.present? }
  end

  # --- filtering ------------------------------------------------------------

  def filter_badges(badges)
    title = filter_params[:title]
    team = filter_params[:team]
    meals = filter_params[:meals]
    showers = filter_params[:showers]
    qualified = filter_params[:qualified]
    query = filter_params[:q]

    badges = badges.select { |badge| titled?(badge, title) } unless title == ALL_FILTER
    badges = badges.select { |badge| badge.team.to_s.include?(team) } unless team == ALL_FILTER
    badges = badges.select { |badge| eats?(badge, meals) } unless meals == ALL_FILTER
    unless showers == ALL_FILTER
      washed = showers == SHOWERS_YES
      badges = badges.select { |badge| badge.showers_granted.present? == washed }
    end
    unless qualified == ALL_FILTER
      unqualified = qualified == UNQUALIFIED
      badges = badges.select { |badge| badge.not_qualified_to_print? == unqualified }
    end
    badges = badges.select { |badge| matches_text?(badge, query) } if query.present?

    keep_failed(badges)
  end

  # A row that could not be saved stays on screen whatever the secondary
  # filters say. It is holding the values that were just submitted rather than
  # the ones it was listed under, so re-running the filters over it can push it
  # out of the very report that names it -- and the admin's typing would go
  # with it, leaving no way to fix the row.
  def keep_failed(badges)
    failed = all_badges.select { |badge| badge.errors.any? }

    failed.empty? ? badges : badges | failed
  end

  # A title matches in any of the three slots.
  def titled?(badge, title)
    [badge.title1, badge.title2, badge.title3].include?(title)
  end

  def eats?(badge, filter)
    meals = badge.meals_granted

    case filter
    when MEALS_ALL_EAT then all_eat?(meals)
    when MEALS_EVENT_WEEK then event_week_only?(meals)
    # Upstream's "Any Eats" is all-eats OR event-week-only, not "any meal at
    # all". The name is kept so the page matches the roster people know.
    when MEALS_ANY_EAT then all_eat?(meals) || event_week_only?(meals)
    else true
    end
  end

  def all_eat?(meals)
    return false if meals.nil?

    meals.pre && meals.event && meals.post
  end

  def event_week_only?(meals)
    return false if meals.nil?

    !meals.pre && meals.event && !meals.post
  end

  # Case-insensitive substring, deliberately not a regular expression: the
  # search text comes straight from a URL and a user-supplied pattern is a
  # denial-of-service surface (PRD decision, 2026-07-28).
  def matches_text?(badge, query)
    needle = query.downcase

    [badge.person&.callsign, badge.title1, badge.title2, badge.title3, badge.team, badge.notes]
      .any? { |value| value.to_s.downcase.include?(needle) }
  end

  # --- sorting --------------------------------------------------------------

  def sort_badges(badges)
    descending = sort_direction == DESCENDING
    column = sort_column

    badges.sort do |a, b|
      order = compare_column(a, b, column, descending)
      # Callsign breaks every tie, and always ascending: a stable second key
      # keeps the roster from reshuffling under the reader.
      order.zero? ? sort_callsign(a) <=> sort_callsign(b) : order
    end
  end

  def compare_column(a, b, column, descending)
    case column
    when "callsign" then compare_text(sort_callsign(a), sort_callsign(b), descending)
    when "mvr" then compare_flag(a.org_vehicle_insurance, b.org_vehicle_insurance, descending)
    when "showers" then compare_flag(a.showers_granted, b.showers_granted, descending)
    when "sap" then compare_number(sap_sort_key(a), sap_sort_key(b), descending)
    else compare_text(sort_value(a, column), sort_value(b, column), descending)
    end
  end

  def sort_value(badge, column)
    case column
    when "status" then badge.status
    when "title1" then badge.title1
    when "title2" then badge.title2
    when "title3" then badge.title3
    when "meals" then helpers.bmid_meals_short_label(badge)
    when "team" then badge.team
    when "notes" then badge.notes
    end
  end

  def sort_callsign(badge)
    badge.person&.callsign.to_s.downcase
  end

  # Blanks sort last whichever way the column is pointing: an empty cell is not
  # the smallest value, it is the absence of one.
  def compare_text(a, b, descending)
    left = a.to_s.strip.downcase
    right = b.to_s.strip.downcase

    return 0 if left == right
    return 1 if left.empty?
    return -1 if right.empty?

    descending ? right <=> left : left <=> right
  end

  # The flagged rows lead when ascending: a Yes is what the column is for.
  def compare_flag(a, b, descending)
    compare_number(a ? 0 : 1, b ? 0 : 1, descending)
  end

  def compare_number(a, b, descending)
    order = a <=> b

    descending ? -order : order
  end

  # Upstream access_date_sortable: a badge whose SAP has no date yet is the one
  # that needs a decision, so it leads; then the people with no SAP at all,
  # then any-time access, then the real dates in calendar order.
  def sap_sort_key(badge)
    return 0 if badge.sap.nil?
    return 1 if badge.access_any_time
    return -1 if badge.access_date.blank?

    badge.access_date.to_time.to_i
  end

  # --- CSV ------------------------------------------------------------------

  def csv_rows
    rows = [CSV_HEADER]

    @badges.each do |badge|
      rows << [
        badge.person&.callsign,
        badge.title1,
        badge.title2,
        badge.title3,
        helpers.bmid_meals_short_label(badge),
        badge.showers_granted ? "Y" : "N",
        badge.org_vehicle_insurance ? "Y" : "N",
        badge.team,
        badge.notes,
        badge.sap ? badge.sap_status : "missing",
        badge.admission_date || "unspecified"
      ]
    end

    rows
  end
end
