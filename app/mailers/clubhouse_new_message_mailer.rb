# frozen_string_literal: true

class ClubhouseNewMessageMailer < ApplicationMailer
  # The email carries a private Clubhouse message, so the mail log keeps no
  # copy of it.
  self.withhold_body_from_mail_log = true

  # to: the test address while broadcast email is tested (Rbs.message_notify).
  # A group message, one conversation everyone in it sees, comes .with(group:
  # true); from is then the author's callsign or, for a message sent as a team,
  # the team's title. A param rather than a keyword: a mail job this release
  # enqueues is run by the release before it while a rolling deploy overlaps
  # them, and that release's notify refused a keyword it did not know.
  def notify(person:, from:, subject:, message:, to: person.email)
    group = params[:group] || false
    liquid_assigns.merge!(
      person: { callsign: person.callsign },
      message_from: from,
      message_subject: subject,
      message_body: message,
      message_group: group
    )

    mail(
      from: format_from(from_do_not_reply, "The Black Rock Rangers"),
      to:,
      subject: liquid_subject("[Clubhouse #{"Group " if group}Message] #{subject}")
    )
  end
end
