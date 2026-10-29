# frozen_string_literal: true

# Me › Team Document (Ember teams-and-positions and the me/agreements "Team Info
# Documents" block): the one document a team publishes for its members, read by
# one of them. Upstream (Membership::retrieveForPerson) sends the body only to
# the person viewing themself, so membership is the whole gate -- no role, and
# not team management. The body is read here and nowhere else: the Mentor team's
# runs to megabytes, so the summary that links here never selects it.
#
# The team's resource_tag is typed in Team Records, so it is followed only
# through Document.resource_tag, as Teams & Positions › Team Documents follows
# it: a pointer at a bookmark- page or a document the code reads by name is no
# team document.
class Me::TeamDocumentsController < ApplicationController
  layout "me"

  def show
    @team = current_user.team.find(params.expect(:id))
    tag = Document.resource_tag(@team.resource_tag)
    @document = Document.find_by(tag:) if tag
    # Reached from Operational Summary or from Me › Agreements, and returned only to
    # one of those two: `from` is a whitelist, never the referer.
    @back_to = params[:from] == "agreements" ? ["Agreements", me_agreements_path]
                                             : ["Operational Summary", me_operational_summary_path]
  end
end
