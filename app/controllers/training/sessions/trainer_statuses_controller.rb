# frozen_string_literal: true

# Bulk save of the trainer attendance table (Laravel trainerStatus). The lib
# skips rows that fell out of sync with the matched trainer slots or their
# rosters.
class Training::Sessions::TrainerStatusesController < Training::Sessions::BaseController
  def update_all
    @training_session.save_trainer_statuses!(submitted_rows)

    redirect_to session_return_path, success: "Trainer attendance updated."
  end

  private

  # Anything that is not a row of attributes is dropped rather than raising:
  # this hash comes off the wire.
  def submitted_rows
    rows = params[:trainers]
    return [] unless rows.respond_to?(:each_value)

    rows.each_value.filter_map do |row|
      row.permit(:person_id, :trainer_slot_id, :status, :is_lead).to_h.symbolize_keys if row.respond_to?(:permit)
    end
  end
end
