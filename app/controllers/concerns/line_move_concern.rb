# frozen_string_literal: true

# The move that puts one row of an ordered line (SortIndexLine) one place up or
# down: a PATCH carrying direction=up|down, answered with a redirect to the page
# the reader moved it from.
module LineMoveConcern
  extend ActiveSupport::Concern

  private

  # One step up or down, and back to back_to either way. A row already at that
  # end, or a direction that is neither, changes nothing and says so.
  def move_in_line(record, back_to, moved_message, at_end_message)
    if record.move(params[:direction])
      redirect_to back_to, success: moved_message
    else
      redirect_to back_to, info: at_end_message
    end
  end
end
