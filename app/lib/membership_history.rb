# frozen_string_literal: true

# A person's team memberships and position grants over time: one Spell per
# recorded start and end, read from person_team_log and person_position_log
# against today's roster (Person › Teams & Positions History).
#
# The roster (person_team, person_position) says what is held today; the logs
# only date it, and the two disagree often (docs/FEATURES.md keeps the counts):
# a log row can stay open after the roster row is gone, a current holding can
# have no row or only closed rows, and a pre-tracking grant revoked since left
# no row at all. Where a held team or position has several open rows, the
# latest is read as today's spell and the earlier ones as spells that ended on
# an unrecorded date; the roster reports (Reports::TeamMembershipReport,
# Training::MenteesReport) summarize the same rows as "since the earliest".
class MembershipHistory
  # The day both logs shipped (Clubhouse 2's Teams deployment), when every
  # membership of the day was written into the team log with this date. A row
  # dated that day says "already held by then", nothing more; an earlier date
  # is a real one, recorded through Bulk Membership History.
  # AwardManagement::TEAM_LOG_START is its year.
  TRACKING_BEGAN = Date.new(2022, 11, 29)

  # began_on nil: the start was never recorded. ended_on nil with current
  # false: it ended, and nothing says when.
  Spell = Data.define(:title, :team_title, :active, :began_on, :ended_on, :current) do
    def before_tracking? = began_on == TRACKING_BEGAN

    def active? = active
  end

  Row = Data.define(:id, :began, :ended)
  Label = Data.define(:title, :team_title, :active)

  attr_reader :teams, :positions

  def initialize(person)
    team_rows = rows(PersonTeamLog.where(person_id: person.id).pluck(:team_id, :joined_on, :left_on))
    team_ids = person.person_team.pluck(:team_id)
    @teams = pair(team_rows, team_ids, team_labels(team_rows.map(&:id) | team_ids))

    position_rows = rows(PersonPositionLog.where(person_id: person.id).pluck(:position_id, :joined_on, :left_on))
    position_ids = person.person_position.pluck(:position_id)
    @positions = pair(position_rows, position_ids, position_labels(position_rows.map(&:id) | position_ids))
  end

  private

  def rows(plucked)
    plucked.map { |id, began, ended| Row.new(id:, began:, ended:) }
  end

  def team_labels(ids)
    labels = Team.where(id: ids).pluck(:id, :title, :active)
                 .to_h { |id, title, active| [id, Label.new(title:, team_title: nil, active:)] }
    with_placeholder(labels, "Team")
  end

  def position_labels(ids)
    labels = Position.left_joins(:team).where(id: ids).pluck(:id, :title, :active, "team.title")
                     .to_h { |id, title, active, team_title| [id, Label.new(title:, team_title:, active:)] }
    with_placeholder(labels, "Position")
  end

  # A deleted position keeps its log rows as the audit trail
  # (PositionManagement.destroy), so an id with no row prints the placeholder
  # Position.retrieve_title prints.
  def with_placeholder(labels, noun)
    labels.default_proc = ->(_hash, id) { Label.new(title: "#{noun} ##{id}", team_title: nil, active: true) }
    labels
  end

  def pair(rows, held, labels)
    by_id = rows.group_by(&:id)

    (by_id.keys | held).flat_map { |id| spells_for(labels[id], by_id.fetch(id, []), held.include?(id)) }
                       .sort_by { |spell| [spell.title.downcase, spell.began_on ? 0 : 1, spell.began_on || TRACKING_BEGAN] }
  end

  def spells_for(label, rows, held)
    rows = rows.uniq { |row| [row.began, row.ended] } # the same dates twice say nothing twice
    closed, open = rows.partition(&:ended)
    latest = open.max_by(&:began) if held

    spells = closed.map { |row| spell(label, row.began, row.ended) }
    spells += (open - [latest]).map { |row| spell(label, row.began) } # ended, and nothing says when
    spells << spell(label, latest ? latest.began : (TRACKING_BEGAN if rows.empty?), current: true) if held
    spells
  end

  def spell(label, began, ended = nil, current: false)
    Spell.new(title: label.title, team_title: label.team_title, active: label.active,
              began_on: began, ended_on: ended, current:)
  end
end
