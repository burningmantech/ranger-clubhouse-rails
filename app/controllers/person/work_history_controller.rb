# frozen_string_literal: true

# A person's on-playa volunteer history across all years — total hours by
# position and by year, with drill-down breakdown pages (provided by
# WorkHistoryConcern) for a single position/year cell, an entire position,
# or an entire year.
#
# Ported from the Laravel TimesheetController#index (wh_training_id query)
# and the Ember WorkHistoryComponent's three drill-downs. Access
# mirrors the PHP TimesheetPolicy#index.
class Person::WorkHistoryController < ApplicationController
  layout "person"

  include PersonConcern
  include WorkHistoryConcern

  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::TIMESHEET_MANAGEMENT],
                 message: "Event Management or Timesheet Management role required to view work history."

  def index
    @is_me = (current_user.id == @person.id)
  end
end
