# frozen_string_literal: true

# The roster grid behind Roster Management: everyone tied to a team, crossed
# with the team's positions, and what each grant is worth.
#
# Port of the API's App\Lib\Reports\TeamMembershipReport. The roster is the
# team's members plus anyone holding one of its Recommended or Optional
# positions. Someone whose only tie is a Public position is left out -- public
# positions are open to the whole organization, so counting them would list
# hundreds of people who have nothing to do with the team.
class TeamMembershipReport
  # Column order across the grid. The schema keeps every team position in one
  # of these three categories. Their headings are the view's business and live
  # on TeamsPositions::RosterManagementHelper.
  CATEGORY_ORDER = [
    Position::TEAM_CATEGORY_ALL_MEMBERS,
    Position::TEAM_CATEGORY_OPTIONAL,
    Position::TEAM_CATEGORY_PUBLIC
  ].freeze

  # The categories a revoke touches, and so the ones that put someone on the
  # roster at all -- the roster is defined as the people a revoke can reach.
  # Named once: spelling it positively here and negatively ("not public")
  # somewhere else would let a fourth category join one set and not the other.
  REVOCABLE_CATEGORIES = [
    Position::TEAM_CATEGORY_ALL_MEMBERS,
    Position::TEAM_CATEGORY_OPTIONAL
  ].freeze

  # What a position's last-activity year is measured from, and so what the cell
  # means. A training position records attendance rather than a timesheet, and
  # its trainers are graded on the sessions they taught.
  KIND_RANGERED = :rangered
  KIND_TRAINED = :trained
  KIND_TAUGHT = :taught

  # Position::TRAINERS maps each training position to the positions that teach
  # it, and one trainer teaches several of them -- hence a set rather than a
  # list.
  TRAINER_POSITION_IDS = Position::TRAINERS.values.flatten.to_set.freeze

  # The join alias each session query groups by, spelled out rather than
  # interpolated from the association name: a literal keeps the column list
  # greppable and keeps the security scan quiet about a string it cannot prove
  # is constant. TrainerStatus has two associations onto slot, so the alias is
  # load-bearing -- see session_years.
  SESSION_COLUMNS = {
    slot: ["slot.position_id", "slot.begins_year"].freeze,
    trainer_slot: ["trainer_slot.position_id", "trainer_slot.begins_year"].freeze
  }.freeze

  Column = Struct.new(:id, :title, :category, :kind, :granted_count, :never_count,
                      keyword_init: true)

  # One person's hold on one position. year is the last year they rangered,
  # trained at, or taught it -- nil when they never have.
  Grant = Struct.new(:joined_on, :year, keyword_init: true)

  # last_year is the most recent year across every position on this team,
  # computed once when the row is built: it is read three times per person and
  # nil -- the never-rangered case -- cannot be memoized lazily.
  Member = Struct.new(:id, :callsign, :status, :member, :grants, :last_year, keyword_init: true) do
    def member? = member

    def grant(position_id) = grants[position_id]

    # Upstream's rule, kept deliberately: holding none of the positions also
    # counts as never having rangered one, so the "never" filters surface the
    # people who hold nothing in the category as well as the idle grantees.
    def rangered_any?(position_ids) = position_ids.any? { |id| grants[id]&.year }
  end

  Result = Struct.new(:team, :columns, :people, keyword_init: true) do
    def position_ids_in(category)
      columns.select { |column| column.category == category }.map(&:id)
    end

    # The first column of each group, which the grid draws a divider before.
    # Columns arrive grouped, so the first of each category is its start.
    def group_start_ids = @group_start_ids ||= columns.uniq(&:category).map(&:id).to_set

    def member_count = people.count(&:member)

    def never_rangered_count = people.count { |person| person.last_year.nil? }

    def column(position_id) = columns.find { |candidate| candidate.id == position_id }

    # For the filter selects: only the statuses and years the roster actually
    # holds, so no choice can lead to a guaranteed-empty grid.
    def status_counts = @status_counts ||= people.group_by(&:status).transform_values(&:size)

    def activity_years = @activity_years ||= people.filter_map(&:last_year).uniq.sort.reverse
  end

  def self.execute(team) = new(team).execute

  # What a revoke strips: every Recommended and Optional position on the team.
  # Public positions are open to the whole organization and are left alone.
  def self.revocable_position_ids(team)
    Position.where(team_id: team.id, team_category: REVOCABLE_CATEGORIES).pluck(:id)
  end

  def initialize(team)
    @team = team
  end

  def execute
    @columns = build_columns
    member_ids = PersonTeam.where(team_id: @team.id).pluck(:person_id).to_set
    roster_ids = roster_person_ids(member_ids)

    # Bounded by the roster on purpose. A Public position can be held by most
    # of the organization -- Green Dot Training has 1,752 grants against a
    # 496-person roster -- and reading every one of them only to discard it
    # walks thousands of rows twice.
    @grants = PersonPosition.where(person_id: roster_ids, position_id: @columns.map(&:id))
                            .pluck(:person_id, :position_id)

    people = build_people(member_ids, roster_ids)
    tally(people)

    Result.new(team: @team, columns: @columns, people:)
  end

  private

  def build_columns
    positions = Position.where(team_id: @team.id).order(:title).to_a

    CATEGORY_ORDER.flat_map { |category|
      positions.select { |position| position.team_category == category }
               .map { |position|
                 Column.new(id: position.id, title: position.title, category:,
                            kind: kind_for(position))
               }
    }
  end

  # Only a training position is measured against sessions rather than
  # timesheets, and only the trainer side of one is measured against teaching.
  #
  # The title is consulted as well as Position::TRAINERS because a cadre can run
  # sessions with no trainee position to be mapped from -- Deep Desert Patrol
  # Trainer has no counterpart on its team, so no key in TRAINERS can ever name
  # it. Reading it as a trainee would ask trainee_status for a trainer's slots,
  # a query that cannot match, and label the cell "never trained at" when what
  # is meant is "never taught".
  def kind_for(position)
    return KIND_RANGERED unless position.type == Position::TYPE_TRAINING

    taught = TRAINER_POSITION_IDS.include?(position.id) || position.title.include?("Trainer")
    taught ? KIND_TAUGHT : KIND_TRAINED
  end

  def build_people(member_ids, roster_ids)
    grants = grants_by_person(activity_years(roster_ids), joined_dates(roster_ids))

    Person.where(id: roster_ids).order(:callsign).pluck(:id, :callsign, :status).map do |id, callsign, status|
      person_grants = grants.fetch(id, {})
      Member.new(id:, callsign:, status:, member: member_ids.include?(id), grants: person_grants,
                 last_year: person_grants.each_value.filter_map(&:year).max)
    end
  end

  # Members, plus the holders of any Recommended or Optional position. Only the
  # revocable columns are read here -- a Public grant never puts anyone on the
  # roster, so querying its holders would be work thrown away.
  def roster_person_ids(member_ids)
    revocable = @columns.select { |column| REVOCABLE_CATEGORIES.include?(column.category) }.map(&:id)

    member_ids | PersonPosition.where(position_id: revocable).pluck(:person_id)
  end

  def grants_by_person(years, joined)
    @grants.each_with_object({}) do |(person_id, position_id), by_person|
      key = [person_id, position_id]
      (by_person[person_id] ||= {})[position_id] =
        Grant.new(joined_on: joined[key], year: years[key])
    end
  end

  # One query per measure for the whole roster, keyed [person_id, position_id].
  # A position has exactly one kind, so the three results cannot collide.
  def activity_years(person_ids)
    # default = []: a kind with no columns reads back nil, and
    # `where(position_id: nil)` is `IS NULL` -- a real query matching whatever
    # rows have no position -- where an empty list is the `1=0` this wants.
    # Most teams have no trainer column, so that fired on nearly every roster.
    ids = @columns.group_by(&:kind).transform_values { |group| group.map(&:id) }
    ids.default = []

    rangered_years(person_ids, ids[KIND_RANGERED])
      .merge(session_years(TraineeStatus.passed.joins(:slot),
                           :slot, person_ids, ids[KIND_TRAINED]),
             session_years(TrainerStatus.where(status: TrainerStatus::STATUS_ATTENDED).joins(:trainer_slot),
                           :trainer_slot, person_ids, ids[KIND_TAUGHT]))
  end

  # Timesheets are stored as local wall-clock (default_timezone :local), so the
  # grouped maximum's year is the year the shift was in.
  def rangered_years(person_ids, position_ids)
    return {} if position_ids.empty?

    Timesheet.where(person_id: person_ids, position_id: position_ids)
             .group(:person_id, :position_id).maximum(:on_duty)
             .transform_values { |on_duty| on_duty&.year }
  end

  # Sessions carry a denormalized begins_year, indexed on
  # (begins_year, position_id) -- exactly this lookup.
  #
  # Inactive slots are excluded, as TraineeStatus.find_for_person_year and
  # TrainerStatus.taught? both do: a cancelled session is not a year trained,
  # and this grid must not credit one the Training pages disown.
  #
  # The API joins person_slot as well, to prove the person signed up for the
  # session they are graded on. A status row is written against that sign-up,
  # so the join only widens the query plan.
  #
  # begins_year defaults to 0 rather than NULL and 0 is truthy in Ruby, so an
  # unstamped slot would render as the year "0" and read as activity. It is
  # taken as no year at all instead.
  def session_years(scope, slot_key, person_ids, position_ids)
    return {} if position_ids.empty?

    group_column, year_column = SESSION_COLUMNS.fetch(slot_key)

    scope.where(person_id: person_ids)
         .where(slot_key => { position_id: position_ids, active: true })
         .group(:person_id, group_column)
         .maximum(year_column)
         .transform_values { |year| year if year.to_i.positive? }
  end

  # When the grant was made, from the still-open log row -- the earliest one,
  # because that is when the grant they hold today actually started. Most
  # historical grants predate the log and have none, and the grid says so by
  # showing no date at all.
  def joined_dates(person_ids)
    PersonPositionLog.where(person_id: person_ids, position_id: @columns.map(&:id), left_on: nil)
                     .group(:person_id, :position_id).minimum(:joined_on)
  end

  # Counts for the position summary, scoped to the roster this page draws --
  # never the whole organization, or a public position would claim more holders
  # than the grid has rows.
  def tally(people)
    @columns.each do |column|
      held = people.filter_map { |person| person.grants[column.id] }
      column.granted_count = held.size
      column.never_count = held.count { |grant| grant.year.nil? }
    end
  end
end
