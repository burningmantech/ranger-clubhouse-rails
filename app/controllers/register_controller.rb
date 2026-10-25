# frozen_string_literal: true

# Opening an auditor account, for someone who wants to sit in on a Ranger
# training and does not have a Clubhouse account yet.
#
# The page is the one part of the Clubhouse a stranger can reach, so it starts
# by asking why they are here. People who want to become a Black Rock Ranger
# are turned around to the Volunteer Form before they are ever shown the
# account form, because an account here does not make anyone a Ranger.
class RegisterController < ApplicationController
  allow_unauthenticated_access

  before_action :redirect_if_authenticated
  before_action :halt_if_closed, unless: :finished_account?

  # Filling this in by hand takes minutes; a handful of tries a minute is more
  # than anyone needs and far less than a robot would want.
  #
  # Sent back as "see other" so the browser asks for the page afresh rather
  # than offering to send the form a second time.
  rate_limit to: 5, within: 60.seconds, only: :create,
             with: -> {
               redirect_to register_path(step: "form"), status: :see_other,
                           error: "Too many attempts. Please try again in a minute."
             }

  # The steps a reader walks through, in order. Anything else is treated as a
  # fresh arrival rather than shown an error, since the step travels in the
  # address and is easy to mistype.
  STEPS = %w[intent volunteer acknowledge form success].freeze

  # What the finished account's page needs to name, carried across the redirect
  # that follows a successful sign-up.
  #
  # Held in the session rather than the flash: a flash lasts exactly one more
  # request, so anything else the browser asked for in the meantime -- another
  # tab, a prefetch -- would spend it, and the reader would never be told the
  # callsign they were given.
  CALLSIGN_KEY = :registered_callsign

  def show
    @step = STEPS.include?(params[:step]) ? params[:step] : STEPS.first

    # Taken once and put down again, so the page reads as a one-off
    # congratulation rather than a record anyone can come back to.
    @callsign = session.delete(CALLSIGN_KEY) if @step == "success"

    # Nothing to congratulate anyone about once the account has been named, so
    # a later visit starts the reader over.
    return redirect_to register_path if @step == "success" && @callsign.blank?

    # The address fields start on the country most accounts are opened from.
    @form = RegisterForm.new(country: "US") if @step == "form"
  end

  def create
    @form = RegisterForm.new(form_params)

    # Someone here to become a Ranger is turned around rather than told which
    # of their answers were wrong. Checked before anything else so they are
    # never made to fix a form they should not be filling in.
    if @form.intent == RegisterForm::RANGER_INTENT
      return redirect_to register_path(step: "volunteer"), status: :see_other
    end

    if @form.save
      # Sent on to a page of its own so the congratulations can be reloaded,
      # shared, and stepped back to without offering to open a second account.
      session[CALLSIGN_KEY] = @form.person.callsign
      return redirect_to register_path(step: "success"), status: :see_other
    end

    # A form answered with a plain 200 is thrown away by the browser rather
    # than shown, so a rejected save has to say so with its status or nothing
    # appears to happen.
    @step = "form"
    render :show, status: :unprocessable_entity
  end

  private

  # `expect` rather than `require`, so a request whose register_form is not a
  # set of answers at all is turned away as a bad request instead of raising.
  # Anyone can post here, and plenty of what arrives will not be a filled-in
  # form.
  def form_params
    params.expect(register_form: [*RegisterForm::PERSON_ATTRIBUTES, :password,
                                  :password_confirmation, :intent, :human_answer])
  end

  # Registration closes outside the season, and the training server never opens
  # accounts at all. Both say so on the page: a visitor here is not signed in,
  # so sending them anywhere else would land them on a login screen with no
  # explanation.
  def halt_if_closed
    return unless Setting.get_value(Setting::AUDITOR_REGISTRATION_DISABLED) || Current.is_ghd_server?

    @step = "closed"
    render :show, status: :service_unavailable
  end

  # The page naming an account that has just been opened. Closing the season
  # between the form and this page would otherwise tell someone holding a new
  # account that accounts cannot be opened.
  def finished_account?
    request.get? && params[:step] == "success" && session[CALLSIGN_KEY].present?
  end
end
