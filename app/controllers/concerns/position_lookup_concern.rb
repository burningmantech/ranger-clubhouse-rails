# frozen_string_literal: true

# Loading the position named in the URL, for the pages that drill into one.
#
# The including page says only where to send a reader whose position could not
# be loaded. How it is looked up, and what the reader is told, are the same
# everywhere and are settled here.
#
# Only for pages taking `:position_id` and sending the reader back to a list.
# A page that lets the position be missing, looks it up by another key, or picks
# it from a list the reader is allowed to manage is doing something else and
# writes its own.
module PositionLookupConcern
  extend ActiveSupport::Concern

  # One wording wherever a position cannot be shown, so a position that never
  # existed cannot be told apart from one this reader may not see.
  POSITION_NOT_FOUND = "The position could not be found."

  private

  def set_position
    @position = Position.find_by(id: params[:position_id])
    return if @position

    # position_not_found_path is the including page's to define: where a reader
    # goes when the position could not be loaded. There is no default worth
    # guessing, and leaving it out raises by its own name.
    redirect_to position_not_found_path, error: POSITION_NOT_FOUND
  end
end
