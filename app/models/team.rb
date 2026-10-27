class Team < ApplicationRecord
  self.table_name = "team"
  self.inheritance_column = "none"

  # Team type constants
  TYPE_TEAM = "team"
  TYPE_CADRE = "cadre"
  TYPE_DELEGATION = "delegation"

  # Special team ID
  COUNCIL_CADRE = 6

  # Associations
  has_many :person_team, dependent: :destroy
  has_many :members, through: :person_team, source: :person
  has_many :position, dependent: :destroy
  has_many :team_roles, dependent: :delete_all

  # pseudo-select columns
  attribute :has_positions, :boolean
  attribute :is_manager, :boolean

  # The teams a message may be sent to as a group thread (MessagesConcern),
  # as PersonMessage#team_valid? accepts a recipient team: active, and a Cadre
  # or Delegation, never a plain team.
  scope :messageable, -> { where(active: true, type: [TYPE_CADRE, TYPE_DELEGATION]) }

  # The scope's rule for a team in hand: a thread's teams, which may have been
  # deactivated or retyped since it was sent.
  def messageable? = active && type.in?([TYPE_CADRE, TYPE_DELEGATION])

  # The active Cadres and Delegations a person is on now: the teams they may
  # write a message as (.scratch/team-messaging/PRD.md), and whose positions a
  # partial timesheet report shows them (PersonTeam.retrieve_cadre_membership_ids).
  scope :cadres_and_delegations_of, ->(person_id) { messageable.where(id: PersonTeam.where(person_id:).select(:team_id)) }

  # Roster management takes two things, and a person needs both.
  #
  # ROSTER_ACCESS_ROLES opens the page at all: managing a team is not by itself
  # enough, because the page hands out and takes away position grants for a
  # whole roster at once. The API draws the same line -- its revoke endpoints
  # sit behind PersonPolicy, which asks for Admin or Event Management.
  ROSTER_ACCESS_ROLES = [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TECH_NINJA].freeze

  # ROSTER_ALL_TEAMS_ROLES then decides WHICH rosters. Everyone else -- an
  # Event Management person included -- reaches only the teams they hold a
  # team_manager row for, so an EM who manages no team reaches none.
  ROSTER_ALL_TEAMS_ROLES = [Role::ADMIN, Role::TECH_NINJA].freeze

  # The teams whose roster the person may manage.
  #
  # A subquery rather than a join, so the caller can chain freely and no team
  # can appear twice. Unordered: the menu asks this on every request and only
  # wants to know whether anything comes back, so the caller orders when it is
  # actually listing teams.
  #
  # @param person [Person, nil]
  # @return [ActiveRecord::Relation]
  def self.manageable_by(person)
    return none unless person && person.has_role?(ROSTER_ACCESS_ROLES)
    return all if manages_every_team?(person)

    where(id: TeamManager.where(person_id: person.id).select(:team_id))
  end

  # Does the person reach any roster at all? The menu asks this on every
  # request, so it answers without touching the team table: the role check is
  # served from the cached role set, and for everyone who is not an Admin or
  # Tech Ninja the remaining question is a single-table probe.
  #
  # @param person [Person, nil]
  # @return [Boolean]
  def self.manageable_by?(person)
    return false unless person && person.has_role?(ROSTER_ACCESS_ROLES)

    manages_every_team?(person) || TeamManager.manager_of_any?(person.id)
  end

  def self.manages_every_team?(person) = person.has_role?(ROSTER_ALL_TEAMS_ROLES)

  # Team resource documents (Teams & Positions › Team Resources) also take two
  # things, and a different pair from rosters.
  #
  # RESOURCE_ACCESS_ROLES opens the page at all, of everyone, Admins included:
  # upstream's page sat in the Ember ops area, whose route wanted one of these
  # (web/app/routes/ops.js). Event Management On Playa counts while its setting
  # is on, when RoleManager promotes it to Event Management.
  RESOURCE_ACCESS_ROLES = [Role::EVENT_MANAGEMENT, Role::VEHICLE_INFO_UPDATE].freeze

  # Then, as upstream's DocumentController decides it: an Admin writes every
  # team's document (a Tech Ninja does not, unlike rosters), and anyone else
  # needs Team Resource Doc Mgmt and a team_manager row for the team.
  # Unordered, as manageable_by is.
  #
  # @param person [Person, nil]
  # @return [ActiveRecord::Relation]
  def self.resource_manageable_by(person)
    return none unless person&.has_role?(RESOURCE_ACCESS_ROLES)
    return all if resource_manages_every_team?(person)
    return none unless person.has_role?(Role::TEAM_RESOURCE_MANAGEMENT)

    where(id: TeamManager.where(person_id: person.id).select(:team_id))
  end

  # Does the person reach any team's document? The menu asks this on every
  # request: the roles come from the cached set, and only a role holder pays
  # the single-table probe.
  #
  # @param person [Person, nil]
  # @return [Boolean]
  def self.resource_manageable_by?(person)
    return false unless person&.has_role?(RESOURCE_ACCESS_ROLES)
    return true if resource_manages_every_team?(person)

    person.has_role?(Role::TEAM_RESOURCE_MANAGEMENT) && TeamManager.manager_of_any?(person.id)
  end

  def self.resource_manages_every_team?(person) = person.has_role?(Role::ADMIN)

  # The members a group message to the team reaches: those a send accepts.
  def messageable_members = members.messageable

  # The tag a team's first resource document is filed under (Laravel's
  # Team::buildResourceTag): the type is added unless the title already names
  # one, so "Green Dot Team" files as green-dot-team-info and "Council" as
  # council-cadre-info. Reads always go through the stored resource_tag, so this
  # only names documents this app mints -- which is why parameterize stands in
  # for Str::kebab. The two can disagree: parameterize turns punctuation into
  # hyphens or drops it ("Volunteer Coords. Cadre" -> volunteer-coords-cadre-info,
  # volunteer-coords.-cadre-info upstream), transliterates or drops letters
  # outside ASCII, and keeps a word that starts with a digit apart ("Team 2" ->
  # team-2-info, team2-info upstream).
  def build_resource_tag = "#{resource_name.parameterize}-info"

  # The description a newly created resource document carries.
  def build_resource_title = "#{resource_name} Document"

  private

  # The title, with the type added unless the title already names one --
  # upstream's hasTeamSuffix, a substring test rather than a word test, as there.
  def resource_name
    title.downcase.match?(/team|cadre|delegation/) ? title : "#{title} #{type.capitalize}"
  end
end
