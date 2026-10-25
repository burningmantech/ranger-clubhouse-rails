# frozen_string_literal: true

# What a person adding their own passkey and an Admin enrolling a key for
# someone share: the request the page's script makes before the device is
# asked for anything, and the guard on what either request may be sent.
#
# The rules are in Passkeys::Registration. A controller says whose account and
# who is at the keyboard by defining passkey_registration.
module PasskeyRegistrationConcern
  extend ActiveSupport::Concern

  included do
    # `options` checks a password, which makes it somewhere to guess one for
    # whoever holds a stolen session.
    rate_limit to: 10, within: 1.minute, only: :options,
               with: -> { render json: { error: "Too many tries. Wait a minute, then try again." }, status: :too_many_requests }
  end

  # Asked by the page's script. Answers with what the browser hands the device,
  # or with the sentence that says why not -- before the device makes anything.
  def options
    outcome = passkey_registration.start(nickname: passkey_form_params[:nickname],
                                         current_password: passkey_form_params[:current_password])

    if outcome.ok?
      render json: outcome.value
    else
      render json: { error: outcome.error }, status: :unprocessable_entity
    end
  end

  private

  # The page sends a hash of text. A hand-built request can send anything --
  # ?passkey_form=x, passkey_form[nickname][]=x -- and none of it is of use.
  def passkey_form_params
    @passkey_form_params ||= begin
      fields = scoped_params(:passkey_form, :nickname, :current_password, :credential).to_h
      fields.transform_values { |value| value.is_a?(String) ? value : "" }.with_indifferent_access
    end
  end
end
