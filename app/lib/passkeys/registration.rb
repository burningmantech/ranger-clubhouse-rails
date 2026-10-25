# frozen_string_literal: true

module Passkeys
  # Adding a passkey to an account. start hands the browser what it needs to
  # ask a phone, laptop or security key for a passkey, and finish checks what
  # came back and keeps it.
  #
  # Everything that can be refused is refused in start, before the device
  # makes anything. A passkey the Clubhouse turns down afterwards stays behind
  # in the person's password manager as a dead entry they must clear by hand.
  #
  # hardware_only is for an Admin enrolling a key onto someone else's account.
  # The device's part happens in the Admin's browser, so without care the
  # passkey could land in the Admin's own password manager -- a quiet, standing
  # way to be that person. The browser is steered to a security key, and a
  # passkey that can be copied between devices, or that lives in the computer
  # itself, is refused. With no attestation asked for, those two facts are
  # relayed by the Admin's browser: this stops accidents and casual misuse, not
  # an Admin running a doctored browser -- who could set the person's password
  # anyway. What makes it loud rather than quiet is elsewhere: added_by on the
  # passkey, the action log, and the email to the person.
  class Registration < Ceremony
    SESSION_KEY = "passkey_registration"

    WRONG_PASSWORD = "That is not your current password."
    EXPIRED = "That took too long. Add the passkey again."
    UNVERIFIED = "The Clubhouse could not check that passkey. Add it again."
    DUPLICATE = "That passkey is already on a Clubhouse account."
    NOT_HARDWARE = "That passkey can be copied between devices or lives in this computer, so it cannot be " \
                   "enrolled for someone else. Use a hardware security key, and delete the passkey that was just made."

    # Steers the browser past the computer's own passkeys and the Admin's
    # password manager, straight to a plugged-in or tapped key.
    HARDWARE_SELECTION = { authenticator_attachment: "cross-platform" }.freeze
    HARDWARE_HINTS = ["security-key"].freeze

    # @param person [Person] the account the passkey goes on
    # @param actor [Person] who is at the keyboard, and whose password is asked for
    # @param session [ActionDispatch::Request::Session, Hash] see Ceremony
    # @param relying_party [WebAuthn::RelyingParty] see Ceremony
    # @param hardware_only [Boolean] accept nothing but a hardware security key
    def initialize(person:, actor:, session:, relying_party:, hardware_only: false)
      super(session: session, relying_party: relying_party)
      @person = person
      @actor = actor
      @hardware_only = hardware_only
    end

    # @param nickname [String] what the person wants to call the passkey
    # @param current_password [String] the actor's own password
    # @return [Outcome] the options a browser passes to the device, or why not
    def start(nickname:, current_password:)
      candidate = PersonPasskey.new(nickname: nickname.to_s)
      candidate.validate
      problem = candidate.errors[:nickname].first
      problem ||= PersonPasskey::LIMIT_MESSAGE if PersonPasskey.limit_reached?(person)
      problem ||= WRONG_PASSWORD unless actor.authenticate(current_password.to_s)
      return refused(problem) if problem

      selection = { resident_key: "required", user_verification: "required" }
      selection.merge!(HARDWARE_SELECTION) if hardware_only
      options = relying_party.options_for_registration(
        user: { id: PersonPasskey.user_handle(person), name: person.email, display_name: person.callsign },
        exclude: person.passkeys.pluck(:external_id),
        authenticator_selection: selection
      )
      # Made for this account: a registration begun for one account can never
      # be finished against another.
      keep_pending(SESSION_KEY, options.challenge, nickname: candidate.nickname, person_id: person.id)
      # The library has no word for hints, so they join what it hands back.
      accepted(hardware_only ? options.as_json.merge(hints: HARDWARE_HINTS) : options)
    end

    # @param credential_json [String] what the device made, as the browser's JSON
    # @return [Outcome] the saved PersonPasskey, or why not
    def finish(credential_json)
      pending = take_pending(SESSION_KEY)
      return refused(EXPIRED) unless pending && pending["person_id"] == person.id

      credential = checked(person_id: person.id, actor_id: actor.id) do
        relying_party.verify_registration(JSON.parse(credential_json.to_s), pending["challenge"], user_verification: true)
      end
      return refused(UNVERIFIED) unless credential
      return refused(NOT_HARDWARE) if hardware_only && !hardware_key?(credential)

      passkey = person.passkeys.create(
        external_id: credential.id, public_key: credential.public_key, sign_count: credential.sign_count,
        aaguid: credential.response.aaguid, nickname: pending["nickname"],
        added_by: (actor unless actor == person)
      )
      passkey.persisted? ? accepted(passkey) : refused(passkey.errors.full_messages.first)
    rescue ActiveRecord::RecordNotUnique
      refused(DUPLICATE)
    end

    private

    attr_reader :person, :actor, :hardware_only

    # A security key's passkey never leaves the key: it is not eligible for
    # backup, and the browser reports it as coming from outside the computer.
    # Recorded when it fails, because an Admin putting a copyable passkey on
    # someone else's account is the very thing this is here to stop.
    def hardware_key?(credential)
      return true if !credential.backup_eligible? && credential.authenticator_attachment != "platform"

      ErrorLog.record("passkey-enrollment-not-hardware", data: { person_id: person.id, actor_id: actor.id })
      false
    end

    def refusal_type(_error)
      "passkey-registration-refused"
    end
  end
end
