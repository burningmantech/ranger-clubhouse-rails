# frozen_string_literal: true

require "test_helper"

# Alpha Pod Management: the shift list, the pod board, and every write that
# changes it.
class Mentoring::AlphaPodsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include TrainingSlotTestHelper
  include PersonTestFactory
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2025
  DENY_MESSAGE = "Admin or Mentor role required to manage Alpha pods."

  setup do
    travel_to Time.zone.local(YEAR, 8, 25, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @alpha_position = Position.create!(id: Position::ALPHA, title: "Alpha",
                                       type: Position::TYPE_FRONTLINE, active: true)
    @mentor_position = Position.create!(id: Position::MENTOR, title: "Mentor",
                                        type: Position::TYPE_MENTORING, active: true)
    Position.create!(id: Position::MENTOR_MITTEN, title: "Mentor Mitten",
                     type: Position::TYPE_MENTORING, active: true)

    @slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 26, 7, 0, 0),
                        ends: Time.zone.local(YEAR, 8, 26, 13, 0, 0), description: "Alpha walk one")
    @inactive_slot = create_slot(@alpha_position, begins: Time.zone.local(YEAR, 8, 27, 7, 0, 0),
                                 ends: Time.zone.local(YEAR, 8, 27, 13, 0, 0),
                                 description: "Dormant walk", active: false)
    @mentor_slot = create_slot(@mentor_position, begins: Time.zone.local(YEAR, 8, 26, 7, 30, 0),
                               ends: Time.zone.local(YEAR, 8, 26, 13, 30, 0), description: "Mentor shift")

    # Fresh people: person_mentor.yml pre-seeds bonk history for several
    # fixture people, which would show up in the pod chips.
    @alpha = create_person("PodAlphaOne", status: Person::ALPHA)
    @other_alpha = create_person("PodAlphaTwo", status: Person::ALPHA)
    @cadre_mentor = create_person("PodMentorOne")

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization ---

  test "an admin can view the shift list" do
    sign_in_as(@admin)
    get mentoring_alpha_pods_path(year: YEAR)
    assert_response :success
  end

  test "a mentor can view the shift list" do
    sign_in_as(@mentor)
    get mentoring_alpha_pods_path(year: YEAR)
    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)
    get mentoring_alpha_pods_path(year: YEAR)
    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "a role outside the gate cannot write either" do
    sign_in_as(@outsider)
    assert_no_difference "Pod.count" do
      post mentoring_alpha_pods_pods_path(@slot)
    end
    assert_redirected_to me_root_path
  end

  # --- the shift list ---

  test "only active shifts of the chosen year are listed, with their pod counts" do
    Pod.create_alpha_set!(@slot)
    sign_in_as(@mentor)

    get mentoring_alpha_pods_path(year: YEAR)

    assert_response :success
    assert_match "Alpha walk one", response.body
    assert_no_match(/Dormant walk/, response.body, "inactive shifts have nothing to manage")
    assert_match "1 pod", response.body
  end

  test "a year with no shifts says so" do
    sign_in_as(@mentor)
    get mentoring_alpha_pods_path(year: YEAR - 1)
    assert_response :success
    assert_match "No active Alpha shifts", response.body
  end

  # --- the board ---

  test "the board shows each pod with its three groups" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@cadre_mentor, is_lead: true)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)
    sign_in_as(@mentor)

    get mentoring_alpha_pods_shift_path(@slot)

    assert_response :success
    assert_match @cadre_mentor.callsign, response.body
    assert_match @alpha.callsign, response.body
    assert_match "Lead", response.body

    # Asserted against the card's own markup, not the whole body: the hero
    # description and the callout both name all three groups, so a bare
    # assert_match would pass on a page with no pods at all.
    assert_select "h2", text: "Pod 1"
    assert_select "h3", text: /Mentors/
    assert_select "h3", text: /MITtens/
    assert_select "h3", text: /Alphas/
  end

  test "a prior bonk is badged on the Alpha list and nowhere else" do
    set = Pod.create_alpha_set!(@slot)
    mentor_of_record = person(:active_ranger)
    [@alpha, @cadre_mentor].each do |person|
      PersonMentor.create!(person:, mentor: mentor_of_record,
                           mentor_year: 2019, status: PersonMentor::STATUS_BONK)
    end
    set.sub_pods.find(&:alpha?).add_person!(@alpha)
    set.add_person!(@cadre_mentor)
    sign_in_as(@mentor)

    get mentoring_alpha_pods_shift_path(@slot)

    assert_response :success
    assert_equal 1, response.body.scan("Bonked 2019").size,
                 "the Alpha carries the badge; the mentor with the same history does not"
  end

  test "a shift with no pods invites the first one" do
    sign_in_as(@mentor)
    get mentoring_alpha_pods_shift_path(@slot)
    assert_response :success
    assert_match "No pods have been formed", response.body
  end

  test "a shift that is not an Alpha shift is refused" do
    sign_in_as(@mentor)
    get mentoring_alpha_pods_shift_path(@mentor_slot)
    assert_redirected_to mentoring_alpha_pods_path(year: YEAR)
    assert_match(/not an Alpha shift/, flash[:error])
  end

  test "Alphas signed in with no pod are counted and named" do
    Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id,
                      on_duty: Current.time - 1.hour, additional_notes: "signed in")
    sign_in_as(@mentor)

    get mentoring_alpha_pods_shift_path(@slot)

    assert_response :success
    assert_match "Waiting for a pod", response.body
    assert_match @alpha.callsign, response.body
  end

  # --- pods ---

  test "adding a pod creates a linked trio and streams the board back" do
    sign_in_as(@mentor)

    assert_difference "Pod.count", 3 do
      post mentoring_alpha_pods_pods_path(@slot), as: :turbo_stream
    end

    assert_response :success
    assert_match "alpha-pods-board", response.body
    assert_equal 1, Pod.mentor_pods_for(@slot).count
  end

  test "deleting a pod removes its trio and renumbers the rest" do
    first = Pod.create_alpha_set!(@slot)
    second = Pod.create_alpha_set!(@slot)
    sign_in_as(@mentor)

    assert_difference "Pod.count", -3 do
      delete mentoring_alpha_pods_pod_path(@slot, first), as: :turbo_stream
    end

    assert_response :success
    assert_equal 1, second.reload.sort_index
  end

  test "a pod moves through the walk order" do
    first = Pod.create_alpha_set!(@slot)
    second = Pod.create_alpha_set!(@slot)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_pod_move_path(@slot, second, direction: Pod::MOVE_EARLIER),
          as: :turbo_stream

    assert_response :success
    assert_equal [2, 1], [first.reload.sort_index, second.reload.sort_index]
  end

  test "an unknown move direction is refused" do
    set = Pod.create_alpha_set!(@slot)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_pod_move_path(@slot, set, direction: "sideways"), as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 1, set.reload.sort_index
  end

  # --- membership ---

  test "the add dialog offers people who are not yet in a pod" do
    set = Pod.create_alpha_set!(@slot)
    Timesheet.create!(person_id: @alpha.id, position_id: @alpha_position.id,
                      on_duty: @slot.begins, additional_notes: "signed in")
    sign_in_as(@mentor)

    get mentoring_new_alpha_pods_person_path(@slot, set.sub_pods.find(&:alpha?))

    assert_response :success
    assert_match @alpha.callsign, response.body
    assert_match "Checked in around", response.body
  end

  test "a member's edit form renders" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    sign_in_as(@mentor)
    post mentoring_alpha_pods_people_path(@slot, pod), params: { person_ids: [@alpha.id] }, as: :turbo_stream

    get mentoring_edit_alpha_pods_person_path(@slot, pod, @alpha)

    assert_response :success
    assert_match @alpha.callsign, response.body
  end

  test "several people are added at once" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    sign_in_as(@mentor)

    post mentoring_alpha_pods_people_path(@slot, pod),
         params: { person_ids: [@alpha.id, @other_alpha.id] }, as: :turbo_stream

    assert_response :success
    assert_equal 2, pod.current_members.count
    assert_equal 2, pod.reload.person_count
  end

  test "adding no one is refused" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    sign_in_as(@mentor)

    post mentoring_alpha_pods_people_path(@slot, pod), params: { person_ids: [] },
         as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 0, pod.current_members.count
  end

  # ActiveRecord reads "#{id}x" as the id, which put that Alpha in the pod.
  test "person ids that are not ids add no one" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    sign_in_as(@mentor)

    post mentoring_alpha_pods_people_path(@slot, pod), params: { person_ids: ["", "abc", "#{@alpha.id}x"] },
         as: :turbo_stream

    assert_response :unprocessable_entity
    assert_equal 0, pod.current_members.count
  end

  test "someone already in another pod of the shift is refused but the rest are added" do
    first = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    second = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    first.add_person!(@alpha)
    sign_in_as(@mentor)

    post mentoring_alpha_pods_people_path(@slot, second),
         params: { person_ids: [@alpha.id, @other_alpha.id] }, as: :turbo_stream

    assert_response :success
    assert_equal [@other_alpha.id], second.current_members.map(&:person_id)
    assert_equal [@alpha.id], first.current_members.map(&:person_id)
  end

  test "a mentor can be marked as the lead when added" do
    set = Pod.create_alpha_set!(@slot)
    sign_in_as(@mentor)

    post mentoring_alpha_pods_people_path(@slot, set),
         params: { person_ids: [@cadre_mentor.id], is_lead: "1" }, as: :turbo_stream

    assert_response :success
    assert set.current_members.first.is_lead
  end

  test "someone is moved from one pod to another" do
    first = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    second = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    first.add_person!(@alpha)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_person_path(@slot, first, @alpha),
          params: { new_pod_id: second.id }, as: :turbo_stream

    assert_response :success
    assert_equal 0, first.current_members.count
    assert_equal [@alpha.id], second.current_members.map(&:person_id)
  end

  test "the lead flag is toggled in place" do
    set = Pod.create_alpha_set!(@slot)
    set.add_person!(@cadre_mentor)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_person_path(@slot, set, @cadre_mentor),
          params: { new_pod_id: set.id, is_lead: "1" }, as: :turbo_stream

    assert_response :success
    assert set.current_members.first.is_lead
  end

  test "an alpha pod refuses a lead" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_person_path(@slot, pod, @alpha),
          params: { new_pod_id: pod.id, is_lead: "1" }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_not pod.current_members.first.is_lead
  end

  test "a member steps up the order" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    pod.add_person!(@other_alpha)
    sign_in_as(@mentor)

    patch mentoring_alpha_pods_person_path(@slot, pod, @other_alpha),
          params: { direction: Pod::MOVE_UP }, as: :turbo_stream

    assert_response :success
    assert_equal [@other_alpha.id, @alpha.id], pod.current_members.ordered.map(&:person_id)
  end

  test "removing someone keeps the row as history" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    sign_in_as(@mentor)

    delete mentoring_alpha_pods_person_path(@slot, pod, @alpha), as: :turbo_stream

    assert_response :success
    assert_equal 0, pod.current_members.count
    assert_not_nil PersonPod.find_by(pod_id: pod.id, person_id: @alpha.id).removed_at
  end

  test "saving an alpha member without relocating them is not an error" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    pod.add_person!(@alpha)
    sign_in_as(@mentor)

    # What the dialog's own Save button sends for an alpha pod: the pod they
    # are already in, and no lead checkbox, because it renders none.
    patch mentoring_alpha_pods_person_path(@slot, pod, @alpha),
          params: { new_pod_id: pod.id }, as: :turbo_stream

    assert_response :success
    assert_match "No changes were made", response.body
    assert_equal 1, pod.current_members.count
  end

  # A dialog is opened by a turbo-FRAME GET, which does not accept a turbo
  # stream. Answering that with a redirect leaves Turbo swapping in the
  # layout's empty modal frame and the reader staring at nothing.
  test "opening a dialog for someone already taken out explains itself in the frame" do
    pod = Pod.create_alpha_set!(@slot).sub_pods.find(&:alpha?)
    sign_in_as(@mentor)

    get mentoring_edit_alpha_pods_person_path(@slot, pod, @alpha),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#modal"
    assert_match "no longer in this pod", response.body
  end

  test "opening the add dialog for a deleted pod explains itself in the frame" do
    mentor_pod = Pod.create_alpha_set!(@slot)
    alpha_pod = mentor_pod.sub_pods.find(&:alpha?)
    mentor_pod.destroy_set!
    sign_in_as(@mentor)

    get mentoring_new_alpha_pods_person_path(@slot, alpha_pod),
        headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_select "turbo-frame#modal"
    assert_match "no longer on this shift", response.body
  end

  test "a plain browser request for a missing pod still redirects" do
    mentor_pod = Pod.create_alpha_set!(@slot)
    alpha_pod = mentor_pod.sub_pods.find(&:alpha?)
    mentor_pod.destroy_set!
    sign_in_as(@mentor)

    get mentoring_new_alpha_pods_person_path(@slot, alpha_pod)

    assert_redirected_to mentoring_alpha_pods_shift_path(@slot)
  end

  # --- the print sheet ---

  test "the print sheet lists the pods in columns" do
    set = Pod.create_alpha_set!(@slot)
    set.sub_pods.find(&:alpha?).add_person!(@alpha)
    sign_in_as(@mentor)

    get mentoring_alpha_pods_print_path(@slot)

    assert_response :success
    assert_match "alpha-pod-table", response.body
    assert_match "Pod 1", response.body
    assert_match @alpha.callsign, response.body
    assert_match "size: letter landscape", response.body, "the sheet asks for landscape"
    assert_no_match(/<nav/, response.body, "the print layout has no chrome")
  end
end
