class Me::MissingRequestsController < ApplicationController
  include TimesheetDashboardConcern
  include TimesheetConcern
  include MissingRequestsConcern

  layout "me/timesheet"
end
