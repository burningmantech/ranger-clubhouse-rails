# frozen_string_literal: true

# Administration › Resource Dashboard: the CPU and memory the Fargate task
# serving the request is using, as its task metadata endpoint reports them.
# Read-only. Tech Team only, as Background Jobs is.
class Admin::ResourceDashboardController < ApplicationController
  layout "admin"

  authorize_role [Role::TECH_NINJA], message: "Tech Ninja role required to view the resource dashboard."

  def index
    @usage = FargateUsage.fetch
  rescue FargateUsage::Unavailable => e
    @error = e.message
  end
end
