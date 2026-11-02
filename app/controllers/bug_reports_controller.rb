# frozen_string_literal: true

# The Bug Report dialog, from the account menu. Anyone signed in may file a report;
# the Tech Team reads them at admin/bug-reports.
class BugReportsController < ApplicationController
  # Every report emails the Tech Cadre list, so one person can send only so
  # many. Counted by person rather than address, since on the playa a whole
  # camp shares one.
  rate_limit to: 10, within: 10.minutes, only: :create, by: -> { Current.person.id },
             with: -> {
               render turbo_stream: ui_toast_stream("Too many bug reports at once. Wait a few minutes, then send this one again.", :error),
                      status: :too_many_requests
             }

  # A GET, so it opens into the layout's modal frame. Without a kind it asks
  # bug or feature request; kind=bug is the form, and kind=feature says where
  # a feature request goes instead (the view).
  def new
    @kind = params[:kind]
    @bug_report = BugReport.new if @kind == "bug"
  end

  def create
    @bug_report = BugReport.new(
      description: params.expect(bug_report: [:description])[:description],
      person: Current.person,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      url: reported_from
    )

    if @bug_report.save
      notify_tech_cadre
      render turbo_stream: [modal_close_dialog, ui_toast_stream("Bug report sent.", :success)]
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Emails the Tech Cadre. The report is saved already, so a mail queue that
  # cannot take the email must not turn it into an error page the person
  # would answer by filing again.
  def notify_tech_cadre
    person = @bug_report.person
    BugReportMailer.with(sender_id: person.id)
                   .notify(callsign: person.callsign, email: person.email, browser: @bug_report.browser,
                           page: @bug_report.url, description: @bug_report.description)
                   .deliver_later
  rescue => e
    Rails.logger.error("Could not queue the email for bug report #{@bug_report.id}: #{e.class}: #{e.message}")
  end

  # The page the person was looking at. The dialog never changes the address
  # bar, so the page that posted the form is the page they were on.
  #
  # Path only: a query string can carry a token, and this log is read by people.
  def reported_from
    URI.parse(request.referer.to_s).path.presence
  rescue URI::InvalidURIError
    nil
  end
end
