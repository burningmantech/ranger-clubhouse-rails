# frozen_string_literal: true

# Ticketing statistics -- where every ticket, pass, and credential stands right
# now (Ember vc/access-documents/statistics port).
#
# Upstream drew eleven one-row tables; here the same counts are a dashboard, one
# card per type showing how that type's documents divide across the claim
# pipeline. The numbers are not year-scoped, so there is no year selector.
class Ticketing::StatisticsController < ApplicationController
  layout "ticketing"

  authorize_role [Role::ADMIN, Role::EDIT_ACCESS_DOCS],
                 message: "Admin or Edit Access Documents role required to view ticketing statistics."

  def index
    @statistics = TicketingStatistics.execute
  end
end
