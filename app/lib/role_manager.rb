# frozen_string_literal: true

class RoleManager
  include BasicCacheHelper

  CACHE_KEY_PREFIX = "person-roles-"

  # While its setting is on, a permission brings a second one with it:
  # source => [conferred, setting].
  CONFERRED_ROLES = {
    Role::EVENT_MANAGEMENT_ON_PLAYA => [Role::EVENT_MANAGEMENT, Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED],
    Role::TRAINER_SEASONAL => [Role::TRAINER, Setting::TRAINING_SEASONAL_ROLE_ENABLED]
  }.freeze

  # Permissions that grant nothing while their setting is off. Off-season a kept
  # Event Management On Playa would open every has_event_management? page to
  # its holder, without the NDA check that Event Management gets.
  SETTING_GATED_ROLES = {
    Role::EVENT_MANAGEMENT_ON_PLAYA => Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
    Role::MEGAPHONE_EMERGENCY_ONPLAYA => Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
    Role::MEGAPHONE_TEAM_ONPLAYA => Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED,
    Role::SHIFT_MANAGEMENT_SELF => Setting::SHIFT_MANAGEMENT_SELF_ENABLED
  }.freeze

  SETTING_GATES_LABELS = {
    Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED => "Event Management On Playa",
    Setting::SHIFT_MANAGEMENT_SELF_ENABLED => "Shift Management Self"
  }.freeze

  # Saving one of these invalidates every person's cached role set.
  ROLE_SETTINGS = (CONFERRED_ROLES.values.map(&:last) + SETTING_GATED_ROLES.values).uniq.freeze

  attr_accessor :roles, :directly_assign_roles, :roles_loaded, :granted_roles

  class << self
    def retrieve(person)
      role_manager = new
      role_manager.retrieve_roles(person)
      role_manager
    end

    # The year is part of the key because this year's training, sign-in and
    # NDA decide the set. Nothing purges on January 1, so a set cached in
    # December must not answer for the new year.
    def cache_key(person_id, year = Current.year)
      "#{CACHE_KEY_PREFIX}#{year}-#{person_id}"
    end

    def purge_person(person_id)
      Rails.cache.delete(cache_key(person_id))
    end

    # Flush every person's cached role set. This clears the whole cache rather
    # than matching CACHE_KEY_PREFIX: solid_cache (production) does not
    # implement delete_matched, so the pattern form raised NotImplementedError.
    # Same trade-off the position/team role writers already make.
    def purge_all
      Rails.cache.clear
    end
  end

  def has_role?(role_or_roles)
    (@roles & Array(role_or_roles)).any?
  end

  # Clubhouse 2's hasRawRole: the roles before an unsigned NDA took them all
  # away, so the NDA can still be offered to the person it locked out. A wiped
  # set is never cached, so a cached set is its own raw set.
  def has_raw_role?(role_or_roles)
    ((@raw_roles || @roles) & Array(role_or_roles)).any?
  end

  # An unsigned NDA took every role away. A wiped set is never cached, so a
  # cached set is never blocked.
  def nda_blocked? = !@raw_roles.nil?

  def has_directly_assigned_role?(role_or_roles)
    (@directly_assign_roles & Array(role_or_roles)).any?
  end

  # Does the person hold any permission built on the given base -- any ART
  # Survey Mgmt permission, say, whichever training it was composed for?
  def has_role_base?(base)
    @roles.any? { |role| (role & Role::ROLE_BASE_MASK) == base }
  end

  def admin?
    has_role?(Role::ADMIN)
  end

  def retrieve_roles(person)
    return if @roles_loaded

    year = Current.year
    cache_key = self.class.cache_key(person.id, year)
    # One read: a purge between an exist? and a read would leave the roles nil.
    if (cached = cache_read(cache_key))
      @roles, @directly_assign_roles, @granted_roles = cached
      @roles_loaded = true
      return
    end

    # Load directly assigned roles
    directly_assigned = person.person_role.pluck(:role_id)
    @directly_assign_roles = directly_assigned.dup

    on_duty_position_id = Timesheet.find_person_on_duty(person.id)&.position_id

    # Load roles from positions: only active ones, as in Clubhouse 2, and only once
    # their training and sign-in conditions are met. PersonPermissionPresenter
    # mirrors this loop; keep them in step.
    position_roles = []
    person.position.active.preload(:roles).each do |position|
      if position.require_training_for_roles
        # With no training position there is nothing to pass, so it confers nothing, as in Clubhouse 2.
        next unless position.training_position_id && Training.did_person_pass_for_year?(person, position.training_position_id, year)
      end
      next if position.require_signin_for_roles && position.id != on_duty_position_id

      position_roles += position.roles.pluck(:id)
    end

    # Load roles from teams
    team_roles = Person.where(id: person.id).joins(:person_team).joins("JOIN team_role ON person_team.team_id = team_role.team_id").pluck(:role_id)

    all_role_ids = (directly_assigned + position_roles + team_roles).uniq

    @granted_roles = all_role_ids
    @roles = all_role_ids

    roles_by_id = all_role_ids.index_with { |r| [r, true] }

    # Before the gate below: Event Management comes with On Playa only while On Playa is kept.
    CONFERRED_ROLES.each do |source, (conferred, setting)|
      roles_by_id[conferred] = true if roles_by_id[source] && Setting.get_value(setting)
    end
    have_manage = roles_by_id[Role::EVENT_MANAGEMENT]

    SETTING_GATED_ROLES.each { |role, setting| roles_by_id.delete(role) unless Setting.get_value(setting) }

    dont_cache = false
    if have_manage && !roles_by_id[Role::TECH_NINJA]
      # Kill the roles if the NDA is not signed, the NDA document exists and this is not a Ground Hog Day server
      # Document#purge_role_cache flushes this cache when that document comes or goes.
      if !Current.is_ghd_server? && !PersonEvent.is_column_set?(person.id, "signed_nda") && Document.have_tag?(Document::DEPT_NDA_TAG)
        # Don 't allow the person to do anything until the NDA is signed.
        @raw_roles = roles_by_id.keys
        roles_by_id = {}
        @directly_assign_roles = []
        dont_cache = true
      end
    end

    @roles = roles_by_id.keys
    unless dont_cache
      cache_write(cache_key, [@roles, @directly_assign_roles, @granted_roles])
    end

    @roles_loaded = true
  end
end
