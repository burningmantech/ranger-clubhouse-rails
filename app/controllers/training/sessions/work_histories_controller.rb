# frozen_string_literal: true

# The per-trainee work history dialog (upstream WorkHistory component). Data comes from the shared
# WorkHistoryReport (the same report behind /person/:id/work-history), so the
# two surfaces can never disagree. The matrix's hour links re-request this
# action with detail params into an inner frame for the entry drill-down.
# Graduation-scoped: only viewers who can graduate see it.
class Training::Sessions::WorkHistoriesController < Training::Sessions::BaseController
  skip_before_action :authorize_session_management
  before_action :authorize_graduation

  def show
    @person = Person.find_by(id: params[:person_id])
    unless @person && PersonSlot.have_slot?(@person.id, @training_session.slot.id)
      return render turbo_stream: [
        ui_toast_stream("That person is not signed up for this session.", :error),
        modal_close_dialog
      ]
    end

    @history = WorkHistoryReport.execute(@person.id)
    @detail_position = @history.positions.find { |p| p.id == params[:detail_position_id].to_i } if params[:detail_position_id].present?
    @detail_year = params[:detail_year].presence&.to_i
  end
end
