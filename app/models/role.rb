# frozen_string_literal: true

# app/models/role.rb
class Role < ApplicationRecord
  self.table_name = "role"

  # Renaming or removing a permission changes who can reach what, so every
  # change to this table is recorded.
  self.audit_model = true

  # Constants
  ADMIN = 1
  VIEW_PII = 2
  VIEW_EMAIL = 3
  # GRANT_POSITION = 4 - superseded by the team management interface
  EDIT_ACCESS_DOCS = 5
  EDIT_BMIDS = 6
  EDIT_SLOTS = 7
  EVENT_MANAGEMENT = 12
  INTAKE = 13
  MENTOR_INTERFACE = 101
  TRAINING_INTERFACE = 102
  VC_INTERFACE = 103
  # ART_TRAINER = 104 -- replaced by ART_TRAINER_BASE
  MEGAPHONE = 105
  TIMESHEET_MANAGEMENT = 106
  SURVEY_MANAGEMENT_TRAINING = 107
  EVENT_MANAGEMENT_ON_PLAYA = 108
  TRAINING_INTERFACE_SEASONAL = 109
  CERTIFICATION_MGMT = 110
  EDIT_ASSETS = 111
  EDIT_SWAG = 112
  CAN_FORCE_SHIFT = 113
  REGIONAL_MANAGEMENT = 114
  PAYROLL = 115
  VEHICLE_MANAGEMENT = 116
  SHIFT_MANAGEMENT_SELF = 117
  SALESFORCE_IMPORT = 118
  MESSAGE_MANAGEMENT = 119
  EDIT_CLOTHING = 120
  MEGAPHONE_TEAM_ONPLAYA = 121
  MEGAPHONE_EMERGENCY_ONPLAYA = 122
  ANNOUNCEMENT_MANAGEMENT = 123
  QUARTERMASTER_INTERFACE = 124
  SHIFT_MANAGEMENT = 125
  POD_MANAGEMENT = 126
  AWARD_MANAGEMENT = 127
  FULL_REPORT_ACCESS = 128
  EDIT_HANDLE_RESERVATIONS = 129
  EDIT_EMERGENCY_CONTACT = 130
  # Can edit existing vehicle records' identifying info (upstream Role.php:64).
  # No migration: the role table is shared with Laravel and already has row 131.
  VEHICLE_INFO_UPDATE = 131
  # Manage a team's resource document. Row 132 is already in the shared
  # database; this only gives it a name.
  TEAM_RESOURCE_MANAGEMENT = 132
  # Opens the Pogs pages: pog statistics and record administration. Unlike 131
  # and 132, no shared database ever held this row; migration
  # 20261013000001_add_pog_management_role adds it.
  POG_MANAGEMENT = 133
  # Opens the Mentoring pages beside MENTOR_INTERFACE, but only while the
  # EventManagementOnPlayaEnabled setting is on (RoleManager::SETTING_GATED_ROLES).
  # Migration 20261125000001_add_mentor_interface_event_role adds the row.
  MENTOR_INTERFACE_EVENT = 134
  TECH_NINJA = 1000

  # Deleting either of these takes admin access away from everyone who holds it,
  # including whoever is doing the deleting, and no page is left that could
  # grant it back. They may be renamed, never removed.
  PROTECTED = [ADMIN, TECH_NINJA].freeze

  POSITION_MASK = 0x0fff
  ROLE_BASE_MASK = 0x7f000000
  ART_TRAINER_BASE = 0x1000000
  SURVEY_MANAGEMENT_BASE = 0x2000000
  ART_GRADUATE_BASE = 0x30000000
  # Manage a training position's resource document. Composed per position like
  # the ART bases, but granted for In-Person Training too -- the rows already
  # exist, minted by the Laravel side this database is shared with.
  TRAINER_RESOURCE_MANAGEMENT_BASE = 0x40000000

  ART_ROLE_SUFFIXES = {
    ART_GRADUATE_BASE => "Graduate",
    ART_TRAINER_BASE => "Interface",
    SURVEY_MANAGEMENT_BASE => "Survey Mgmt",
    TRAINER_RESOURCE_MANAGEMENT_BASE => "Resrc Mgmt"
  }.freeze

  # Where a permission is filed on the forms that grant them, in the order the
  # groups are drawn. A new constant belongs in one of these lists; until it is
  # in one, grant_groups files its row under OTHER_GROUP instead of losing it.
  GROUPS = {
    "General Event Operations" => [
      EVENT_MANAGEMENT,
      EVENT_MANAGEMENT_ON_PLAYA,
      FULL_REPORT_ACCESS,
      POG_MANAGEMENT,
      TEAM_RESOURCE_MANAGEMENT
    ],
    "Communication" => [
      ANNOUNCEMENT_MANAGEMENT,
      MEGAPHONE,
      MEGAPHONE_TEAM_ONPLAYA,
      MEGAPHONE_EMERGENCY_ONPLAYA,
      MESSAGE_MANAGEMENT
    ],
    "In-Person Training" => [
      TRAINING_INTERFACE,
      TRAINING_INTERFACE_SEASONAL,
      SURVEY_MANAGEMENT_TRAINING,
      TRAINER_RESOURCE_MANAGEMENT_BASE | Position::TRAINING
    ],
    "Mentoring" => [MENTOR_INTERFACE, MENTOR_INTERFACE_EVENT],
    "Quartermaster Management" => [
      EDIT_SWAG,
      EDIT_CLOTHING,
      QUARTERMASTER_INTERFACE
    ],
    "People and Records" => [
      AWARD_MANAGEMENT,
      CERTIFICATION_MGMT,
      EDIT_EMERGENCY_CONTACT,
      INTAKE,
      REGIONAL_MANAGEMENT,
      VIEW_EMAIL,
      VIEW_PII
    ],
    "Shift / Timesheet Management" => [
      CAN_FORCE_SHIFT,
      EDIT_SLOTS,
      PAYROLL,
      POD_MANAGEMENT,
      SHIFT_MANAGEMENT,
      SHIFT_MANAGEMENT_SELF,
      TIMESHEET_MANAGEMENT
    ],
    "System Administration" => [
      ADMIN,
      TECH_NINJA
    ],
    "Gear and Vehicles" => [
      EDIT_ASSETS,
      VEHICLE_MANAGEMENT,
      VEHICLE_INFO_UPDATE
    ],
    "Volunteer Coordination / Ticketing" => [
      VC_INTERFACE,
      EDIT_ACCESS_DOCS,
      EDIT_BMIDS,
      EDIT_HANDLE_RESERVATIONS,
      SALESFORCE_IMPORT
    ]
  }.freeze
  OTHER_GROUP = "Other"

  # Two positions have permissions composed from them and are no ART: In-Person
  # Training and Alpha. Whatever is composed from either is filed with its
  # subject, under its own title, and never in a card of the position's own,
  # which for In-Person Training would be a second card titled "Training".
  POSITION_GROUPS = { Position::TRAINING => "Training", Position::ALPHA => "Mentoring" }.freeze

  # Associations
  has_many :person_roles, dependent: :delete_all
  has_many :team_roles, dependent: :delete_all
  has_many :position_roles, dependent: :delete_all

  has_many :teams, -> { order("team.title") }, through: :team_roles
  has_many :positions, -> { order("position.title") }, through: :position_roles

  # Validations
  validates :title, presence: true

  # Scopes
  scope :ordered_by_title, -> { order(:title) }
  scope :with_associations, -> { includes(:teams, :positions) }

  # Class Methods
  # The whole catalog, split in two: the permissions the code names directly,
  # and the ones composed from a training position. Composed permissions are
  # grouped under the position their low bits point at, and each group is
  # ordered the same way -- by the base the permission was built from.
  #
  # Returns [named_permissions, [[position_title, permissions], ...]].
  def self.catalog
    named, composed = ordered_by_title.with_associations.to_a
                                      .partition { |role| role.art_position_id.nil? }

    titles = Position.where(id: composed.map(&:art_position_id)).pluck(:id, :title).to_h

    [named, by_position(composed, titles)]
  end

  # Every permission, filed for a form that grants them:
  # [[[group_title, permissions], ...], [[art_title, permissions], ...]].
  #
  # The first list is the groups, each A to Z by title: what GROUPS names,
  # whatever is composed from a position in POSITION_GROUPS, and under
  # OTHER_GROUP the rest -- a named permission no group claims, or one composed
  # from a position that is gone or is no ART. The second holds the ARTs, each
  # with the permissions composed from it in base order.
  #
  # Together the two lists hold each permission exactly once, and the forms
  # rely on it: they post the whole list, so a permission they do not draw is
  # revoked by the next save.
  def self.grant_groups(roles = ordered_by_title)
    roles = roles.to_a
    by_id = roles.index_by(&:id)
    positions = Position.where(id: roles.filter_map(&:art_position_id)).index_by(&:id)

    filed = GROUPS.transform_values { |ids| by_id.values_at(*ids).compact }
    of_arts, rest = (roles - filed.values.flatten).partition do |role|
      position = positions[role.art_position_id]
      position && Training.training_position?(position) && Training.art?(position)
    end
    rest.each { |role| (filed[POSITION_GROUPS.fetch(role.art_position_id, OTHER_GROUP)] ||= []) << role }

    groups = filed.reject { |_title, permissions| permissions.empty? }
                  .map { |title, permissions| [title, permissions.sort_by { |role| role.title.downcase }] }

    [groups, by_position(of_arts, positions.transform_values(&:title))]
  end

  # Composed permissions under the position each was built from:
  # [[position_title, permissions], ...], A to Z by title. Each group runs in
  # the order of the bases its permissions were built from, so one type sits in
  # one place under every position.
  def self.by_position(composed, titles)
    composed.group_by(&:art_position_id)
            .map do |position_id, roles|
      [titles[position_id] || "Position ##{position_id}",
       roles.sort_by { |role| role.id & ROLE_BASE_MASK }]
    end
            .sort_by { |title, _| title.downcase }
  end

  private_class_method :by_position

  def self.find_for_query(query = {})
    scope = ordered_by_title
    scope = scope.with_associations if query[:include_associations]
    scope
  end

  def self.create_art_roles(position_id)
    position = Position.find(position_id)

    unless position.type == Position::TYPE_TRAINING
      raise ArgumentError, 'Position type is not "training"'
    end

    unless position.title.include?("Training")
      raise ArgumentError, 'Position title does not contain the word "Training"'
    end

    unless position.active?
      raise ArgumentError, "Position is not active"
    end

    title = position.title.gsub(" Training", "")
    added = []
    existing = []

    # All four or none: a run that dies part way through would otherwise leave a
    # half-built set behind and report failure for the ones it did create.
    transaction do
      ART_ROLE_SUFFIXES.each do |base, suffix|
        role_id = base | position_id
        existing_role = find_by(id: role_id)

        if existing_role
          existing << {
            id: role_id,
            title: existing_role.title
          }
          next
        end

        new_role = create!(
          id: role_id,
          title: "ART #{title} #{suffix}"
        )

        added << {
          id: new_role.id,
          title: new_role.title
        }
      end
    end

    [added, existing]
  end

  # Instance Methods

  # The training position a composed permission was built from, or nil for a
  # permission the code names directly.
  def art_position_id
    return nil if (id & ROLE_BASE_MASK) == 0

    # A base carrying no position bits names no position, so it belongs with the
    # permissions the code names directly rather than in a "Position #0" group.
    (id & ~ROLE_BASE_MASK).nonzero?
  end

  # May this permission be deleted? The two that confer admin access may not.
  def protected_role?
    PROTECTED.include?(id)
  end

  def art_position_title
    return nil if (id & ROLE_BASE_MASK) == 0
    Position.where(id: id & ~ROLE_BASE_MASK).pick(:title)
  end

  # What a composed permission is called inside its ART's own card: its type
  # alone, the card's title having named the ART. A base the code has no name
  # for keeps its whole title, so a box never reads as a number.
  def art_type_label
    ART_ROLE_SUFFIXES.fetch(id & ROLE_BASE_MASK, title)
  end

  def art_role_title
    base = id & ROLE_BASE_MASK
    return nil if base == 0

    prefixes = ART_ROLE_SUFFIXES[base]
    if prefixes.nil?
      "Unknown base #{base}"
    elsif prefixes.is_a?(Array)
      prefixes[1]
    else
      prefixes
    end
  end
end
