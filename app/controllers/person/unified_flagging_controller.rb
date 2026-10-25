# frozen_string_literal: true

# Admin "unified flagging" page: a PNV's per-team (Personnel/RRN/VC/Mentor)
# notes and ranks, training & alpha shift history, and known rangers/PNVs.
class Person::UnifiedFlaggingController < ApplicationController
  layout "person"

  include PersonConcern

  # Narrows the broad person-page gate applied by PersonConcern.
  authorize_role [Role::ADMIN, Role::INTAKE, Role::REGIONAL_MANAGEMENT],
                 message: "Admin, Intake, or Regional Management role required to view intake records."

  before_action :ensure_can_update_known_folks, only: [:update_known_folks]

  def show
    @rrn_only = rrn_only?
    @history = Intake.history_for_person(@person, Current.year, rrn_only: @rrn_only)
    @can_edit_known_folks = has_role?([Role::ADMIN, Role::VC, Role::INTAKE])
  end

  def update_known_folks
    if @person.update(known_folks_params)
      redirect_to person_unified_flagging_path(@person), success: "Known Rangers/PNVs updated."
    else
      redirect_to person_unified_flagging_path(@person), error: "Unable to update Known Rangers/PNVs."
    end
  end

  private

  # Regional Management without either Intake or Admin sees the RRN-only
  # restricted view (see .scratch/unified-flagging/PRD.md permission matrix).
  def rrn_only?
    has_role?(Role::REGIONAL_MANAGEMENT) && !has_role?(Role::ADMIN) && !has_role?(Role::INTAKE)
  end

  def ensure_can_update_known_folks
    return if has_role?([Role::ADMIN, Role::VC, Role::INTAKE])

    redirect_to person_unified_flagging_path(@person), error: "Not authorized"
  end

  def known_folks_params
    params.expect(person: [:known_rangers, :known_pnvs])
  end
end
