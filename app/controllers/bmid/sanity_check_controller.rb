# frozen_string_literal: true

# BMID > Sanity Check: the read-only report of shift sign-ups that disagree
# with SAP and Staff Credential access dates (Ember vc/bmid-sanity-check
# port). It lives with the other badge pages: the audience and the fix-it
# tooling are both here, not under /vc.
class Bmid::SanityCheckController < ApplicationController
  layout "bmid"

  authorize_role [Role::ADMIN, Role::EDIT_BMIDS],
                 message: "Admin or Edit BMIDs role required to manage BMIDs."

  # The checks compare sign-ups with the access documents and the box office
  # date as they stand today, so a past year would be checked against this
  # year's. Only the current year is checked, and params[:year] is ignored.
  def index
    @year = current_year
    @report = BmidSanityCheckReport.execute(@year)
    # Validated against the report's own key list -- the set findings will
    # dispatch on. Unknown values (including the "all" sentinel) mean no
    # filter; downstream code speaks symbols.
    @check = params[:check].presence_in(BmidSanityCheckReport::CHECK_KEYS.map(&:to_s))&.to_sym
    @findings = @report.findings(check: @check)
  end
end
