# frozen_string_literal: true

# Teams & Positions › Team Documents (Ember ops/team-resources): the one
# document each team writes for its members, kept by the team's managers.
#
# No authorize_role here, as on Roster Management: the gate is a role, then
# Admin or another role plus a team_manager row, which a flat role list cannot
# say, so authorized_roles stays nil and these before_actions answer it.
# Team.resource_manageable_by is the rule; the menu asks its ? twin. The first
# gate is unconditional so an action added later cannot ship open.
#
# Reading and writing are one permission here, unlike Trainer Resources (where
# the whole training interface reads and only the resource role writes): the
# read page is the manager's preview of what members will see.
class TeamsPositions::TeamDocumentsController < ApplicationController
  layout "teams_positions"

  before_action :require_team_document_manager
  before_action :set_team, except: :index

  # Below this controller's gates, so their messages are the ones a refused
  # reader gets; the concern's own write gate, which this include registers,
  # then never refuses anyone they let through.
  include ResourceDocumentCrudConcern

  def index
    @teams = Team.resource_manageable_by(Current.person).order(:title).to_a
    @manages_all = Team.resource_manages_every_team?(Current.person)
    # Without the body: the Mentor Team's runs to megabytes, and a list shows
    # none of it.
    @documents = Document.listed_by_pointer(@teams.map(&:resource_tag))
  end

  def show
    @document = find_resource_document
  end

  private

  def require_team_document_manager
    return if Team.resource_manageable_by?(Current.person)

    not_authorized_redirect("Team Documents needs Event Management or Vehicle Info Update, and either Admin " \
                            "or the Team Resource Doc Mgmt permission with a team to manage.")
  end

  # An Admin reaches every team, so a team they cannot find is gone. Anyone
  # else is refused without being told whether it exists, as on Roster
  # Management.
  def set_team
    return if resource_entity

    if Team.resource_manages_every_team?(Current.person)
      redirect_to teams_positions_team_documents_path, error: "That team no longer exists."
    else
      not_authorized_redirect("That team's document is not available to you.")
    end
  end

  # --- ResourceDocumentCrudConcern hooks ---

  # Found on first ask, through the one rule (Team.resource_manageable_by: the
  # ops-area roles, then Laravel's retrieveResourceEntity team branch), so every
  # callback that asks gets the same answer.
  def resource_entity
    return @team if defined?(@team)

    @team = Team.resource_manageable_by(Current.person).find_by(id: params[:team_id])
  end

  def can_manage_resource? = resource_entity.present?

  def resource_show_path = teams_positions_team_document_path(@team)

  def resource_return_label = @team.title

  def resource_form_path = teams_positions_team_document_path(@team)

  def resource_document_label = "team document"
end
