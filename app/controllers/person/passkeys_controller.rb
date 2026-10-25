# frozen_string_literal: true

# The passkeys on someone's account, for an Admin to look over, remove, and --
# when the Tech Team hands someone a security key -- add to.
#
# Removing a passkey stops it signing in. It does not sign anyone out -- that
# is Login Sessions, and the page says so.
#
# Enrolling a key for someone else happens in the Admin's own browser, which is
# the hazard: see Passkeys::Registration's hardware_only. Here the Admin's own
# password is asked for (PasskeyRegistrationConcern), nothing but a hardware
# key is accepted, and the person is told who did it.
#
# Every add and removal is written to the action log by PersonPasskey itself,
# with the Admin as who and the person as whose, and emailed to the person
# (PasskeyMailer).
class Person::PasskeysController < ApplicationController
  include PasskeyRegistrationConcern

  layout "person"

  include PersonConcern

  # After the include: the last authorize_role replaces the concern's wider list.
  authorize_role [Role::ADMIN]

  # Seeing and removing answer everywhere, so an Admin can clear a passkey even
  # on a Clubhouse that offers none. Adding one needs passkeys to be on.
  before_action :require_passkeys_enabled, only: %i[new options create]

  def index
    @passkeys = @person.passkeys.includes(:added_by).order(:created_at)
  end

  def new
    @form = PasskeyForm.new(nickname: "Security Key")
  end

  def create
    outcome = passkey_registration.finish(passkey_form_params[:credential])

    if outcome.ok?
      PasskeyMailer.with(sender_id: current_user.id)
                   .added(person: @person, nickname: outcome.value.nickname, by: current_user).deliver_later
      redirect_to person_passkeys_path(@person), status: :see_other,
                                                 success: "#{outcome.value.nickname} can now sign in as #{@person.callsign}, " \
                                                          "and an email went to #{@person.callsign}."
    else
      @form = PasskeyForm.new(nickname: passkey_form_params[:nickname])
      @form.errors.add(:base, outcome.error)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    passkey = @person.passkeys.find(params[:id])
    passkey.destroy
    # The person hears of it, and from whom: see PasskeyMailer.
    PasskeyMailer.with(sender_id: current_user.id)
                 .removed(person: @person, nickname: passkey.nickname, by: current_user).deliver_later

    redirect_to person_passkeys_path(@person), status: :see_other,
                                               success: "#{passkey.nickname} can no longer sign in as #{@person.callsign}."
  end

  private

  def passkey_registration
    Passkeys::Registration.new(person: @person, actor: current_user, hardware_only: true,
                               session: session, relying_party: Passkeys.relying_party(request))
  end

  def require_passkeys_enabled
    return if Passkeys.enabled?(request)

    redirect_to person_passkeys_path(@person), error: "Passkeys are switched off on this Clubhouse."
  end
end
