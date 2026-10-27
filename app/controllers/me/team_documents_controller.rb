# frozen_string_literal: true

# Me › Team Document (Ember teams-and-positions and the me/agreements "Team Info
# Documents" block): the one document a team publishes for its members, read by
# one of them. Upstream (Membership::retrieveForPerson) sends the body only to
# the person viewing themself, so membership is the whole gate -- no role, and
# not team management. The body is read here and nowhere else: the Mentor team's
# runs to megabytes, so the summary that links here never selects it.
#
# The team's resource_tag is typed in Team Records, so it is followed only
# through Document.resource_tag, as Teams & Positions › Team Resources follows
# it: a pointer at a bookmark- page or a document the code reads by name is no
# team document.
class Me::TeamDocumentsController < ApplicationController
  layout "me"

  def show
    @team = current_user.team.find(params.expect(:id))
    tag = Document.resource_tag(@team.resource_tag)
    @document = Document.find_by(tag:) if tag
  end
end
