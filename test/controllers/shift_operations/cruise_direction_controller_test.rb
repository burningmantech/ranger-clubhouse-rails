# frozen_string_literal: true

require "test_helper"

# Cruise Direction: the shift picker, the pod board, and every write that
# changes it.
class ShiftOperations::CruiseDirectionControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025
  DENY_MESSAGE = "Admin or Pod Management role required to manage Cruise Direction pods."

  setup do
    # Noon, an hour into the shift below.
    travel_to Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @dirt = Position.create!(id: Position::DIRT, title: "Dirt", type: Position::TYPE_FRONTLINE,
                             active: true, cruise_direction: true)
    @green_dot = Position.create!(id: Position::DIRT_GREEN_DOT, title: "Dirt - Green Dot",
                                  type: Position::TYPE_FRONTLINE, active: true, cruise_direction: true)
    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)

    @slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 26, 11, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 17, 0, 0), description: "Dirt shift")
    @later_slot = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 26, 17, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 23, 0, 0), description: "Evening dirt")
    # Not a dirt shift: its pods belong to the Alpha Pod Management page.
    @alpha_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                              ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Alpha walk")

    @admin = person(:auditor_ranger)
    @pod_manager = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::POD_MANAGEMENT, "Pod Management")
    ensure_role(Role::VC_INTERFACE, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@pod_manager, Role::POD_MANAGEMENT)
    grant_role(@outsider, Role::VC_INTERFACE)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization ---

  test "an admin can view the board" do
    sign_in_as(@admin)
    get shift_operations_cruise_direction_path(year: YEAR)
    assert_response :success
  end

  test "a pod manager can view the board" do
    sign_in_as(@pod_manager)
    get shift_operations_cruise_direction_path(year: YEAR)
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get shift_operations_cruise_direction_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "a role outside the gate cannot write either" do
    sign_in_as(@outsider)

    assert_no_difference "Pod.count" do
      post shift_operations_cruise_direction_pods_path(slot_id: @slot.id, year: YEAR)
    end

    assert_redirected_to me_root_path
  end

  # The date lookup answers with a shift's id, so it has to sit behind the gate.
  test "a role outside the gate learns nothing from a date" do
    sign_in_as(@outsider)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26 18:30")

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # --- the shift picker ---

  test "the page opens on the shift that is running now" do
    pod = Pod.create_shift_pod!(@slot, location: "Esplanade & 3:00")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(year: YEAR)

    assert_response :success
    assert_select "#cruise-direction-board"
    assert_match "Esplanade &amp; 3:00", response.body
    assert_select "option[selected][value=?]", @slot.id.to_s
    assert_equal 1, pod.reload.sort_index
  end

  test "a chosen shift wins over the one running now" do
    Pod.create_shift_pod!(@later_slot, location: "Evening post")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @later_slot.id, year: YEAR)

    assert_response :success
    assert_match "Evening post", response.body
  end

  # Someone building the next shift's pods before it starts stays on it.
  test "Refresh keeps a shift picked from the list" do
    sign_in_as(@admin)
    get shift_operations_cruise_direction_path(slot_id: @later_slot.id, year: YEAR)

    get assert_select("a", text: "Refresh").first["href"]

    assert_select "option[selected][value=?]", @later_slot.id.to_s
  end

  # The page is left open for hours, so on the running shift Refresh follows
  # the clock rather than holding on to a shift that has since ended.
  test "Refresh moves on from the running shift once it ends" do
    sign_in_as(@admin)
    get shift_operations_cruise_direction_path(year: YEAR)
    refresh = assert_select("a", text: "Refresh").first["href"]

    travel_to Time.zone.local(YEAR, 8, 26, 18, 0, 0)
    get refresh

    assert_select "option[selected][value=?]", @later_slot.id.to_s
  end

  # Asked for a shift this page does not manage, it shows no board rather than
  # quietly swapping in a different shift's pods.
  test "an Alpha shift cannot be picked from this page" do
    Pod.create_shift_pod!(@slot, location: "Esplanade & 3:00")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @alpha_slot.id, year: YEAR)

    assert_response :success
    assert_no_match(/Alpha walk/, response.body, "an Alpha shift is not in the picker")
    assert_select "#cruise-direction-board", false, "no pods are shown for an unmanaged shift"
    assert_match "Pick a shift", response.body
  end

  test "a year with no dirt shifts says so" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(year: YEAR - 1)

    assert_response :success
    assert_match "No dirt shifts were scheduled for #{YEAR - 1}", response.body
  end

  # The year selector's GET carries only the year, so the shift is dropped --
  # which is right, because a shift from one year is not in another year's list.
  test "changing the year outside the event asks for a shift" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(year: YEAR - 1)

    assert_response :success
    assert_no_match(/cruise-direction-board/, response.body)
  end

  # --- a date in the link ---

  # Noon is an hour into @slot, so landing on the evening shift is the date's
  # doing rather than the clock's.
  test "a date opens the shift it lands in" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26 18:30")

    assert_redirected_to shift_operations_cruise_direction_path(slot_id: @later_slot.id, year: YEAR)
  end

  # The date names its year: nothing else in this request says which one.
  test "a date in an earlier year opens that year's shift" do
    earlier = create_slot(@dirt, begins: Time.zone.local(YEAR - 1, 8, 27, 11, 0, 0),
                          ends: Time.zone.local(YEAR - 1, 8, 27, 17, 0, 0), description: "Last year's dirt")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR - 1}-08-27T12:00")

    assert_redirected_to shift_operations_cruise_direction_path(slot_id: earlier.id, year: YEAR - 1)
  end

  # No board at all, rather than the running shift's pods under an error about
  # some other time.
  test "a date no dirt shift covers says so and shows no board" do
    Pod.create_shift_pod!(@slot, location: "Esplanade & 3:00")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26 03:00")

    assert_response :success
    assert_equal "No dirt shift was found for Tue Aug 26, #{YEAR} @ 03:00. Pick a shift from the list.",
                 flash[:error]
    assert_select "#cruise-direction-board", false
    assert_match "Pick a shift to see the pods", response.body
  end

  # A year before the pod tables begin -- with a dirt shift that does cover the
  # moment -- a day no calendar has, words, and a value that is not text. Each
  # is told the same thing, and none of them raises or redirects.
  test "a date this page cannot use is not found either" do
    create_slot(@dirt, begins: Time.zone.local(2019, 8, 27, 11, 0, 0),
                ends: Time.zone.local(2019, 8, 27, 17, 0, 0), description: "Before the floor")
    sign_in_as(@admin)

    {
      "2019-08-27 12:00" => "Tue Aug 27, 2019 @ 12:00",
      "#{YEAR}-02-30 12:00" => "that date",
      "#{YEAR}-08-26 25:00" => "that date",
      "#{YEAR}-08-26 garbage" => "that date",
      # Ruby would read this one as the 8th of May.
      "8/5/#{YEAR} 12:00" => "that date",
      "next tuesday" => "that date",
      { a: "b" } => "that date"
    }.each do |date, stamp|
      get shift_operations_cruise_direction_path(date:)

      assert_response :success, "date=#{date.inspect}"
      assert_equal "No dirt shift was found for #{stamp}. Pick a shift from the list.", flash[:error]
      assert_select "#cruise-direction-board", false
    end
  end

  # Real dirt shifts overlap across a handover, and the incoming shift wins.
  test "a date inside a handover opens the later shift" do
    incoming = create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 26, 16, 30, 0),
                           ends: Time.zone.local(YEAR, 8, 26, 22, 0, 0), description: "Incoming dirt")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26 16:45")

    assert_redirected_to shift_operations_cruise_direction_path(slot_id: incoming.id, year: YEAR)
  end

  # Read as midnight, the bare date would open the overnight shift instead.
  test "a date without a time opens the first shift beginning that day" do
    create_slot(@dirt, begins: Time.zone.local(YEAR, 8, 25, 22, 0, 0),
                ends: Time.zone.local(YEAR, 8, 26, 4, 0, 0), description: "Overnight dirt")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26")

    assert_redirected_to shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)
  end

  test "a date without a time on a day no shift begins says so" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR}-08-24")

    assert_equal "No dirt shift was found for Sun Aug 24, #{YEAR}. Pick a shift from the list.", flash[:error]
  end

  # A shift's times are wall clock, so the digits decide: converting either of
  # these by its offset would land on another shift or on none. The last is
  # what an unescaped "+" arrives as.
  test "seconds and an offset on a date are ignored" do
    sign_in_as(@admin)

    ["T18:30:00-04:00", "T18:30:00Z", " 18:30:00 -0700", "T18:30:00.000 00:00"].each do |clock|
      get shift_operations_cruise_direction_path(date: "#{YEAR}-08-26#{clock}")

      assert_redirected_to shift_operations_cruise_direction_path(slot_id: @later_slot.id, year: YEAR),
                           "date=#{YEAR}-08-26#{clock}"
    end
  end

  test "a date that finds nothing shows no board even beside a shift id" do
    Pod.create_shift_pod!(@slot, location: "Esplanade & 3:00")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @slot.id, date: "#{YEAR}-08-26 03:00")

    assert_response :success
    assert_match "No dirt shift was found for", flash[:error]
    assert_select "#cruise-direction-board", false
  end

  # "The list" in the message has to be the one the reader was after.
  test "a date that finds nothing shows its own year's shifts" do
    earlier = create_slot(@dirt, begins: Time.zone.local(YEAR - 1, 8, 27, 11, 0, 0),
                          ends: Time.zone.local(YEAR - 1, 8, 27, 17, 0, 0), description: "Last year's dirt")
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR - 1}-07-04 12:00")

    assert_response :success
    assert_equal "No dirt shift was found for Thu Jul 4, #{YEAR - 1} @ 12:00. Pick a shift from the list.",
                 flash[:error]
    assert_select "select[name=slot_id] option[value=?]", earlier.id.to_s
    assert_select "select[name=slot_id] option[value=?]", @slot.id.to_s, false
    assert_select "select[name=year] option[selected][value=?]", (YEAR - 1).to_s
  end

  test "a date in a year with no dirt shifts does not point at a list" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(date: "#{YEAR - 1}-07-04 12:00")

    assert_response :success
    assert_equal "No dirt shift was found for Thu Jul 4, #{YEAR - 1} @ 12:00.", flash[:error]
    assert_match "No dirt shifts were scheduled for #{YEAR - 1}", response.body
  end

  # An Array is not blank and does not answer to_i.
  test "a shift id that is not text selects nothing rather than raising" do
    sign_in_as(@admin)

    [["1"], { a: "1" }].each do |slot_id|
      get shift_operations_cruise_direction_path(slot_id:, year: YEAR)

      assert_response :success, "slot_id=#{slot_id.inspect}"
      assert_select "#cruise-direction-board", false
    end
  end

  # --- the board ---

  test "the board shows each pod with its Rangers and how they get around" do
    pod = Pod.create_shift_pod!(@slot, location: "Center Camp", transport: Pod::TRANSPORT_BICYCLE)
    firecracker = signed_in("Firecracker", @dirt)
    pod.add_person!(firecracker)
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    assert_response :success
    assert_select "h2", text: "Pod 1"
    assert_match "Center Camp", response.body
    assert_match "Bike Mobile", response.body
    assert_match firecracker.callsign, response.body
  end

  test "a shift with no pods says so" do
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    assert_response :success
    assert_match "No pods have gone out on this shift yet", response.body
  end

  test "the board counts and names the people no one has picked up" do
    signed_in("Hazmat", @green_dot)
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    assert_response :success
    assert_match "Waiting for a pod", response.body
    assert_match "Hazmat", response.body
  end

  test "every pod card carries the drag target its position is reported to" do
    pod = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    get shift_operations_cruise_direction_path(slot_id: @slot.id, year: YEAR)

    assert_select "[data-controller=sortable]"
    assert_select "[data-sortable-update-url=?]",
                  shift_operations_cruise_direction_pod_position_path(pod, year: YEAR)
  end

  # --- pods ---

  test "creating a pod puts it on the end and opens the add dialog on it" do
    Pod.create_shift_pod!(@slot)
    signed_in("Firecracker", @dirt)
    sign_in_as(@admin)

    assert_difference "Pod.count", 1 do
      post shift_operations_cruise_direction_pods_path(slot_id: @slot.id, year: YEAR),
           params: { pod: { transport: Pod::TRANSPORT_VEHICLE, location: "9:00 Plaza" } },
           as: :turbo_stream
    end

    assert_response :success
    pod = Pod.shift_pods_for(@slot).last

    assert_equal 2, pod.sort_index
    assert_equal Pod::TRANSPORT_VEHICLE, pod.transport
    assert_equal "9:00 Plaza", pod.location

    assert_turbo_stream_replaces "cruise-direction-board"
    # The dialog rides back with the board: a pod is made in order to fill it.
    assert_match "Add Rangers to Pod 2", response.body
    assert_match "Firecracker", response.body
  end

  test "a pod cannot be created on a shift this page does not manage" do
    sign_in_as(@admin)

    assert_no_difference "Pod.count" do
      post shift_operations_cruise_direction_pods_path(slot_id: @alpha_slot.id, year: YEAR),
           params: { pod: { transport: Pod::TRANSPORT_FOOT } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "not a dirt shift", response.body
  end

  test "editing a pod changes where it is and how it gets around" do
    pod = Pod.create_shift_pod!(@slot, location: "Center Camp")
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_path(pod, year: YEAR),
          params: { pod: { transport: Pod::TRANSPORT_BICYCLE, location: "Esplanade" } },
          as: :turbo_stream

    assert_response :success
    assert_equal [Pod::TRANSPORT_BICYCLE, "Esplanade"], pod.reload.slice(:transport, :location).values
    assert_turbo_stream_replaces "cruise-direction-board"
  end

  test "clearing a pod's location leaves it with none" do
    pod = Pod.create_shift_pod!(@slot, location: "Center Camp")
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_path(pod, year: YEAR),
          params: { pod: { transport: pod.transport, location: "   " } }, as: :turbo_stream

    assert_nil pod.reload.location
  end

  test "deleting a pod takes its Rangers out and closes the gap" do
    first = Pod.create_shift_pod!(@slot)
    second = Pod.create_shift_pod!(@slot)
    third = Pod.create_shift_pod!(@slot)
    second.add_person!(signed_in("Firecracker", @dirt))
    sign_in_as(@admin)

    assert_difference "Pod.count", -1 do
      delete shift_operations_cruise_direction_pod_path(second, year: YEAR), as: :turbo_stream
    end

    assert_response :success
    assert_equal [1, 2], [first, third].map { |pod| pod.reload.sort_index }
    assert_empty PersonPod.where(pod_id: second.id)
    assert_match "Pod 2 was deleted", response.body
  end

  test "a pod that is already gone refuses rather than raising" do
    pod = Pod.create_shift_pod!(@slot)
    id = pod.id
    pod.destroy!
    sign_in_as(@admin)

    delete shift_operations_cruise_direction_pod_path(id, year: YEAR), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "no longer on this shift", response.body
  end

  # An Alpha pod has its own page and its own rules; this one must not be able
  # to reach it even with the right id.
  test "an Alpha pod cannot be changed through this page" do
    alpha_pod = Pod.create_alpha_set!(@alpha_slot)
    sign_in_as(@admin)

    delete shift_operations_cruise_direction_pod_path(alpha_pod, year: YEAR), as: :turbo_stream

    assert_response :unprocessable_entity
    assert Pod.exists?(alpha_pod.id)
  end

  # --- dragging a pod ---

  test "dropping a pod on a place renumbers the line" do
    first = Pod.create_shift_pod!(@slot)
    second = Pod.create_shift_pod!(@slot)
    third = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_position_path(third, year: YEAR),
          params: { position: 1 }, as: :turbo_stream

    assert_response :success
    assert_equal [1, 2, 3], [third, first, second].map { |pod| pod.reload.sort_index }
    assert_match "Pod order updated", response.body
    assert_turbo_stream_replaces "cruise-direction-board"
  end

  # The browser's idea of the order can be seconds stale, so the board is
  # redrawn either way -- but a drag that changed nothing says nothing.
  test "a pod dropped back where it started redraws without announcing anything" do
    pod = Pod.create_shift_pod!(@slot)
    Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_position_path(pod, year: YEAR),
          params: { position: 1 }, as: :turbo_stream

    assert_response :success
    assert_turbo_stream_replaces "cruise-direction-board"
    assert_no_match(/Pod order updated/, response.body)
  end

  # `pod` is written by the Laravel side too, so a line is not guaranteed to
  # run 1..N. The dialog's move buttons post a place counted along the line;
  # posting sort_index instead would land somewhere else entirely, and the
  # keyboard path is the only way to move a pod without a mouse.
  test "the move buttons post a place in the line, not a sort_index" do
    first = Pod.create_shift_pod!(@slot)
    middle = Pod.create_shift_pod!(@slot)
    last = Pod.create_shift_pod!(@slot)
    [first, middle, last].each_with_index { |pod, index| pod.update_column(:sort_index, (index + 1) * 4) }
    sign_in_as(@admin)

    get shift_operations_edit_cruise_direction_pod_path(middle, year: YEAR)

    assert_response :success
    assert_select "a[href*='position=1']", 1, "Move earlier offers the place before it, not sort_index - 1"
    assert_select "a[href*='position=3']", 1, "Move later offers the place after it"
  end

  test "a move made from the dialog leaves the dialog open on the new place" do
    Pod.create_shift_pod!(@slot)
    pod = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_position_path(pod, position: 1, from: "dialog", year: YEAR),
          as: :turbo_stream

    assert_response :success
    assert_turbo_stream_replaces "cruise-direction-board"
    assert_match "cruise-direction-pod-dialog", response.body,
                 "the dialog is redrawn rather than closed, so the next move needs no reopening"
    assert_match "is now 1 of 2", response.body
    assert_equal 1, pod.reload.sort_index
  end

  test "a drag with no place moves nothing rather than jumping to the front" do
    first = Pod.create_shift_pod!(@slot)
    last = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_position_path(last, year: YEAR), as: :turbo_stream

    assert_response :success
    assert_equal [1, 2], [first, last].map { |pod| pod.reload.sort_index }
    assert_no_match(/Pod order updated/, response.body)
  end

  # The picker only ever lists this year's active dirt shifts, so a write that
  # accepts anything else lands on a shift the page can never select again.
  test "a pod cannot be created on a shift from another year" do
    other_year = create_slot(@dirt, begins: Time.zone.local(YEAR - 1, 8, 26, 11, 0, 0),
                             ends: Time.zone.local(YEAR - 1, 8, 26, 17, 0, 0), description: "Last year")
    sign_in_as(@admin)

    assert_no_difference -> { Pod.count } do
      post shift_operations_cruise_direction_pods_path(slot_id: other_year.id, year: YEAR),
           params: { pod: { transport: Pod::TRANSPORT_FOOT } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  test "a pod on a shift the picker cannot offer is not editable either" do
    stranded = Pod.create_shift_pod!(@alpha_slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_path(stranded, year: YEAR),
          params: { pod: { location: "Anywhere" } }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_nil stranded.reload.location
  end

  test "a request that arrives without the pod's details answers with a toast" do
    pod = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_pod_path(pod, year: YEAR), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "arrived without the pod", response.body
  end

  # The counts render beside the picker, outside the cards partial, so they are
  # their own stream target. A write that replaced only the board would leave
  # them showing the shift as it was before.
  test "a write replaces the counts as well as the cards" do
    pod = Pod.create_shift_pod!(@slot)
    firecracker = signed_in("Firecracker", @dirt)
    sign_in_as(@admin)

    post shift_operations_cruise_direction_people_path(pod, year: YEAR),
         params: { person_ids: [firecracker.id] }, as: :turbo_stream

    assert_response :success
    assert_turbo_stream_replaces "cruise-direction-board"
    assert_turbo_stream_replaces "cruise-direction-stats"
    assert_match "Rangers Out", response.body
    assert_match "Signed In, No Pod", response.body
  end

  # --- pod membership ---

  test "several Rangers can be added at once" do
    pod = Pod.create_shift_pod!(@slot)
    firecracker = signed_in("Firecracker", @dirt)
    hazmat = signed_in("Hazmat", @green_dot)
    sign_in_as(@admin)

    assert_difference "PersonPod.count", 2 do
      post shift_operations_cruise_direction_people_path(pod, year: YEAR),
           params: { person_ids: [firecracker.id, hazmat.id] }, as: :turbo_stream
    end

    assert_response :success
    assert_equal 2, pod.reload.person_count
    assert_match "Firecracker and Hazmat added to Pod 1", response.body
  end

  # One refusal must not throw away the rest of the selection.
  test "someone already in another pod is refused while the rest are added" do
    first = Pod.create_shift_pod!(@slot)
    second = Pod.create_shift_pod!(@slot)
    taken = signed_in("Firecracker", @dirt)
    free = signed_in("Hazmat", @dirt)
    first.add_person!(taken)
    sign_in_as(@admin)

    assert_difference "PersonPod.count", 1 do
      post shift_operations_cruise_direction_people_path(second, year: YEAR),
           params: { person_ids: [taken.id, free.id] }, as: :turbo_stream
    end

    assert_response :success
    assert_match "Hazmat added to Pod 2", response.body
    assert_match "Firecracker is already in Pod 1", response.body
  end

  # The dialog cannot offer them, so only a replayed or hand-made request gets
  # here -- but an unchecked id would put anyone in the database into a pod.
  test "someone who never checked in for the shift cannot be added" do
    pod = Pod.create_shift_pod!(@slot)
    stranger = create_person("Bystander")
    sign_in_as(@admin)

    assert_no_difference "PersonPod.count" do
      post shift_operations_cruise_direction_people_path(pod, year: YEAR),
           params: { person_ids: [stranger.id] }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "Bystander is not checked in for this shift", response.body
  end

  # The select-all toggle is the only element carrying the controller's toggle
  # target, so a dialog offering nothing but earlier check-ins must still
  # render it or Stimulus throws on connect.
  test "the add dialog keeps its select-all when everyone checked in early" do
    pod = Pod.create_shift_pod!(@slot)
    person = create_person("Riverbed")
    Timesheet.create!(person_id: person.id, position_id: @dirt.id,
                      on_duty: @slot.begins - 2.hours, additional_notes: "a prior shift")
    sign_in_as(@admin)

    get shift_operations_new_cruise_direction_person_path(pod, year: YEAR)

    assert_response :success
    assert_select "[data-checkbox-select-all-target=toggle]"
    assert_match "Riverbed", response.body
    assert_match "Checked In Earlier", response.body
  end

  test "adding no one is refused" do
    pod = Pod.create_shift_pod!(@slot)
    sign_in_as(@admin)

    post shift_operations_cruise_direction_people_path(pod, year: YEAR),
         params: { person_ids: [] }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "Pick at least one callsign", response.body
  end

  # ActiveRecord reads "#{id}x" as the id, which put that Ranger in the pod.
  test "person ids that are not ids add no one" do
    pod = Pod.create_shift_pod!(@slot)
    firecracker = signed_in("Firecracker", @dirt)
    sign_in_as(@admin)

    assert_no_difference "PersonPod.count" do
      post shift_operations_cruise_direction_people_path(pod, year: YEAR),
           params: { person_ids: ["", "abc", "#{firecracker.id}x"] }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "Pick at least one callsign", response.body
  end

  test "the add dialog offers the people no one has picked up" do
    pod = Pod.create_shift_pod!(@slot)
    signed_in("Firecracker", @dirt)
    sign_in_as(@admin)

    get shift_operations_new_cruise_direction_person_path(pod, year: YEAR)

    assert_response :success
    assert_match "Firecracker", response.body
    assert_select "input[name='person_ids[]']"
  end

  # The same request the relocate select sends, which is what makes the drag
  # and the keyboard path one code path.
  test "a Ranger dragged onto another pod moves there" do
    first = Pod.create_shift_pod!(@slot)
    second = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt)
    first.add_person!(person)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_person_path(first, person, year: YEAR),
          params: { new_pod_id: second.id }, as: :turbo_stream

    assert_response :success
    assert_equal 0, first.reload.person_count
    assert_equal 1, second.reload.person_count
    assert_match "Firecracker moved to Pod 2", response.body
    # The row they left is kept, stamped -- who was in which pod stays
    # answerable after the event.
    assert PersonPod.where(pod_id: first.id, person_id: person.id).where.not(removed_at: nil).exists?
  end

  test "a Ranger dropped back on their own pod is left alone" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt)
    pod.add_person!(person)
    sign_in_as(@admin)

    assert_no_difference "PersonPod.count" do
      patch shift_operations_cruise_direction_person_path(pod, person, year: YEAR),
            params: { new_pod_id: pod.id }, as: :turbo_stream
    end

    assert_response :success
    assert_match "already in Pod 1", response.body
  end

  test "taking a Ranger out of a pod keeps the record and disbands an empty pod" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt)
    pod.add_person!(person)
    sign_in_as(@admin)

    assert_no_difference "PersonPod.count", "the row is stamped, not deleted" do
      delete shift_operations_cruise_direction_person_path(pod, person, year: YEAR), as: :turbo_stream
    end

    assert_response :success
    assert_equal 0, pod.reload.person_count
    assert_predicate pod, :disbanded?
    assert_match "Firecracker was taken out of Pod 1", response.body
  end

  test "the member dialog lists the other pods to move to" do
    first = Pod.create_shift_pod!(@slot)
    Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt)
    first.add_person!(person)
    sign_in_as(@admin)

    get shift_operations_edit_cruise_direction_person_path(first, person, year: YEAR)

    assert_response :success
    assert_select "select#new_pod_id option", count: 2
  end

  # Someone else took them out while this board sat on screen.
  # The dialog can be open while another operator takes the same person out.
  # Answering "already in Pod 1" would assert they are still there, while the
  # board redrawn under the toast shows them gone.
  test "moving a Ranger another operator already removed says so" do
    pod = Pod.create_shift_pod!(@slot)
    firecracker = signed_in("Firecracker", @dirt)
    pod.add_person!(firecracker)
    pod.remove_person!(firecracker)
    sign_in_as(@admin)

    patch shift_operations_cruise_direction_person_path(pod, firecracker, year: YEAR),
          params: { new_pod_id: pod.id }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match "no longer in Pod 1", response.body
    assert_no_match(/already in/, response.body)
  end

  test "opening the dialog for a Ranger who has left says so" do
    pod = Pod.create_shift_pod!(@slot)
    person = signed_in("Firecracker", @dirt)
    sign_in_as(@admin)

    get shift_operations_edit_cruise_direction_person_path(pod, person, year: YEAR),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_match "no longer in this pod", response.body
  end

  private

  # The board partial carries its own root id, so it is replaced, never
  # updated -- an update would nest the board inside itself and leave two
  # elements with one id.
  def assert_turbo_stream_replaces(target)
    assert_select "turbo-stream[action=replace][target=?]", target
  end

  def signed_in(callsign, position)
    person = create_person(callsign)
    Timesheet.create!(person_id: person.id, position_id: position.id, on_duty: @slot.begins,
                      additional_notes: "signed in for the shift")
    person
  end
end
