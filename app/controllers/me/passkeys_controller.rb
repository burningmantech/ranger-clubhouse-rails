# frozen_string_literal: true

require "user_agent_parser"

# A person's own passkeys: the phones, laptops, password managers and security
# keys that sign them in without a password.
#
# Adding one takes two requests with the device's own prompt in between, so
# the page's script asks `options` first (PasskeyRegistrationConcern) and sends
# what the device made to `create`. Passkeys::Registration has the rules.
#
# Every add and every removal is emailed to the person (PasskeyMailer). From
# here rather than from the model: deleting an account takes its passkeys with
# it, and must not write to the account about each one.
class Me::PasskeysController < ApplicationController
  include PasskeyRegistrationConcern

  layout "me"

  # Part of the profile, which past prospectives keep.
  skip_before_action :confine_past_prospective

  def index
    @passkeys = current_user.passkeys.includes(:added_by).order(:created_at)
  end

  def new
    @form = PasskeyForm.new(nickname: suggested_nickname)
  end

  def create
    outcome = passkey_registration.finish(passkey_form_params[:credential])

    if outcome.ok?
      PasskeyMailer.with(sender_id: current_user.id)
                   .added(person: current_user, nickname: outcome.value.nickname, by: current_user).deliver_later
      redirect_to me_profile_passkeys_path, status: :see_other,
                                            success: "#{outcome.value.nickname} can now sign you in."
    else
      @form = PasskeyForm.new(nickname: passkey_form_params[:nickname])
      @form.errors.add(:base, outcome.error)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    passkey = current_user.passkeys.find(params[:id])
    passkey.destroy
    PasskeyMailer.with(sender_id: current_user.id)
                 .removed(person: current_user, nickname: passkey.nickname, by: current_user).deliver_later

    redirect_to me_profile_passkeys_path, status: :see_other,
                                          success: "#{passkey.nickname} can no longer sign you in."
  end

  private

  def passkey_registration
    Passkeys::Registration.new(person: current_user, actor: current_user,
                               session: session, relying_party: Passkeys.relying_party(request))
  end

  # "Chrome on Mac OS X": where the person is sitting, which is most often
  # what they are about to save the passkey on.
  def suggested_nickname
    agent = UserAgentParser.parse(request.user_agent.to_s)
    "#{agent.family} on #{agent.os.family}".first(PersonPasskey::NICKNAME_LIMIT)
  end
end
