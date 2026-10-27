# frozen_string_literal: true

# Me › Team Document (Ember teams-and-positions and the me/agreements "Team Info
# Documents" block): the one document a team publishes for its members, read by
# one of them. Upstream (Membership::retrieveForPerson) sends the body only to
# the person viewing themself, so membership is the whole gate -- no role, and
# not team management. The body is read here and nowhere else: the Mentor team's
# runs to megabytes, so the summary that links here never selects it.
class Me::TeamDocumentsController < ApplicationController
  layout "me"

  def show
    @team = current_user.team.find(params.expect(:id))
    @document = Document.find_by(tag: @team.resource_tag) if @team.resource_tag.present?
  end
end
