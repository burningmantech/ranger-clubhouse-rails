# frozen_string_literal: true

class TeamsPositions::PositionGrantsController < ApplicationController
  include CsvExportConcern

  layout "teams_positions"

  # Upstream's PositionPolicy asks for Event Management alone -- Laravel's
  # hasRole has no Admin shortcut -- and every report ported into this app names
  # Admin alongside it. Read-only either way: nothing here writes.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required to view position grants."

  ALL = UiComponents::FilterBarHelper::ALL_FILTER

  # The pools the two "everyone should have this" flags are measured against,
  # taken from upstream's PeopleByPositionReport. A position carrying
  # all_rangers is compared against Rangers; new_user_eligible against every
  # account still live enough to be trained. Neither pool moves with the status
  # filter -- the flags define who is expected to hold the grant, so narrowing
  # them by the reader's filter would report a gap that does not exist.
  ALL_RANGERS_POOL = [
    Person::ACTIVE, Person::INACTIVE, Person::INACTIVE_EXTENSION, Person::SUSPENDED
  ].freeze

  NEW_USER_EXCLUDED = [
    Person::DECEASED, Person::DISMISSED, Person::RESIGNED,
    Person::UBERBONKED, Person::PAST_PROSPECTIVE
  ].freeze

  # Ember default-checked its ALLOWED_TO_WORK statuses and offered no checkbox
  # at all for the four locked-out ones. Same default here, as a single filter
  # value -- and unlike upstream, the locked-out statuses stay reachable, which
  # is how a non-Ranger holding an all-Rangers position gets found.
  RANGERING_STATUSES = (Person::LIVE_STATUSES - [Person::PAST_PROSPECTIVE]).freeze

  # The filter tokens live on TeamsPositions::PositionGrantsHelper, which owns
  # their labels, and are named in full inside methods rather than aliased to a
  # constant here -- a class-body constant reference resolves at load time, and
  # a controller/helper pair that names each other that way deadlocks both
  # autoloads.

  before_action :set_filter_params
  before_action :set_position, only: :show

  # Every position worth listing, with how many people hold it. The rosters
  # themselves are never loaded here -- 46,000 grants across 221 positions.
  def index
    positions = Position.select(:id, :title, :active, :type, :all_rangers, :new_user_eligible)
                        .order(:title).to_a

    # Only for the inclusion rule below, so it is deliberately unfiltered: which
    # positions the report lists should not shift as the reader narrows the
    # people, or the list they are scanning reshuffles under them.
    grant_counts = PersonPosition.group(:position_id).count

    @counts = holder_scope.group(:position_id).count
    # Under the on-site filter the two hashes are the same query, so it is only
    # asked once.
    @on_site_counts = @on_site_only ? @counts : holder_scope.where(person: { on_site: true })
                                                            .group(:position_id).count
    @unassigned_counts = unassigned_counts(positions)

    # Upstream's rule: a position is listed while it is active, or somebody
    # holds it, or somebody is missing it. An inactive position no one holds is
    # a record, not a roster -- Position Records is where those live.
    listed = positions.select do |position|
      position.active || grant_counts[position.id].to_i.positive? ||
        @unassigned_counts[position.id].to_i.positive?
    end

    @total_count = listed.size
    @positions = apply_filters(listed)

    # Every rollup describes the positions actually listed, not the whole
    # report -- they sit in one summary line directly above those rows, and a
    # line mixing filtered counts with report-wide ones would be read as
    # describing what is on screen.
    @grant_count = @positions.sum { |position| @counts[position.id].to_i }
    @unassigned_count = @positions.sum { |position| @unassigned_counts[position.id].to_i }
    @return_params = current_index_params
  end

  # One position's roster, plus the people missing it when the position is one
  # everybody is meant to hold.
  def show
    @members = roster
    @return_params = current_index_params

    respond_to do |format|
      # The unassigned pool runs to thousands of rows on a flagged position and
      # the export is built entirely from the roster, so only the page asks for
      # it.
      format.html do
        @total_members = member_total
        @unassigned = unassigned_people
      end
      format.csv do
        send_csv(csv_rows, filename: "#{@position.title.parameterize}-grants.csv")
      end
    end
  end

  private

  def set_filter_params
    helper = TeamsPositions::PositionGrantsHelper

    @filter_params = {
      type: UiComponents::FilterBarHelper.known_filter(params[:type], Position::TYPES),
      status: status_param,
      on_site: UiComponents::FilterBarHelper.known_filter(params[:on_site], [helper::ON_SITE_ONLY]),
      matching: UiComponents::FilterBarHelper.known_filter(params[:matching], [helper::MATCHING_ONLY])
    }

    # Both pages label their counts differently once the roster itself is
    # narrowed to on-site people, so it is derived with the filters rather than
    # in either action.
    @on_site_only = on_site?
  end

  # The one filter whose default is narrower than "all": an unasked-for status
  # lands on the Rangering set rather than on the sentinel, matching the boxes
  # Ember arrived with already checked.
  def status_param
    helper = TeamsPositions::PositionGrantsHelper
    allowed = [ALL, helper::STATUS_RANGERING] + Person::ALL_STATUSES

    allowed.include?(params[:status]) ? params[:status] : helper::STATUS_RANGERING
  end

  def set_position
    @position = Position.find(params[:position_id])
  end

  # The statuses the reader asked for, or nil when they asked for all of them.
  def status_filter
    case @filter_params[:status]
    when ALL then nil
    when TeamsPositions::PositionGrantsHelper::STATUS_RANGERING then RANGERING_STATUSES
    else [@filter_params[:status]]
    end
  end

  def on_site? = @filter_params[:on_site] == TeamsPositions::PositionGrantsHelper::ON_SITE_ONLY

  # Grants narrowed to the people the reader asked for. Joined through person so
  # both narrowings are one query rather than a subquery per position.
  def holder_scope
    scope = PersonPosition.joins(:person)
    scope = scope.where(person: { status: status_filter }) if status_filter
    scope = scope.where(person: { on_site: true }) if on_site?
    scope
  end

  # {position_id => count} for the flagged positions only -- about 25 of the
  # 221, so a COUNT each is cheaper than the reader's patience for a clever one.
  def unassigned_counts(positions)
    positions.each_with_object({}) do |position, counts|
      pool = unassigned_pool(position)
      next unless pool

      counts[position.id] = pool.where.not(id: grant_ids(position)).count
    end
  end

  # Who is expected to hold this position, or nil when no one in particular is.
  # new_user_eligible is tested first because upstream tests it first: a
  # position carrying both flags is measured against the wider pool.
  def unassigned_pool(position)
    scope = if position.new_user_eligible
              Person.where.not(status: NEW_USER_EXCLUDED)
            elsif position.all_rangers
              Person.where(status: ALL_RANGERS_POOL)
            end
    return nil unless scope

    on_site? ? scope.where(on_site: true) : scope
  end

  def grant_ids(position) = position.person_position.select(:person_id)

  # Type and the "hide the empty ones" toggle both run in Ruby: the 221
  # positions are already loaded, and the counts they test are the hashes above.
  # Finding one position by name is the scroll list's job, not a filter's -- it
  # jumps to a row without hiding the ones around it.
  def apply_filters(positions)
    type = @filter_params[:type]
    positions = positions.select { |position| position.type == type } unless type == ALL

    return positions unless @filter_params[:matching] == TeamsPositions::PositionGrantsHelper::MATCHING_ONLY

    positions.select { |position| @counts[position.id].to_i.positive? }
  end

  # Ordered by MySQL's own case-insensitive collation -- a Ruby sort_by here
  # would file every lowercase callsign after "Zulu". on_site rides along on top
  # of basic_info's three columns for the roster's badge.
  def roster
    scope = Person.basic_info.select(:on_site).where(id: grant_ids(@position))
    scope = scope.where(status: status_filter) if status_filter
    scope = scope.where(on_site: true) if on_site?
    scope.order(:callsign).to_a
  end

  # What the roster would hold before the status filter, so the page can say how
  # much of it is being shown. The on-site filter counts here because it narrows
  # the roster itself rather than the reader's view of it.
  def member_total
    scope = @position.person_position
    scope = scope.joins(:person).where(person: { on_site: true }) if on_site?
    scope.count
  end

  # Never narrowed by the status filter: the pool is what the position's flags
  # promise, so filtering it would hide the gap the report exists to find.
  def unassigned_people
    pool = unassigned_pool(@position)
    return [] unless pool

    pool.basic_info.select(:on_site).where.not(id: grant_ids(@position)).order(:callsign).to_a
  end

  # Matches what the page is showing rather than upstream's always-everybody
  # export: these filters live in the URL, so a reader who narrowed the roster
  # and then exported it asked for the narrowed one.
  def csv_rows
    [["Callsign", "Status"]] + @members.map { |person| [person.callsign, person.status] }
  end

  # The filters the reader was working in, carried onto the roster page so Back
  # returns them to the list they came from, and onto the export link so the CSV
  # matches the page. The status filter is always emitted: its default is
  # narrower than "all", so dropping it would silently re-apply it.
  def current_index_params
    UiComponents::FilterBarHelper.active_filters(@filter_params).with_defaults(status: ALL)
  end
end
