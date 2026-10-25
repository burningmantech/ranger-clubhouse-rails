# frozen_string_literal: true

# Read-only view of every email the Clubhouse has sent, searchable by
# recipient, address, and subject.
class Admin::MailLogController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  def index
    @form = MailLogFilterForm.new(filter_params)

    result = MailLog.find_for_query(
      person_id: resolve_person_id(@form.person_callsign),
      email: @form.email.presence,
      subject: @form.subject.presence,
      page: @form.page
    )

    # Pagy returns a lazy relation; load it so the view's .any? doesn't issue
    # an extra query.
    @logs = result[:mail_log].to_a
    @meta = result[:meta]
    @stats = MailLog.retrieve_stats(nil)
  end

  # Lazy turbo-frame target: renders a single message body.
  def body
    @mail = MailLog.find(params[:id])
    render "common/mail_log/body", layout: false
  end

  private

  def filter_params
    scoped_params(MailLogFilterForm::PARAM_SCOPE, :person_callsign, :email, :subject, :page)
  end

  # Falls back to an id no one holds so a callsign that matches no one returns
  # no messages. Dropping the search instead would quietly hand back the whole
  # log.
  def resolve_person_id(callsign)
    return nil if callsign.blank?

    Person.find_id_by_callsign(callsign) || 0
  end
end
