# frozen_string_literal: true

# SearchBarPolicy gates access to the global search bar.
#
# The bar always exposes the "Person Manage" search mode, plus the modes the
# viewer's permissions unlock: "HQ Window" (HQ Window Interface enabled +
# Admin/Shift Management), "Timesheet" (Admin/Timesheet Management) and "Swag"
# (Admin/Quartermaster). The bar itself needs Event Management or Event
# Management On Playa -- the master gate that AutocompleteController also holds.
#
# Usage:
#   SearchBarPolicy.allowed?(Current.person)
#
class SearchBarPolicy
  # Mode identifiers exposed by the switcher.
  MODE_PERSON_MANAGE = "person_manage"
  MODE_HQ = "hq"
  MODE_TIMESHEET = "timesheet"
  MODE_SWAG = "swag"

  # Destination path template per mode: where a person result (and the
  # currently-viewed person, when the viewer switches modes on a /person/N or
  # /hq/N page) lands. ":id" is substituted with the person id -- server side by
  # AutocompleteController, client side by search_bar_controller.js.
  MODE_PATHS = {
    MODE_PERSON_MANAGE => "/person/:id",
    MODE_HQ => "/hq/:id",
    MODE_TIMESHEET => "/person/:id/timesheets",
    MODE_SWAG => "/person/:id/swag"
  }.freeze

  # Roles that enable the "HQ Window" search mode — the same gate as the HQ
  # Window pages themselves (HqConcern's authorize_role).
  HQ_MODE_ROLES = [Role::ADMIN, Role::SHIFT_MANAGEMENT].freeze

  # Roles that enable the "Timesheet" and "Swag" search modes -- the same gates
  # as the person timesheet / swag pages those modes navigate to.
  TIMESHEET_MODE_ROLES = [Role::ADMIN, Role::TIMESHEET_MANAGEMENT].freeze
  SWAG_MODE_ROLES = [Role::ADMIN, Role::QUARTERMASTER].freeze

  # On-duty position subtypes that default the bar into HQ mode. Position#subtype
  # yields the position type verbatim for non-mentoring positions (so an HQ shift
  # reports Position::TYPE_HQ) and "mentor" for non-mentee mentoring shifts.
  # (Ember equivalent: search-item-bar.js onduty_position.subtype 'hq'/'mentor'.)
  HQ_DEFAULT_SUBTYPES = [Position::TYPE_HQ, "mentor"].freeze

  # @param person [Person, nil] The current user
  # @return [Boolean] Whether the search bar should be shown
  #
  # The bar is only ever rendered for the logged-in user, whose roles are already
  # resolved into Current.roles_manager (see ApplicationController#set_current_user),
  # so we gate on Current to match the menu-visibility convention
  # (MenusBuilder uses Current.has_role? even with a person in context).
  def self.allowed?(person = nil)
    return false if person.nil?

    Current.has_event_management?
  end

  # Whether the "HQ Window" search mode is available to the viewer: the HQ
  # Window Interface setting must be on AND the viewer must hold Admin or
  # Shift Management — mirroring the gate on the HQ pages themselves
  # (HqConcern). Also consulted by AutocompleteController to keep a crafted
  # mode=hq request inert for anyone else.
  #
  # @return [Boolean]
  def self.hq_mode_available?
    Setting.get_value(Setting::HQ_WINDOW_INTERFACE_ENABLED) && Current.has_role?(HQ_MODE_ROLES)
  end

  # Ordered mode descriptors for the modal mode switcher.
  #
  # "person_manage" is always present. "hq" is shown — enabled — only while the
  # HQ Window Interface is enabled for the viewer (setting + Admin/Shift
  # Management); results in that mode navigate to the HQ Window shell (/hq/N).
  #
  # @return [Array<Hash>] ordered descriptors: { value:, label:, enabled: }
  def self.mode_options
    options = [{ value: MODE_PERSON_MANAGE, label: "Person Manage", enabled: true }]
    options << { value: MODE_HQ, label: "HQ Window", enabled: true } if hq_mode_available?
    if Current.has_role?(TIMESHEET_MODE_ROLES)
      options << { value: MODE_TIMESHEET, label: "Timesheet", enabled: true }
    end
    options << { value: MODE_SWAG, label: "Swag", enabled: true } if Current.has_role?(SWAG_MODE_ROLES)
    options
  end

  # Destination path template for the given mode, or nil when the mode is not one
  # the viewer may use (a crafted or stale value) -- callers then leave the
  # person-manage destination in place.
  #
  # @return [String, nil] e.g. "/person/:id/swag"
  def self.path_template_for(mode)
    MODE_PATHS[mode] if enabled_modes.include?(mode)
  end

  # Default-selected mode. Auto-selects "hq" when the viewer is on duty in an
  # HQ Window or mentor position (and the hq mode is available to them), so a
  # viewer staffing the HQ window lands in the right mode without switching.
  # The availability check runs first so the on-duty lookup (a Timesheet query
  # memoized on Current) is skipped whenever the hq mode is off the table.
  #
  # @return [String] MODE_HQ or MODE_PERSON_MANAGE
  def self.default_mode
    if hq_mode_available? && HQ_DEFAULT_SUBTYPES.include?(Current.onduty_position_subtype)
      MODE_HQ
    else
      MODE_PERSON_MANAGE
    end
  end

  # Mode values the bar will actually issue searches for. Used to validate a
  # persisted/legacy localStorage value before it can leak into a request.
  #
  # @return [Array<String>]
  def self.enabled_modes
    mode_options.select { |opt| opt[:enabled] }.map { |opt| opt[:value] }
  end
end
