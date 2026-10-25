# frozen_string_literal: true

module PersonConcern
  extend ActiveSupport::Concern

  # The roles admitted to /person/:id. Named rather than inlined so that pages
  # which LINK to a person page can ask the same question this gate asks --
  # see LinkHelper#can_view_person_page?. Reports reach a wider audience than
  # the person pages they point at, and a link that bounces the reader is worse
  # than no link.
  #
  # Shift Management is admitted so HQ Window workers can open the person
  # pages the HQ sidebar links to. Note this grants page access across every
  # PersonConcern controller, not only the HQ-linked ones; the stricter
  # per-action gates (authorize_ability, and PersonTimesheetConcern's own
  # authorize_role) still apply on top. Person › Schedule / Available Sign-Ups add
  # no write gate, so Shift Management adds and removes sign-ups there too: kept on
  # purpose (ruled 2026-10-10), though Clubhouse 2's SchedulePolicy leaves it out.
  VIEW_ROLES = [
    Role::ADMIN,
    Role::EVENT_MANAGEMENT,
    Role::EVENT_MANAGEMENT_ON_PLAYA,
    Role::MENTOR,
    Role::TRAINER,
    Role::VC,
    Role::SHIFT_MANAGEMENT
  ].freeze

  included do
    before_action :set_person
    authorize_role VIEW_ROLES
    helper_method :can_manage_callsign_or_status?
    helper_method :can_see_contact_info?
    helper_method :can_edit_permissions?
    helper_method :can_manage_banners?
  end

  private

  def set_person
    id = params[:person_id] || params[:id]
    if id.present?
      unless (@person = Person.find_by(id: id))
        redirect_to me_root_path, error: "Person not found"
        return false
      end
    else
      raise ActionController::ExpectedParameterMissing, "Missing person_id or id parameter."
    end

    true
  end

  def can_manage_callsign_or_status?
    has_role? [Role::ADMIN, Role::VC, Role::MENTOR]
  end

  def can_see_contact_info?
    can_view_pii? || can_view_emergency_contact? || can_view_emergency_contact_during_event?
  end

  def can_view_emergency_contact_during_event?
    Current&.can_view_emergency_contact_during_event?
  end

  def can_edit_permissions?
    Person::PermissionsController.role_gates.fetch(:edit_permissions).permits?(authorization_context)
  end

  def can_manage_banners?
    has_role? [Role::ADMIN, Role::VC]
  end

  # Answers the YearGate/RoleGate authorization context for the person pages that
  # use +require_current_year_for+ (@year is set by each controller's setup_year).
  def current_year_selected?
    @year == Current.year
  end

  # Normalize a controller's year-source list into the descending, de-duplicated
  # set (always including the current year) that the hero panel year selector wants.
  def years_with_current(years)
    (years + [Current.year]).uniq.sort.reverse
  end
end
