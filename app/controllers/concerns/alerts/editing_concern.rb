# frozen_string_literal: true

module Alerts::EditingConcern
  extend ActiveSupport::Concern

  UpdateResult = Data.define(:changes)

  PREFERENCES_INTENT = "save_preferences"
  SMS_STATE_INTENT = "save_sms_state"

  def edit
    render template: "alerts/edit", locals: edit_locals
  end

  def update
    # The SMS state form skips verification, so only an admin allowed it may send it.
    if admin_acting? ? !admin_intent_allowed?(params[:intent]) : params[:intent] == SMS_STATE_INTENT
      head :forbidden
      return
    end

    case params[:intent]
    when "save_number"
      handle_save_number
    when "confirm_code"
      handle_confirm_code
    when "send_code"
      handle_send_code
    when PREFERENCES_INTENT
      handle_save_preferences
    when SMS_STATE_INTENT
      handle_save_sms_state
    else
      flash[:error] = "Unknown action."
      redirect_to action: :edit
    end
  end

  private

  def edit_locals
    {
      person: @person,
      alerts: PersonAlert.find_all_for_person(@person.id),
      admin_acting: admin_acting?,
      can_edit_sms_state: admin_acting? && has_role?(Role::TECH_NINJA),
      can_view_sms_state: admin_acting? && has_role?(Role::ADMIN),
      alerts_form_path: alerts_form_path,
      alerts_back_path: alerts_back_path
    }
  end

  # =========================================================================
  # Intent: save_number
  # =========================================================================

  def handle_save_number
    return unless prevent_if_ghd_server("SMS number update")

    # A blank number clears it, so a request that is not a set of fields is
    # refused (400) by expect rather than read as blank.
    result = ::Alerts::SmsPreferencesService.save_number(
      person: @person,
      raw_number: params.expect(person: [:sms_number])[:sms_number]
    )

    if result.success?
      case result.status
      when "sent"
        flash[:success] = "Phone number updated. Verification code sent."
        ActionLog.record(current_user, "person-sms-update", "SMS number updated")
      when "sent-fail"
        flash[:warning] = "Phone number updated, but a verification code could not be sent. Please try resending."
        ActionLog.record(current_user, "person-sms-update", "SMS number updated, verification send failed")
      when "cleared"
        flash[:success] = "Phone number removed."
        ActionLog.record(current_user, "person-sms-update", "SMS number removed")
      when "unchanged"
        flash[:info] = "Phone number is unchanged."
      end
      redirect_to action: :edit
    else
      flash.now[:error] = sms_error_message(result)
      result.errors.each { |attr, msg| @person.errors.add(attr, msg) }
      render template: "alerts/edit", locals: edit_locals, status: :unprocessable_entity
    end
  end

  # =========================================================================
  # Intent: confirm_code
  # =========================================================================

  def handle_confirm_code
    result = ::Alerts::SmsPreferencesService.confirm_code(
      person: @person,
      code: scoped_params(:person, :verification_code)[:verification_code]
    )

    if result.success?
      flash[:success] = "Phone number verified."
      ActionLog.record(current_user, "person-sms-verify", "SMS number verified")
      redirect_to action: :edit
    else
      case result.status
      when "already-verified"
        flash[:info] = "Phone number is already verified."
        redirect_to action: :edit
      else
        flash.now[:error] = sms_error_message(result)
        result.errors.each { |attr, msg| @person.errors.add(attr, msg) }
        render template: "alerts/edit", locals: edit_locals, status: :unprocessable_entity
      end
    end
  end

  # =========================================================================
  # Intent: send_code
  # =========================================================================

  def handle_send_code
    return unless prevent_if_ghd_server("SMS verification")

    result = ::Alerts::SmsPreferencesService.send_code(person: @person)

    if result.success?
      case result.status
      when "sent"
        flash[:success] = "New verification code sent."
      when "sent-fail"
        flash[:error] = "Could not send verification code at this time. Please try again later."
      end
    else
      case result.status
      when "already-verified"
        flash[:info] = "Phone number is already verified."
      when "no-number"
        flash[:error] = "No phone number on file. Please add one first."
      end
    end

    redirect_to action: :edit
  end

  # =========================================================================
  # Intent: save_preferences
  # =========================================================================

  def handle_save_preferences
    result = update_alerts

    if result.changes.present?
      ActionLog.record(current_user, "person-alerts-update",
                       admin_acting? ? "alerts update for #{@person.callsign}" : "alerts update",
                       { "alerts" => result.changes, "person_id" => @person.id })
    end

    flash[:success] = "Alert preferences updated."
    redirect_to action: :edit
  end

  # =========================================================================
  # Intent: save_sms_state (TECH_NINJA only)
  # =========================================================================

  def handle_save_sms_state
    @person.update!(sms_state_params)
    flash[:success] = "SMS state updated."
    redirect_to action: :edit
  end

  def sms_state_params
    permitted = params.expect(person: [:sms_number, :sms_stopped, :sms_verified])
    permitted[:sms_number] = nil if permitted[:sms_number].is_a?(String) && permitted[:sms_number].strip.empty?
    permitted
  end

  def update_alerts
    alert_changes = []

    alerts_params.each do |pref|
      alert = Alert.find_by(id: pref[:id])
      next unless alert

      person_alert = PersonAlert.find_or_create_for_person(@person.id, alert.id)
      person_alert.use_email = pref[:use_email] if pref.key?(:use_email)
      person_alert.use_sms = pref[:use_sms] if pref.key?(:use_sms)

      changes = person_alert.changes.slice("use_email", "use_sms")
      person_alert.save!

      alert_changes << changes.merge("alert_id" => alert.id) if changes.present?
    end

    UpdateResult.new(changes: alert_changes)
  end

  # Anything that is not a row of attributes is dropped rather than raising:
  # this hash comes off the wire.
  def alerts_params
    alerts = params[:alerts]
    return [] unless alerts.respond_to?(:each_value)

    alerts.each_value.filter_map do |alert_param|
      alert_param.permit(:id, :use_email, :use_sms) if alert_param.respond_to?(:permit)
    end
  end

  def sms_error_message(result)
    case result.status
    when "invalid-number"
      "The phone number does not appear to be valid."
    when "duplicate-number"
      "The phone number is already used by another account."
    when "country-not-supported"
      result.errors[:sms_number] || "Phone numbers from this country cannot be used at this time."
    when "no-match"
      "The verification code does not match."
    else
      "An error occurred. Please try again."
    end
  end
end
