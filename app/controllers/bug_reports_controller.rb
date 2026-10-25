# frozen_string_literal: true

# The Bug Report dialog in the top menu. Anyone signed in may file a report;
# the Tech Team reads them at admin/bug-reports.
class BugReportsController < ApplicationController
  # A GET, so it opens into the layout's modal frame.
  def new
    @bug_report = BugReport.new
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
      render turbo_stream: [modal_close_dialog, ui_toast_stream("Bug report sent.", :success)]
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

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
