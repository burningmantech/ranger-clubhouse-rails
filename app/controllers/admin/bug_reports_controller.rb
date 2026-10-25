# frozen_string_literal: true

# The problems people reported from the Bug Report button in the top menu.
# Tech Team only, and that is narrower than the other logs on purpose: an
# Admin who is not also a Tech Ninja is turned away.
class Admin::BugReportsController < ApplicationController
  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to read bug reports."

  def index
    # Loaded here, once: the page asks the list whether it is empty, how long
    # it is, and for its rows, and a relation answers each with a query.
    @bug_reports = BugReport.for_log.to_a
    # Only a full page can be hiding more reports, so only then is the table
    # counted.
    @total = @bug_reports.size < BugReport::LIST_LIMIT ? @bug_reports.size : BugReport.count
  end

  def purge
    count = BugReport.purge!(Current.person)

    redirect_to admin_bug_reports_path, notice: "#{helpers.pluralize(count, 'bug report')} deleted."
  end
end
