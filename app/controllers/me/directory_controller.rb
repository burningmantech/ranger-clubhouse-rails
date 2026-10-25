class Me::DirectoryController < ApplicationController
  layout "me"

  def index
    @teams = DirectoryReport.execute
    @scroll_to_teams = @teams.map do |team|
      OpenStruct.new(id: "team-#{team.id}", title: team.title)
    end
  end
end
