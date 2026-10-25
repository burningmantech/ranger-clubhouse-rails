# frozen_string_literal: true

# HQ-scoped twin of Me::MissingRequestsController — missing timesheet requests
# submitted at the window on the person's behalf. The request belongs to the
# person; create_person_id records the operator who typed it in.
class Hq::MissingRequestsController < ApplicationController
  include HqTimesheetConcern
  include MissingRequestsConcern
end
