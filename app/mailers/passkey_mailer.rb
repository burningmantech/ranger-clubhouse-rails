# frozen_string_literal: true

# Tells someone that the ways into their account have changed: a passkey was
# added, or one was removed, by them or by an Admin.
#
# Sent every time, whoever did it. It is how a person hears of a passkey they
# did not add -- from a session someone else got hold of, or from an Admin who
# enrolled a key for them -- and a changed password is noticed where a second
# passkey never would be.
#
# The message carries no link, on purpose. A security notice that teaches
# people to follow its link is a gift to whoever forges the next one, so it
# names the place instead: the Account menu, then Passkeys.
class PasskeyMailer < ApplicationMailer
  # @param person [Person] whose account it is
  # @param nickname [String] what the passkey is called
  # @param by [Person] who added it: the person themselves, or an Admin
  def added(person:, nickname:, by:)
    notice(person, nickname, by)
  end

  # @param person [Person] whose account it is
  # @param nickname [String] what the passkey was called
  # @param by [Person] who removed it: the person themselves, or an Admin
  def removed(person:, nickname:, by:)
    notice(person, nickname, by)
  end

  private

  def notice(person, nickname, by)
    liquid_assigns.merge!(
      greeting: "Hi #{person.desired_first_name}",
      nickname: nickname,
      by_you: by == person,
      by_callsign: by.callsign,
      support_email: EmailAddresses::TECH_CADRE
    )

    mail(from: do_not_reply_from, to: person.email, subject: liquid_subject)
  end
end
