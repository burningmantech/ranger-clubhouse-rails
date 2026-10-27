class ApplicationController < ActionController::Base
  include Authentication
  include ApplicationHelper
  include ActiveStorage::SetCurrent
  include AuthorizeHelper

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_current_user
  before_action :end_locked_session
  before_action :confine_past_prospective
  before_action :authorization_status_gatekeeper
  before_action :authorization_role_gatekeeper
  before_action :build_menu_items
  after_action :track_page_visit

  # The earliest params[:year] setup_year will honour. 1998 matches the year
  # selector's default floor (PageLayoutHelper#year_options); controllers whose
  # pages cover a different span declare their own.
  class_attribute :year_floor, default: 1998, instance_writer: false

  # Whether this page's year selector offers an all-years choice. It is the same
  # decision as the selector's include_all (PageLayoutHelper#year_options), so
  # the view reads this rather than spelling it a second time -- turning the
  # option on in only one of the two places used to leave the selector offering
  # "All" while setup_year quietly coerced it to the current year.
  class_attribute :allow_all_years, default: false, instance_writer: false

  helper_method :current_user
  helper_method :current_year
  helper_method :event_year
  helper_method :has_role?
  helper_method :has_event_management?
  helper_method :can_view_pii?
  helper_method :can_view_email?
  helper_method :can_view_emergency_contact?
  helper_method :can_view_emergency_contact_during_event?
  helper_method :is_admin?
  helper_method :is_team_manager?
  helper_method :year_floor
  helper_method :allow_all_years
  helper_method :google_analytics

  add_flash_types :success, :warning, :info, :error

  private

  def require_login
    redirect_to root_path unless current_user
  end

  def current_user
    Current.person
  end

  def current_year
    Current.year
  end

  def current_time
    Current.time
  end

  def event_year
    time = current_time
    # September or later refers to the upcoming event.
    (time.month >= 9) ? time.year + 1 : time.year
  end

  # The page's year scope: params[:year] is honoured only when it is a year
  # the page could have offered -- four digits, between the controller's
  # year_floor and the current year. Anything else ("abc".to_i is 0, and some
  # pages write year-keyed rows) falls back to the current year.
  #
  # Pages that set allow_all_years also honour the selector's all-years choice,
  # which arrives as PageLayoutHelper::ALL_YEARS and leaves @year nil.
  def setup_year
    requested = params[:year].to_s
    @year = if allow_all_years && requested == PageLayoutHelper::ALL_YEARS
              nil
            elsif requested.match?(/\A\d{4}\z/) && requested.to_i.between?(year_floor, current_year)
              requested.to_i
            else
              current_year
            end
    @is_current_year = (@year == current_year)
  end

  # The fields nested under one key: filter[...] or a form's scope. They are a
  # hash only when the page built the request. Anything else -- ?filter=x,
  # ?filter[]=x, a bare ?filter -- reads as no fields rather than raising
  # NoMethodError on #permit. Sliced as well as permitted: permit lets through
  # Rails' multiparameter keys (start_time(1i)), which a form object cannot take.
  def scoped_params(scope, *filters)
    values = params[scope]
    return {} unless values.is_a?(ActionController::Parameters)

    keys = filters.flat_map { |filter| filter.is_a?(Hash) ? filter.keys : filter }
    values.permit(*filters).slice(*keys)
  end

  def has_role?(roles)
    Current.has_role?(roles)
  end

  def has_event_management?
    Current&.has_event_management?
  end

  def can_view_pii?
    Current&.can_view_pii?
  end

  def can_view_email?
    Current&.can_view_email?
  end

  def can_view_emergency_contact?
    Current&.can_view_emergency_contact?
  end

  def can_view_emergency_contact_during_event?
    Current&.can_view_emergency_contact_during_event?
  end

  def authorization_role_gatekeeper
    allowed_roles = self.class.authorized_roles
    return if allowed_roles.nil? || Current.has_role?(allowed_roles)

    not_authorized_redirect(self.class.authorized_roles_message)
  end

  def authorization_status_gatekeeper
    return if status_authorization_allowed?

    not_authorized_redirect(self.class.authorized_statuses_message)
  end

  # A past prospective is no longer applying: the dashboard and their own
  # profile are all the Clubhouse opens to them. The controllers behind those
  # pages skip this, as does SessionsController so they can still sign out.
  def confine_past_prospective
    return unless Current.person&.past_prospective?

    not_authorized_redirect
  end

  def not_authorized_redirect(message = nil)
    flash[:error] = message || "You are not authorized to view the page."
    redirect_to me_root_path
  end

  def status_authorization_allowed?
    allowed_statuses = self.class.authorized_statuses
    excluded_statuses = self.class.authorized_statuses_except
    return true if allowed_statuses.nil? && excluded_statuses.nil?
    return false unless Current.person

    status = Current.person.status

    if allowed_statuses
      return allowed_statuses.include?(status)
    end

    !excluded_statuses.include?(status)
  end

  def set_current_user
    resume_session
    if Current.session&.person_id
      Current.person = Person.find(Current.session.person_id)
      if Current.person
        Current.person.update_columns(last_seen_at: Current.time)
        Current.roles_manager = RoleManager.retrieve(Current.person)
      end
    end

    Current.user_agent = request.user_agent
    Current.ip_address = request.remote_ip
  end

  def build_menu_items
    return true unless current_user
    @me_show_vehicles = VehicleEligibility.is_person_eligible?(current_user.id, Current.year)

    # Build menu context for hash-based menu abstraction
    @menu_context = {
      person: current_user,
      computed: {
        show_vehicles: @me_show_vehicles,
        is_development: Rails.env.development?,
        # Admins and Tech Ninjas reach every roster; everyone else only the
        # teams they manage. This runs on every request, so it answers from the
        # cached role set for an admin and with a single-table probe otherwise.
        manages_team_roster: Team.manageable_by?(current_user),
        # Wider than the key above on purpose: Bulk Membership History admits
        # any Clubhouse Team Manager, where Team.manageable_by? also demands
        # Event Management. Asked as one predicate because menu conditions are
        # ANDed together and "an Admin or a team manager" is a single question.
        records_team_history: is_admin? || is_team_manager?,
        # Team Resources: Event Management or Vehicle Info Update, then Admin, or
        # Team Resource Doc Mgmt and a team to manage. Answered from the cached
        # role set, plus one probe for a holder of both roles.
        manages_team_resources: Team.resource_manageable_by?(current_user),
        # Whether this Clubhouse offers passkeys at all. The pages behind the
        # menu item answer 404 where it does not.
        passkeys_enabled: Passkeys.enabled?(request)
      }
    }

    # Keep backward compatibility for any views still using @me_show_vehicles
    true
  end

  # Feed the mega menu's "Recently visited" list. Any successful GET to a
  # mega-menu page counts, however the person navigated there. Tracking is a
  # nicety — it must never turn a successful page into an error.
  def track_page_visit
    return unless current_user
    return unless request.get? && response.successful?
    # A frame load (a review line opening its pane) is not a visit to the page.
    return if turbo_frame_request?
    return unless tracked_page?

    PersonPageVisit.record(current_user.id, request.path)
  rescue => e
    Rails.logger.error("track_page_visit failed: #{e.class}: #{e.message}")
  end

  def google_analytics
    return "" unless Rails.env.production?

    gtag = Setting.get_value(Setting::GOOGLE_ANALYTICS_ID)
    return "" unless gtag.present?
    render partial: "google_analytics_code", locals: { gtag: }
  end

  # Whether this request is a mega-menu page. Controllers whose menu links are
  # built at request time (Training::BaseController) extend it.
  def tracked_page?
    MegaMenu.tracked_paths.include?(request.path)
  end

  def prevent_if_ghd_server(action)
    if Current.is_ghd_server?
      redirect_to me_root_path, error: "The action #{action} is not permitted in the Groundhog Day Server"
      return false
    end

    true
  end

  def is_admin?
    has_role? Role::ADMIN
  end

  # Memoized for the request: the menu asks this on every page load, and
  # Team.manageable_by? asks it again for anyone holding a roster role, so
  # without this an Event Manager paid the same probe twice per request. The
  # answer cannot come from the cached role set -- being a team manager is a
  # team_manager row, not a role -- so one probe per request is the floor.
  def is_team_manager?
    return @is_team_manager if defined?(@is_team_manager)

    @is_team_manager = TeamManager.manager_of_any?(Current.person_id)
  end
end
