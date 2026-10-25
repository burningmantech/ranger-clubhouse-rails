# frozen_string_literal: true

# A SOQL console onto the Salesforce org the application import reads. Tech
# Team only: an Admin who is not also a Tech Ninja is turned away.
#
# run answers 200 with turbo streams, never the house 422 re-render:
# RequestLogger keeps a 422's parameters and page in request_log, which Admins
# without Tech Ninja can read, and here that would be the SOQL and the records.
# The form stays a Drive submission, so an expired session or a lost role
# redirects the whole page.
class Admin::SalesforceQueryController < ApplicationController
  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to query Salesforce."
  # The training server's database is a redacted copy, but a build that skipped
  # the redaction, or credentials typed back in there, would reach the live org.
  before_action -> { prevent_if_ghd_server("Salesforce queries") }, only: :run

  def index; end

  def run
    query = SalesforceQuery.new(params.expect(:soql)).run

    render turbo_stream: [
      turbo_stream.update("salesforce-query-results", partial: "results", locals: { query: }),
      turbo_stream.update("live-region", helpers.salesforce_query_summary(query))
    ]
  end
end
