# frozen_string_literal: true

module Passkeys
  # What adding a passkey and signing in with one have in common. Each takes
  # two requests with the device's own part in between: the first hands the
  # browser a challenge and keeps a note of it, and the second checks what the
  # device did with it.
  class Ceremony
    # How long someone has to get through their device's prompts.
    LIFETIME = 5.minutes

    # What either request comes to: something to hand on, or the sentence that
    # says why not.
    Outcome = Data.define(:value, :error) do
      def ok? = error.nil?
    end

    # Handed the two things it needs from a request rather than the request
    # itself, so its rules can be tested without one.
    #
    # @param session [ActionDispatch::Request::Session, Hash] where the first
    #   request leaves its note for the second
    # @param relying_party [WebAuthn::RelyingParty] what a passkey is checked
    #   against: Passkeys.relying_party
    def initialize(session:, relying_party:)
      @session = session
      @relying_party = relying_party
    end

    private

    attr_reader :session, :relying_party

    def accepted(value)
      Outcome.new(value: value, error: nil)
    end

    def refused(message)
      Outcome.new(value: nil, error: message)
    end

    # The note the first request leaves for the second. The real clock, not
    # Current.time -- the training server's clock is not a security clock.
    def keep_pending(key, challenge, **details)
      session[key] = details.stringify_keys.merge("challenge" => challenge, "at" => Time.now.to_i)
    end

    # Single use: gone from the session whether or not it is still good.
    def take_pending(key)
      pending = session.delete(key)
      pending if pending.is_a?(Hash) && pending["at"].to_i > LIFETIME.ago.to_i
    end

    # Runs a call into the WebAuthn library, or the parsing in front of it, and
    # answers nil for anything that does not check out.
    #
    # The rescue is as wide as it is on purpose, and a block given here should
    # hold nothing but that call. Handed bytes it cannot read, the library
    # raises whatever its parsers raise -- NoMethodError, EOFError, IOError,
    # JSON::ParserError, a bare RuntimeError -- rather than its own errors, and
    # none of those may turn a forged form field into an error page. What went
    # wrong is recorded, never the bytes: a wrong address in
    # RANGER_CLUBHOUSE_PASSKEY_ORIGIN looks exactly like a forgery from the
    # outside, and the error log is how an operator tells them apart.
    def checked(**details)
      yield
    rescue StandardError => e
      ErrorLog.record(refusal_type(e), data: details.merge(reason: e.class.name))
      nil
    end
  end
end
