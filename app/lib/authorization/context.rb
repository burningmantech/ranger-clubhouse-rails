# frozen_string_literal: true

module Authorization
  # Answers a gate's questions via Current and the live controller, through typed accessors
  # only (no reaching into controller ivars). Keeps the gates unit-testable: a test passes a
  # plain stub responding to the same methods, with no HTTP.
  #
  # Note: +has_event_management?+ (EM + EMOP) and +event_management?+ (EM only) are distinct
  # on purpose — do not collapse them.
  class Context
    def initialize(controller)
      @controller = controller
    end

    def admin? = Current.admin?
    def has_role?(roles) = Current.has_role?(roles)
    def has_event_management? = Current.has_event_management?
    def event_management? = Current.event_management?
    def current_year? = @controller.send(:current_year_selected?)
  end
end
