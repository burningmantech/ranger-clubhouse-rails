# frozen_string_literal: true

require "test_helper"

class ShiftOperations::RocPhotoBoardControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include PersonPhotoTestHelper # create_photo
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031
  DENY_MESSAGE = "Admin or Event Management role required to view the " \
                 "ROC Photo Board."
  GROUP_TITLES = ["Khakis", "Troubleshooters", "Operators", "Green Dot Leads", "OODs"].freeze

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 18, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @event_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)

    @shift_lead = board_position(Position::RSC_SHIFT_LEAD, "RSC Shift Lead")
    @intake = board_position(Position::RSCI, "RSC Intake")
    @troubleshooter = board_position(Position::TROUBLESHOOTER, "Troubleshooter")
    @operator = board_position(Position::OPERATOR, "Operator")
    @operator_smooth = board_position(Position::OPERATOR_SMOOTH, "Operator (Smooth)")
    @green_dot_lead = board_position(Position::GREEN_DOT_LEAD, "Green Dot Lead")
    @ood = board_position(Position::OOD, "OOD")
    @roc_star = board_position(Position::ROC_STAR, "ROC Star")

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- access

  test "admin may open the board" do
    get shift_operations_roc_photo_board_path

    assert_response :success
  end

  test "event management may open the board" do
    sign_in_as(@event_manager)

    get shift_operations_roc_photo_board_path

    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get shift_operations_roc_photo_board_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # Timesheet Management reads the other on-duty pages, so it is the gate a
  # reader would expect to work here.
  test "timesheet management alone does not reach the board" do
    grant_role(@outsider, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(@outsider)

    get shift_operations_roc_photo_board_path

    assert_redirected_to me_root_path
  end

  # ---------------------------------------------------------------- groups

  test "every group is drawn in order even with no one on duty" do
    get shift_operations_roc_photo_board_path

    assert_equal GROUP_TITLES, group_titles
    assert_select ".photo-board-empty", GROUP_TITLES.size
  end

  test "somebody on duty lands in their group with the position they are in" do
    sign_in_on_duty(@admin, @shift_lead)
    sign_in_on_duty(@event_manager, @green_dot_lead)
    sign_in_on_duty(@outsider, @ood)

    get shift_operations_roc_photo_board_path

    assert_equal [@admin.callsign], callsigns_in_group("Khakis")
    assert_equal ["RSC Shift Lead"], positions_in_group("Khakis")
    assert_equal [@event_manager.callsign], callsigns_in_group("Green Dot Leads")
    assert_equal [@outsider.callsign], callsigns_in_group("OODs")
    assert_empty callsigns_in_group("Troubleshooters")
  end

  # Two positions, one heading, one list of names -- and the names sort as a
  # reader reads them, not by which position they came from.
  # The pair is chosen so plain sorting would answer the other way round: an
  # upper-case Z sorts before a lower-case b until case stops counting.
  test "a group merges its positions into one callsign order, ignoring case" do
    sign_in_on_duty(create_person("Zulu"), @operator)
    sign_in_on_duty(create_person("banjo"), @operator_smooth)

    get shift_operations_roc_photo_board_path

    assert_equal ["banjo", "Zulu"], callsigns_in_group("Operators")
  end

  test "a shift that has been signed out is off the board" do
    sign_in_on_duty(@admin, @ood, on_duty: @now - 3.hours, off_duty: @now - 1.hour)

    get shift_operations_roc_photo_board_path

    assert_empty callsigns_in_group("OODs")
  end

  # A sign-in no one ever closed would otherwise stand on the wall forever as
  # somebody still out there.
  test "a sign-in left open since a past event is off the board" do
    sign_in_on_duty(@admin, @ood, on_duty: @now - 20.days)

    get shift_operations_roc_photo_board_path

    assert_empty callsigns_in_group("OODs")
  end

  # The same fault from the other side: a start time mistyped into a future year
  # is no one who is on duty now, and sitting above the floor rather than below
  # it, it would never age off the wall either.
  test "a sign-in stamped in the future is off the board" do
    sign_in_on_duty(@admin, @ood, on_duty: @now + 3.days)

    get shift_operations_roc_photo_board_path

    assert_empty callsigns_in_group("OODs")
  end

  # Two open entries, one Ranger, one person standing in the room. Two photos of
  # them would say the group is bigger than it is.
  test "somebody signed in twice within a group gets one card" do
    sign_in_on_duty(@admin, @shift_lead)
    sign_in_on_duty(@admin, @intake)

    get shift_operations_roc_photo_board_path

    assert_equal [@admin.callsign], callsigns_in_group("Khakis")
    assert_select ".photo-board-group-count", text: "1 on duty", count: 1
  end

  # ----------------------------------------------------------------- hosts

  test "a host is listed on their own, without a position" do
    sign_in_on_duty(@admin, @roc_star)

    get shift_operations_roc_photo_board_path

    assert_equal [@admin.callsign],
                 css_select(".photo-board-host .photo-board-callsign").map { |node| node.text.strip }
    assert_select ".photo-board-host .photo-board-position", false
    assert_select ".photo-board-no-host", false
    # A host belongs to no group, so no group grew one.
    assert_equal [], GROUP_TITLES.flat_map { |title| callsigns_in_group(title) }
  end

  test "with no host on duty the board says who to ask instead" do
    get shift_operations_roc_photo_board_path

    assert_select ".photo-board-no-host", /No ROC Star is on duty/
    assert_select ".photo-board-host", false
  end

  # ---------------------------------------------------------------- photos

  test "an approved photo is shown, and a placeholder stands in without one" do
    with_photo = create_person("Pose")
    approve_photo(with_photo)
    sign_in_on_duty(with_photo, @ood)
    sign_in_on_duty(create_person("Bare"), @ood)

    get shift_operations_roc_photo_board_path

    assert_equal ["Bare", "Pose"], callsigns_in_group("OODs")
    assert_select ".photo-board-card img.photo-board-photo", 1
    assert_select ".photo-board-card .photo-board-photo-missing", 1
  end

  # An unapproved photo is not the person's photo, so the card falls back the
  # same way it does for somebody who has never sent one in.
  test "a photo still awaiting review does not reach the board" do
    waiting = create_person("Pending")
    # The image is attached, exactly as an approved one would be, so the only
    # thing keeping this face off the wall is that no one has passed it yet.
    approve_photo(waiting, status: PersonPhoto::SUBMITTED)
    sign_in_on_duty(waiting, @ood)

    get shift_operations_roc_photo_board_path

    assert_select ".photo-board-photo-missing", 1
    assert_select "img.photo-board-photo", false
  end

  # ----------------------------------------------------------------- kiosk

  # Named against what the ordinary layout actually renders. An id nothing in
  # the app emits would pass just as happily with the full navbar, sidebar and
  # modal frame wrapped around the board.
  test "the board carries no navigation for anyone to use" do
    get shift_operations_roc_photo_board_path

    assert_select "nav.photo-board-rail"
    assert_select "nav.navbar", false
    assert_select "turbo-frame#modal", false
    assert_select "div.drawer", false
  end

  # The next copy of the board comes from a route of its own. Named at the page
  # rather than on the frame: a frame that carries an address fetches it the
  # moment it arrives, drawing the board a second time for one page open. And
  # pointed at the page that holds it, Turbo reads the loop and empties the
  # frame -- the display goes blank and stays blank, with no one to notice.
  test "the board is refreshed from its own route, and not fetched twice on arrival" do
    get shift_operations_roc_photo_board_path

    assert_select "[data-photo-board-source-value=?]",
                  shift_operations_roc_photo_board_board_path
    assert_select "turbo-frame#photo-board:not([src])"
    assert_select "[data-photo-board-source-value=?]",
                  shift_operations_roc_photo_board_path, false
  end

  # The whole app answers turbo:frame-missing by showing the page the server
  # sent in place of the one open -- an error page, or the sign-in page. On a
  # screen no one is watching, the board would be gone for good, with no timer
  # left to try again. The kiosk base the display extends handles the event
  # itself, and the app-wide handler stands down for an event already handled.
  test "the display keeps the app-wide frame-missing visit from reaching an unattended screen" do
    javascript = Rails.root.join("app/javascript")

    assert_match(/extends Kiosk/, javascript.join("controllers/photo_board_controller.js").read)
    assert_match(/preventDefault/, javascript.join("controllers/kiosk_controller.js").read)
    assert_match(/defaultPrevented[\s\S]*visit\(/, javascript.join("application.js").read)
  end

  # Every other page swaps only the body, which would leave the board wearing
  # the theme and chrome of wherever the reader came from -- the fixed dark
  # theme lives on <html>, and a Turbo visit never replaces that.
  test "following a link to the board loads the page afresh" do
    get shift_operations_roc_photo_board_path

    assert_select "meta[name=turbo-visit-control][content=reload]", 1
  end

  test "the refresh route answers with the board and no page around it" do
    sign_in_on_duty(@admin, @ood)

    get shift_operations_roc_photo_board_board_path

    assert_response :success
    assert_equal GROUP_TITLES, group_titles
    assert_equal [@admin.callsign], callsigns_in_group("OODs")
    # The answer must not name the address it came from: Turbo reads a frame
    # whose source is the request that produced it as a loop, and throws the
    # board away rather than follow one. The display then sits blank forever,
    # with no one there to see that it did.
    assert_select "turbo-frame#photo-board:not([src])"
    # No layout: the page is already on the monitor. Asserted against the raw
    # body, because parsing a bare fragment supplies an <html> of its own.
    assert_no_match(/<body/, response.body)
  end

  test "the refresh route is behind the same gate as the board" do
    sign_in_as(@outsider)

    get shift_operations_roc_photo_board_board_path

    assert_redirected_to me_root_path
  end

  private

  def board_position(id, title)
    Position.find_by(id:) ||
      Position.create!(id:, title:, type: Position::TYPE_FRONTLINE, active: true)
  end

  def sign_in_on_duty(person, position, on_duty: @now - 1.hour, off_duty: nil)
    Timesheet.create!(person:, position:, on_duty:, off_duty:,
                      additional_notes: "test shift")
  end

  # The shared factory plus the image itself, which is what the board reads.
  def approve_photo(person, status: PersonPhoto::APPROVED)
    photo = create_photo(person:, status:, profile_filename: "p.jpg")
    photo.profile.attach(io: StringIO.new("not-really-a-jpeg"), filename: "p.jpg",
                         content_type: "image/jpeg")
    photo
  end

  def group_titles
    css_select(".photo-board-group-title").map { |node| node.text.strip }
  end

  def group_node(title)
    css_select(".photo-board-group").find do |node|
      css_select(node, ".photo-board-group-title").first&.text&.strip == title
    end
  end

  def callsigns_in_group(title)
    css_select(group_node(title), ".photo-board-callsign").map { |node| node.text.strip }
  end

  def positions_in_group(title)
    css_select(group_node(title), ".photo-board-position").map { |node| node.text.strip }
  end
end
