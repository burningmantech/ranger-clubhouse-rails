# frozen_string_literal: true

# Team record administration: the save and destroy rules the Ember admin/teams
# page got from the Laravel Team model's boot() hooks and validation rules.
#
# They live here rather than on Team because the model is frozen for the
# translation. Each method notes what should move onto the model when it
# reopens.
module TeamManagement
  # The allowed types and how they are named on screen. One hash so a type the
  # validator accepts cannot go unlabelled, or a labelled one be rejected on
  # save -- the two used to be separate constants in separate files, held level
  # only by a test. TeamRecordsHelper#team_record_type_label reads this for the
  # views.
  TYPE_LABELS = {
    Team::TYPE_TEAM => "Team",
    Team::TYPE_CADRE => "Cadre",
    Team::TYPE_DELEGATION => "Delegation"
  }.freeze
  TYPES = TYPE_LABELS.keys.freeze
  # Types that are listed in the Cadre & Delegation Directory whatever
  # include_in_directory says. See directory_listed?.
  DIRECTORY_TYPES = [Team::TYPE_CADRE, Team::TYPE_DELEGATION].freeze
  TITLE_MAX = 100
  # The column limits. Upstream validates neither, and its own
  # buildResourceTag() emits tags past 30 characters, so a shorter cap here
  # would reject rows Laravel legitimately writes.
  EMAIL_MAX = 255
  RESOURCE_TAG_MAX = 255
  DELETE_REASON = "Team deletion"
  SAVE_REASON = "Team record edit"

  # Booleans the schema declares NOT NULL. A blank checkbox value casts to nil
  # and would reach MariaDB as a NotNullViolation 500.
  BOOLEAN_COLUMNS = %i[active mvr_eligible pvr_eligible awards_eligible include_in_directory].freeze

  # Roles too dangerous to hand a whole roster without already holding them.
  # PersonTeam.add_person guards the mirror operation with the same pair.
  GUARDED_ROLE_IDS = [Role::ADMIN, Role::TECH_NINJA].freeze

  # Columns upstream stores as NULL rather than "" (its NullIfEmptyAttribute
  # on email() and description()). The Laravel writers still share these
  # tables, so a blank one written here would make `where(email: nil)`
  # disagree depending on who saved the row.
  NULL_IF_EMPTY = %i[email description].freeze

  module_function

  # Is the team listed in the Cadre & Delegation Directory? Cadres and
  # delegations always are; any other type only when explicitly flagged.
  # DirectoryReport and the admin grid's Directory chip must agree, so both
  # ask here. Move onto Team as a predicate + scope when it reopens.
  def directory_listed?(team)
    DIRECTORY_TYPES.include?(team.type) || team.include_in_directory
  end

  # Validate and persist, syncing role grants when the actor may change them.
  # Errors land on the team so the form redisplays them; returns false instead
  # of raising, like ActiveRecord#save.
  #
  # Move to Team when it reopens: the validations, and the awards zeroing as a
  # before_save.
  def save(team, role_ids: nil, is_tech_ninja: false)
    NULL_IF_EMPTY.each { |column| team[column] = team[column].presence }

    desired_roles = IdList.parse(role_ids) if is_tech_ninja && role_ids
    return false unless valid?(team, desired_roles)

    # Upstream's saving() hook. The two automation columns are meaningless
    # without awards eligibility, and leaving them set would let the automation
    # fire against a team that is no longer eligible.
    unless team.awards_eligible
      team.awards_auto_grant = false
      team.awards_grants_service_year = false
    end

    creating = team.new_record?
    changes = team.changes.except("created_at", "updated_at")

    ApplicationRecord.transaction do
      team.save!
      # desired_roles is nil when the form never offered the field, and [] when
      # a Tech Ninja cleared every box -- only the latter should revoke.
      Membership.update_team_roles(team.id, desired_roles, SAVE_REASON) if desired_roles
      # Upstream's Team model is auditModel = true, so the Laravel app has been
      # writing team-create / team-update rows to this shared table all along.
      # Without this the trail simply stops at the port.
      ActionLog.record(Current.person, creating ? "team-create" : "team-update", SAVE_REASON,
                       changes.merge("id" => team.id)) if creating || changes.any?
    end

    # Role grants feed RoleManager's per-person cache; TeamRole.add/remove
    # already clear for those. Nothing else here is cached, so a full-store
    # flush on every rename would discard every user's roles and settings.
    true
  end

  # Release the team's positions and remove its membership records, then delete
  # it. Upstream NULLs position.team_id and audit-deletes the rest; one model
  # association makes a bare team.destroy the wrong way to get there: Team
  # has_many :position, dependent: :destroy would destroy the positions -- and
  # their slots and sign-ups -- instead of releasing them. A model bug: when
  # Team reopens, make positions :nullify, and this method can shrink to the
  # award/log cleanup plus the audit entry.
  def destroy(team)
    team_id = team.id
    title = team.title

    ApplicationRecord.transaction do
      Position.where(team_id:).update_all(team_id: nil)
      # Destroyed one at a time, not delete_all: PersonAward's after_destroy
      # recomputes the person's years_of_awards, and those years feed their
      # years of service. A bulk delete leaves both counting awards that no
      # longer exist. Upstream fires the same per-row hook via deleteWithReason.
      PersonAward.where(team_id:).find_each(&:destroy!)
      PersonTeamLog.where(team_id:).delete_all
      TeamManager.where(team_id:).delete_all
      # Revoked through Membership rather than deleted in bulk, so each lost
      # role grant leaves its own audit entry -- the same path save takes.
      Membership.update_team_roles(team_id, [], DELETE_REASON)
      # Its memberships go with it (has_many :person_team, dependent: :destroy),
      # one at a time so PersonTeam's after_destroy can rebuild each member's
      # awards -- a no-op while AwardManagement.rebuild_for_person_id is
      # commented out. Messages keep their team ids (PersonMessage#sender_name).
      team.destroy!
      ActionLog.record(Current.person, "team-delete", DELETE_REASON, { team_id:, title: })
    end

    # The team's members lose whatever roles it granted, and their cached role
    # sets are keyed per person. Membership.update_team_roles above already
    # cleared for any revoked grant; this covers a team that granted none.
    Rails.cache.clear
    true
  end

  # Team carries no validations of its own, so everything the columns require
  # is checked here -- an over-long string or a nil NOT NULL boolean would
  # otherwise reach MariaDB and raise, turning a correctable form mistake into
  # an error page with the reader's work lost.
  #
  # desired_roles is nil unless the actor may change role grants.
  def valid?(team, desired_roles = nil)
    team.errors.clear

    if team.title.blank?
      team.errors.add(:title, "Title can't be blank.")
    elsif team.title.length > TITLE_MAX
      team.errors.add(:title, "The title must be #{TITLE_MAX} characters or fewer.")
    end

    team.errors.add(:type, "The type must be Team, Cadre, or Delegation.") unless TYPES.include?(team.type)

    { email: EMAIL_MAX, resource_tag: RESOURCE_TAG_MAX }.each do |column, limit|
      value = team[column]
      team.errors.add(column, "must be #{limit} characters or fewer") if value.present? && value.length > limit
    end

    BOOLEAN_COLUMNS.each do |column|
      team.errors.add(column, "must be true or false") if team[column].nil?
    end

    validate_roles(team, desired_roles) if desired_roles

    team.errors.empty?
  end

  # team_role carries no foreign key, so an id naming no role would only fail
  # deep inside TeamRole.add -- rolling back the reader's other edits and
  # landing them on a bare error page. Granting a role is also how a team hands
  # every member that role, so the two roles that could escalate a whole roster
  # need the actor to already hold them, matching PersonTeam.add_person.
  def validate_roles(team, desired_roles)
    unknown = desired_roles - Role.where(id: desired_roles).pluck(:id)
    team.errors.add(:role_ids, "The role grants include #{unknown.sort.join(", ")}, which name no role.") if unknown.any?

    granted = desired_roles - TeamRole.find_all_for_team(team.id).pluck(:role_id)
    (granted & GUARDED_ROLE_IDS).each do |role_id|
      next if Current.person&.has_role?(role_id)

      title = Role.find_by(id: role_id)&.title || "Role ##{role_id}"
      team.errors.add(:role_ids, "You cannot grant #{title}: you do not hold it yourself.")
    end
  end
end
