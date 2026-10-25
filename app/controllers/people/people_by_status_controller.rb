# frozen_string_literal: true

# Every Clubhouse account, grouped by the status it holds right now.
#
# The index counts each status; a status opens onto its own page listing the
# people who hold it. Not year-scoped -- the person table keeps no history of
# a status, only the one it holds today.
class People::PeopleByStatusController < ApplicationController
  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to view people by status."

  def index
    @counts = PeopleByStatusReport.counts
    @total = @counts.values.sum
  end

  def show
    @status = PeopleByStatusReport.find_status(params[:status])
    # An address naming no status has no one to list, so the reader is sent to
    # the one page that can tell them which statuses exist.
    return redirect_to(people_by_status_path,
                       alert: "That is not a status the Clubhouse assigns.") unless @status

    @people = PeopleByStatusReport.people(@status)
  end
end
