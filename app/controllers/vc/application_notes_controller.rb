# frozen_string_literal: true

# Notes (VC comments and Unified Flagging notes) on a prospective application.
class Vc::ApplicationNotesController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to manage applications."

  before_action :set_application

  def create
    ProspectiveApplicationNote.create!(
      prospective_application: @application,
      person_id: current_user.id,
      note: params.expect(:note),
      type: params.expect(:type))

    redirect_to vc_application_path(@application), success: "Note added."
  end

  def update
    note = ProspectiveApplicationNote.find_note_for_application!(@application.id, params[:id])
    note.update!(note: params.expect(:note))

    redirect_to vc_application_path(@application), success: "Note updated."
  end

  def destroy
    note = ProspectiveApplicationNote.find_note_for_application!(@application.id, params[:id])
    note.destroy

    redirect_to vc_application_path(@application), success: "Note deleted."
  end

  private

  def set_application
    @application = ProspectiveApplication.find(params[:application_id].to_s.sub(/\A[Aa]-/, ""))
  rescue ActiveRecord::RecordNotFound
    redirect_to vc_applications_path, error: "Application not found."
  end
end
