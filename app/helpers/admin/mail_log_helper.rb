# frozen_string_literal: true

module Admin::MailLogHelper
  MAIL_LOG_FILTER_CHIP_LABELS = {
    person_callsign: "Person",
    email: "Email",
    subject: "Subject"
  }.freeze

  # One filter_bar chip per active search field. Each URL drops that one field
  # and keeps the rest.
  def mail_log_filter_chips(form)
    active = form.query_params[MailLogFilterForm::PARAM_SCOPE] || {}

    filter_chips(active, MAIL_LOG_FILTER_CHIP_LABELS) do |remaining, _key|
      admin_mail_log_path(remaining.any? ? { MailLogFilterForm::PARAM_SCOPE => remaining } : {})
    end
  end
end
