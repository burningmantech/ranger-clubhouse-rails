# frozen_string_literal: true

class PersonController < ApplicationController
  include PersonConcern

  # admin: false -- Clubhouse 2's PersonPolicy#delete admits Tech Ninja alone, and
  # that policy has no before hook letting Admin through. The same gate answers the
  # Delete Account item in person/_actions, so the menu and the guard cannot disagree.
  authorize_ability :delete_account,
                    roles: [Role::TECH_NINJA],
                    admin: false,
                    only: :destroy,
                    deny_to: :overview_path,
                    message: "Tech Ninja role required to delete an account."

  # Clubhouse 2's PersonPolicy#sendWelcomeEmail admits Admin or VC, asked before the
  # prospective check. The same gate answers the Resend Welcome Message item in
  # person/_actions.
  authorize_ability :resend_welcome,
                    roles: [Role::VC],
                    only: :resend_welcome,
                    deny_to: :overview_path,
                    message: "Admin or Volunteer Coordinator role required to resend the welcome message."

  # Clubhouse 2 keeps on_site in PersonFilter's EVENT_FIELDS, which only Shift
  # Management (or Admin) may write; Event Management alone was silently refused there.
  # The same gate answers the Mark On/Off Site button in person/_actions.
  authorize_ability :toggle_onsite,
                    roles: [Role::SHIFT_MANAGEMENT],
                    only: :toggle_onsite,
                    deny_to: :overview_path,
                    message: "Admin or Shift Management role required to mark a person on or off site."

  # Clearing person.on_boarded_at shows the person the first-sign-in tour again
  # (Me::DashboardController#onboarded sets it). Admin or VC, as the resend; the
  # same gate answers the Reset Onboarding Tour item in person/_actions.
  authorize_ability :reset_onboarding,
                    roles: [Role::VC],
                    only: :reset_onboarding,
                    deny_to: :overview_path,
                    message: "Admin or Volunteer Coordinator role required to reset the onboarding tour."

  def show
    role_manager = RoleManager.retrieve(@person)
    @permission_rows = PersonPermissionPresenter.new(person: @person).overview_rows(role_manager)
    @nda_blocked = role_manager.nda_blocked?
    @person_membership = Membership.retrieve_for_person(@person)
    @person_fkas = @person.person_fka.map(&:fka)
    @photo = @person.avatar_photo_attachment
    @person_banners = PersonBanner.find_for_query(person_id: @person.id, active: true)
    @email_suppression = EmailSuppression.find_by(email: @person.email)
  end

  def toggle_onsite
    @person.on_site = !@person.on_site
    @person.save(validate: false)
    redirect_to person_path(@person), success: "#{@person.callsign} is now #{@person.on_site ? "on site" : "off site"}."
  end

  def destroy
    @person.destroy
    redirect_to me_root_path, success: "Account deleted."
  end

  def resend_welcome
    unless @person.prospective?
      redirect_to person_path(@person), error: "This account has status #{@person.status}, not prospective."
      return
    end

    # As long as Create Prospectives' first link. Nothing is saved: the token is
    # signed from the record as it stands, so an older record that fails
    # validation still gets its email.
    invite_token = @person.generate_token_for(:invitation)
    WelcomeMailer.with(sender_id: current_user.id).notify(person: @person, invite_token:).deliver_later
    redirect_to person_path(@person), success: "Welcome message resent."
  end

  # update_attribute: no validations, as the resend's token save, since an older
  # record fails them; the callbacks run, so audit_model logs who reset whose.
  def reset_onboarding
    @person.update_attribute(:on_boarded_at, nil)
    redirect_to person_path(@person),
                success: "#{@person.callsign} will see the onboarding tour at their next visit to the dashboard."
  end


  def redirect_to_hq
    if Setting.get_value(Setting::HQ_WINDOW_INTERFACE_ENABLED)
      redirect_to hq_path(@person)
    else
      render turbo_stream: [ui_toast_stream("The HQ Interface is not available at this time.", :error)],
             status: :unprocessable_entity
    end
  end

  private

  def overview_path
    person_path(@person)
  end
end
