# frozen_string_literal: true

# The ROC wall display: who is on duty right now, shown as photos
# large enough to read from across the room.
#
# No one stands at this page. It is opened on a monitor and left alone, so it
# refreshes and scrolls itself -- see the photo-board Stimulus controller.
class ShiftOperations::RocPhotoBoardController < ApplicationController
  # Not the shift_operations layout: this page carries no navbar, no sidebar,
  # and no menus. The whole screen is the board. `board` opts out again with
  # `render layout: false`, since it answers into a page that is already up.
  layout "photo_board"

  # Nothing on this page draws a menu, and the display asks for the board again
  # every five minutes for as long as it is up. No sense building navigation
  # no one can reach, once an hour, forever.
  skip_before_action :build_menu_items

  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required to view the " \
                          "ROC Photo Board."

  def index
    @board = RocPhotoBoardReport.execute
  end

  # The board by itself, for the display to pull in on its own timer. No
  # layout: the answer is dropped into the page already on the monitor.
  def board
    @board = RocPhotoBoardReport.execute
    render layout: false
  end
end
