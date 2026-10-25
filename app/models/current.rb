class Current < ActiveSupport::CurrentAttributes
  attr_accessor :session, :person, :roles_manager, :groundhog_day_time, :ip_address, :user_agent

  resets do
    @onduty_entry = nil
    @onduty_entry_person_id = nil
  end

  def initialize
    super
    # A date no one can read leaves the time unset, which is what the server
    # falls back to anyway. Letting it raise here would take down every page.
    ghd = ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"]
    @groundhog_day_time = begin
      ghd.present? ? Time.zone.parse(ghd) : nil
    rescue ArgumentError
      nil
    end
    @deployment = ENV["RANGER_CLUBHOUSE_ENVIRONMENT"] || "Development"
  end

  def is_production?
    @deployment == "Production"
  end

  def is_staging?
    @deployment == "Staging"
  end

  def is_development?
    @deployment == "Development"
  end

  def is_training?
    @deployment == "Training"
  end

  # The variable being set at all is what marks the training server, whether or
  # not the time in it can be read. A server that says it is one is treated as
  # one: mail is held back there, and so are the actions it is not allowed.
  def is_ghd_server?
    @groundhog_day_time.present? || ENV["RANGER_CLUBHOUSE_GROUNDHOG_DAY_TIME"].present?
  end

  def has_role?(role)
    roles_manager ? roles_manager.has_role?(role) : false
  end

  def has_role_base?(base)
    roles_manager ? roles_manager.has_role_base?(base) : false
  end

  def has_raw_role?(role)
    roles_manager ? roles_manager.has_raw_role?(role) : false
  end

  def has_event_management?
    has_role? [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA]
  end

  def can_view_pii?
    has_role? [Role::ADMIN, Role::MENTOR, Role::VC, Role::VIEW_PII]
  end

  def can_view_email?
    has_role? [Role::ADMIN, Role::MENTOR, Role::VC, Role::VIEW_EMAIL]
  end

  def can_view_emergency_contact?
    return true if has_role? [Role::ADMIN, Role::VC]
    Setting.get_value(Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED) && has_role?([Role::EVENT_MANAGEMENT_ON_PLAYA, Role::EVENT_MANAGEMENT])
  end

  def can_view_emergency_contact_during_event?
    has_role? [Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA]
  end

  def person_id
    person&.id
  end

  # The viewer's still-open timesheet entry for the current year, with the
  # position preloaded (Timesheet.find_person_on_duty), or nil when signed out
  # or not on duty. Memoized for the life of the request-scoped instance and
  # keyed to the person so a person switch never serves a stale entry.
  # Powers the HQ Window "you are not on duty" warning, the on-duty-mentor
  # check, and the Cmd-K default search mode.
  # (Ember equivalent: the session service's updateOnDuty / onduty_position.)
  def onduty_entry
    return nil if person.nil?

    if @onduty_entry_person_id != person.id
      @onduty_entry_person_id = person.id
      @onduty_entry = Timesheet.find_person_on_duty(person.id)
    end

    @onduty_entry
  end

  # Subtype of the viewer's on-duty position ("mentor", "mentee", or the
  # position type such as Position::TYPE_HQ), or nil when not on duty.
  def onduty_position_subtype
    onduty_entry&.position&.subtype
  end

  def admin?
    has_role? Role::ADMIN
  end

  def event_management?
    has_role? Role::EVENT_MANAGEMENT
  end

  def event_management_on_playa?
    has_role? Role::EVENT_MANAGEMENT_ON_PLAYA
  end

  def time
    @groundhog_day_time || Time.zone.now
  end

  def year
    time.year
  end

  def today
    @groundhog_day_time ? @groundhog_day_time.to_date : Time.zone.today
  end
end
