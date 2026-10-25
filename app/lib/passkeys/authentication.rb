# frozen_string_literal: true

module Passkeys
  # Signing in with a passkey. start hands the browser a challenge, and finish
  # checks what the phone, laptop or security key did with it and says whose
  # passkey it was.
  #
  # No email address is asked for: the device offers the passkeys it holds for
  # this Clubhouse and the person picks one, so nothing here can be used to
  # find out which addresses have accounts.
  class Authentication < Ceremony
    SESSION_KEY = "passkey_authentication"

    EXPIRED = "That took too long. Select Sign In with a Passkey to try again."
    # One sentence for every other failure. A passkey the Clubhouse has never
    # seen and one that failed its checks must not be told apart from outside.
    UNRECOGNIZED = "The Clubhouse doesn't recognize that passkey. Sign in with your email address and password instead."

    # @return [Outcome] the options a browser passes to the device
    def start
      options = relying_party.options_for_authentication(user_verification: "required")
      keep_pending(SESSION_KEY, options.challenge)
      accepted(options)
    end

    # @param credential_json [String] what the device answered, as the browser's JSON
    # @return [Outcome] the PersonPasskey that signed in (its person is who), or why not
    def finish(credential_json)
      pending = take_pending(SESSION_KEY)
      return refused(EXPIRED) unless pending

      raw = checked { JSON.parse(credential_json.to_s) }
      passkey = presented_passkey(raw)
      return refused(UNRECOGNIZED) unless passkey

      credential = checked(passkey_id: passkey.id, person_id: passkey.person_id) do
        relying_party.verify_authentication(raw, pending["challenge"], public_key: passkey.public_key,
                                                                       sign_count: passkey.sign_count,
                                                                       user_verification: true)
      end
      return refused(UNRECOGNIZED) unless credential && handle_agrees?(credential, passkey)

      passkey.used!(credential.sign_count)
      accepted(passkey)
    end

    private

    # The passkey the device says it used. A row whose person is gone counts as
    # no passkey at all: Clubhouse 2 shares the database and can delete a person
    # without knowing this table exists.
    def presented_passkey(raw)
      return unless raw.is_a?(Hash) && raw["id"].is_a?(String)

      passkey = PersonPasskey.includes(:person).find_by(external_id: raw["id"])
      passkey if passkey&.person
    end

    # A device that names the account it filed the passkey under must name the
    # account the passkey is on. Not every device does.
    def handle_agrees?(credential, passkey)
      credential.user_handle.nil? || credential.user_handle == PersonPasskey.user_handle(passkey.person)
    end

    # A counter that went backwards is the one failure that can mean a copied
    # security key, so it gets a name of its own in the error log.
    def refusal_type(error)
      error.is_a?(WebAuthn::SignCountVerificationError) ? "passkey-sign-count-regression" : "passkey-sign-in-refused"
    end
  end
end
