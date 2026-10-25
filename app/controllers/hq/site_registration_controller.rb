# frozen_string_literal: true

# On-Site Registration wizard for the HQ Window Interface
# (/hq/:person_id/site-registration). Ported from the Ember
# port/templates/hq/site-checkin.hbs, port/controllers/hq/site-checkin.js,
# and port/routes/hq/site-checkin.js; the staged step engine mirrors
# port/components/ui-wizard{,-step}.{js,hbs} as the hq-wizard Stimulus
# controller over server-rendered step sections.
#
# Wire contract: step saves respond with Turbo Streams — a failed save
# re-renders the step form with errors, a successful save re-renders it fresh
# and streams the advance signal the wizard listens for, so the wizard only
# advances once the server confirms the write (upstream saveContactForm
# semantics). Marking on site is a full-page redirect and the success state
# keys off person.on_site itself.
class Hq::SiteRegistrationController < ApplicationController
  include HqConcern
  # Barcode checkout/check-in/attachment for the Radios step. This controller
  # routes the concern's actions itself and overrides assets_outcome to answer
  # with a Turbo Stream, keeping the operator on the current wizard step.
  include AssetManagementConcern

  # Server-side lockout once the person is on site — the Ember client only
  # disabled the Begin button.
  before_action :block_when_on_site,
                only: %i[save_camp_info save_emergency_contact radio_check mark_on_site]

  helper_method :can_edit_emergency_contact?, :wizard_steps

  WizardStep = Data.define(:name, :title)

  CAMP_INFO_STEP = WizardStep.new(name: "camp-info", title: "Verify Camp Information")
  EMERGENCY_CONTACT_STEP = WizardStep.new(name: "emergency-contact",
                                          title: "Verify Emergency Contact Information")
  RADIOS_STEP = WizardStep.new(name: "radios", title: "Radios")
  ON_SITE_STEP = WizardStep.new(name: "on-site", title: "Mark Person as On Site")

  def show
    load_radio_step_data unless @person.on_site || @person.pnv?
  end

  def save_camp_info
    if @person.update(params.expect(person: [:camp_location]))
      render_step_saved(CAMP_INFO_STEP, "Saved the camp information.")
    else
      render_step_errors(CAMP_INFO_STEP)
    end
  end

  def save_emergency_contact
    unless can_edit_emergency_contact?
      redirect_to hq_site_registration_path(@person),
                  error: "You cannot update emergency contact information right now. " \
                         "Ranger operations must be running on playa."
      return
    end

    if @person.update(params.expect(person: [:emergency_contact]))
      render_step_saved(EMERGENCY_CONTACT_STEP, "Saved the emergency contact information.")
    else
      render_step_errors(EMERGENCY_CONTACT_STEP)
    end
  end

  # Interstitial guard behind the Radios step "Next" (upstream checkForRadio):
  # when the person is allowed an event radio but none is checked out, confirm
  # before moving on. Confirm advances the wizard client-side, Cancel stays,
  # and no audit record is written — upstream parity.
  def radio_check
    if allowed_event_radio? && !event_radio_checked_out?
      render turbo_stream: turbo_stream.update("modal",
                                               partial: "hq/site_registration/no_radio_modal",
                                               locals: { callsign: @person.callsign })
    else
      render turbo_stream: advance_stream
    end
  end

  # Explicit set — not the person-page toggle. on_site only flips when the
  # save succeeds (upstream set the attribute before the request; the port
  # deliberately does not).
  def mark_on_site
    @person.on_site = true
    if @person.save(validate: false)
      redirect_to hq_site_registration_path(@person),
                  success: "#{@person.callsign} is now marked on site."
    else
      redirect_to hq_site_registration_path(@person),
                  error: "Could not mark #{@person.callsign} as on site. " \
                         "Try again — if it keeps failing, report it to the Tech Ninjas."
    end
  end

  private

  # AssetManagementConcern path contract — this controller's own endpoints, so
  # gear issued during registration stays inside the wizard.
  def assets_person = @person

  def assets_return_path = hq_site_registration_path(@person)

  def assets_checkout_path = hq_site_registration_assets_path(@person)

  def assets_check_in_path(person_asset)
    hq_site_registration_asset_check_in_path(@person, person_asset)
  end

  def assets_change_attachment_path(person_asset)
    hq_site_registration_asset_change_attachment_path(@person, person_asset)
  end

  def assets_update_attachment_path(person_asset)
    hq_site_registration_asset_update_attachment_path(@person, person_asset)
  end

  # The asset controls render inside the wizard's open dialog, and the wizard's
  # step position lives only in the Stimulus controller. A redirect would
  # neither match the frame nor survive the remount, so every asset outcome
  # re-renders the Radios step in place — carrying the outcome message inline,
  # since a page toast would sit dimmed behind the dialog's top layer — and
  # closes any modal stacked above the wizard.
  def assets_outcome(flash_type, message, **)
    load_radio_step_data
    render turbo_stream: [
      radios_step_stream(notice: message,
                         notice_type: flash_type == :error ? :error : :success),
      turbo_stream.update("modal", "")
    ]
  end

  def radios_step_stream(notice: nil, notice_type: nil)
    turbo_stream.update("hq-step-#{RADIOS_STEP.name}",
                        partial: "hq/site_registration/radios_step",
                        locals: { person: @person, person_event: @person_event,
                                  event_info: @event_info, active_assets: @active_assets,
                                  attachments: @attachments, checkout_form: @checkout_form,
                                  notice:, notice_type: })
  end

  # Steps in wizard order — Radios is skipped entirely for Alphas and
  # Prospectives (upstream isAlphaOrProspective; Person#pnv? covers both).
  def wizard_steps
    steps = [CAMP_INFO_STEP, EMERGENCY_CONTACT_STEP]
    steps << RADIOS_STEP unless @person.pnv?
    steps << ON_SITE_STEP
  end

  # Emergency Contact write gate — the same authorization the profile stack
  # applies to the emergency-contact section (Current.can_view_emergency_contact?:
  # Admin / Event Management / Event Management On Playa mode) plus the
  # dedicated EDIT_EMERGENCY_CONTACT role the upstream HQ gate names. The
  # Ember gate was UX-only; here it is enforced server-side.
  #
  # Deliberately broader than upstream, decided 2026-07-21: Ember allowed
  # Admin / EMOP-enabled / Edit Emergency Contact, so a plain Event Management
  # holder was refused off-season. Matching that would leave HQ and
  # /person/N/profile disagreeing about who may edit the same field, so this
  # follows the Rails profile stack instead. The "off season" notice still
  # renders for a Shift-Management-only worker.
  def can_edit_emergency_contact?
    can_view_emergency_contact? || has_role?(Role::EDIT_EMERGENCY_CONTACT)
  end

  def block_when_on_site
    return true unless @person.on_site

    redirect_to hq_site_registration_path(@person),
                info: "#{@person.callsign} is already marked on site. On-Site Registration is complete."
    false
  end

  def load_radio_step_data
    @active_assets = PersonAsset.find_for_query(person_id: @person.id, year: Current.year)
                                .reject { |person_asset| person_asset.checked_in.present? }
    @attachments = AssetAttachment.find_all
    @checkout_form = AssetCheckoutForm.new
  end

  # Upstream allowedEventRadio — eligible, agreement signed, and a positive cap.
  def allowed_event_radio?
    @event_info.radio_eligible && @person_event.asset_authorized &&
      @event_info.radio_max.to_i.positive?
  end

  # Any current-year, not-checked-in radio (upstream activeAssets radio scan).
  def event_radio_checked_out?
    PersonAsset.retrieve_type_for_person_ids(Asset::TYPE_RADIO, [@person.id]).present?
  end

  def render_step_saved(step, message)
    render turbo_stream: [
      step_stream(step),
      advance_stream,
      ui_toast_stream(message, :success)
    ]
  end

  def render_step_errors(step)
    render turbo_stream: step_stream(step)
  end

  def step_stream(step)
    turbo_stream.update("hq-step-#{step.name}",
                        partial: "hq/site_registration/#{step.name.underscore}_step",
                        locals: { person: @person })
  end

  def advance_stream
    turbo_stream.update("hq-wizard-signal", partial: "hq/site_registration/advance_signal")
  end
end
