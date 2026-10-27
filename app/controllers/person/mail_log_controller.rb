# frozen_string_literal: true

# Read-only audit view of the emails the Clubhouse has sent to or from a
# person, plus the history of email address changes on the account.
class Person::MailLogController < ApplicationController
  layout "person"

  include PersonConcern

  # Narrows the broad person-page gate applied by PersonConcern.
  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view the mail log."

  def index
    result = MailLog.find_for_query(person_id: @person.id, page: params[:page])
    # Pagy returns a lazy relation; load it so the view's .any? doesn't issue
    # an extra query.
    @logs = result[:mail_log].to_a
    @pagy = result[:pagy]
    @stats = MailLog.retrieve_stats(@person.id)
    @email_history = EmailHistory.find_for_query(person_id: @person.id, include_source_person: 1).to_a
  end

  # Lazy turbo-frame target: renders a single message body. Scoped the same
  # way as find_for_query — the person may be the recipient or the sender.
  def body
    @mail = MailLog.where(person_id: @person.id).or(MailLog.where(sender_id: @person.id)).find(params[:id])
    render "common/mail_log/body", layout: false
  end
end
