# frozen_string_literal: true

require "test_helper"

# Training › Mentoring › Verdicts: the verdicts with their filters and CSV, the
# mentors' seasons, a verdict that outlives its timesheet entry, and the gate.
class Training::Mentoring::VerdictsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ArtMentoringTestHelper
  include PersonTestFactory
  include ReportCardTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  SLUG = "green-dot"

  setup do
    travel_to Time.zone.local(YEAR, 9, 2, 19, 0, 0)
    Rails.cache.clear
    Current.reset
    setup_art_mentoring

    ensure_role(Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING, "Green Dot Interface")
    grant_role(person(:retired_ranger), Role::ART_TRAINER_BASE | Position::GREEN_DOT_TRAINING)

    @slot = mentee_shift(Time.zone.local(YEAR, 9, 1, 17, 45, 0))
    @ferrous = create_person("Ferrous")
    @cinder = create_person("Cinder")
    mentor_entry(@ferrous, @slot.begins - 10.minutes, off_duty: @slot.ends)
    tinsel = mentee_entry(create_person("Tinsel"), @slot.begins, off_duty: @slot.ends, slot: @slot)
    sable = mentee_entry(create_person("Sable"), @slot.begins + 5.minutes, off_duty: @slot.ends, slot: @slot)
    @passed = walk(tinsel, @ferrous, status: PersonMentor::STATUS_PASS, notes: "Ready for the team.")
    @bonked = walk(sable, @cinder, status: PersonMentor::STATUS_BONK)

    sign_in_as(person(:retired_ranger))
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  def verdicts_path(year: YEAR, **) = training_mentoring_verdicts_path(SLUG, year:, **)

  test "the verdicts and each mentor's season are listed, each shift linking to its roster" do
    get verdicts_path

    assert_response :success
    assert_select "h1", text: /Green Dot Mentoring Verdicts/
    assert_select "title", text: "Green Dot Mentoring Verdicts"
    assert_report_card
    assert_select "tr#verdict-#{@passed.id}", text: /Tinsel.*Passed.*Ferrous.*Ready for the team\./m do
      assert_select "a[href=?]", training_mentoring_assignment_shift_path(SLUG, @slot.id, year: YEAR)
    end
    assert_select "tr#mentor-#{@ferrous.id}"
    assert_select "tr#mentor-#{@cinder.id}"
    assert_includes response.body, "Not signed in as a mentor", "Cinder was paired without signing in"
  end

  test "the filters narrow the verdicts, and the CSV follows them" do
    get verdicts_path(status: PersonMentor::STATUS_BONK)

    assert_select "tr#verdict-#{@bonked.id}"
    assert_select "tr#verdict-#{@passed.id}", count: 0
    assert_includes response.body, "Verdict: Bonked"
    assert_select "a[href=?]", verdicts_path(status: PersonMentor::STATUS_BONK, format: :csv)

    get verdicts_path(status: PersonMentor::STATUS_BONK, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal ["Mentee,Verdict,Mentor,Shift,Length,Notes", "Sable,Bonked,Cinder,2026-09-01 17:50,5:55,"],
                 response.body.lines(chomp: true)
  end

  test "a pass recorded with no mentor leaves the CSV's Mentor cell empty" do
    rook = mentee_entry(create_person("Rook"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    walk(rook, nil, status: PersonMentor::STATUS_PASS)

    get verdicts_path(format: :csv)

    assert_includes response.body.lines(chomp: true), "Rook,Passed,,2026-09-01 17:55,5:50,"
  end

  test "an ART-only verdict is listed with its badge and can be filtered" do
    rook = mentee_entry(create_person("Rook"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    abstained = walk(rook, @ferrous, status: PersonMentor::STATUS_ABSTAIN)

    get verdicts_path(status: PersonMentor::STATUS_ABSTAIN)

    assert_select "tr#verdict-#{abstained.id}", text: /Rook.*Abstained.*Ferrous/m
    assert_select "tr#verdict-#{@passed.id}", count: 0
    assert_includes response.body, "Verdict: Abstained"
  end

  test "the verdicts list by mentee unless sorted by shift or by mentor" do
    zephyr = mentee_entry(create_person("Zephyr"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    late = walk(zephyr, @ferrous, status: PersonMentor::STATUS_PASS)
    order = -> { css_select("tr[id^='verdict-']").map { |row| row["id"] } }
    ids = ->(*walks) { walks.map { |w| "verdict-#{w.id}" } }

    get verdicts_path
    assert_equal ids.call(@bonked, @passed, late), order.call, "Sable, Tinsel, Zephyr"
    assert_select "select#sort option[selected]", text: "Mentee"
    assert_includes response.body, "Showing 3 of 3 verdicts, by mentee"

    get verdicts_path(sort: "shift")
    assert_equal ids.call(late, @bonked, @passed), order.call, "newest shift first"
    assert_includes response.body, "Showing 3 of 3 verdicts, by shift, newest first"
    assert_select "button[aria-controls='mentoring-verdicts-filters-panel'] .badge", { count: 0 },
                  "an order narrows nothing, so it is not counted as a filter"

    get verdicts_path(sort: "mentor")
    assert_equal ids.call(@bonked, late, @passed), order.call, "Cinder, then Ferrous's newest shift first"

    get verdicts_path(sort: "mentor", format: :csv)
    assert_equal %w[Sable Zephyr Tinsel], response.body.lines.drop(1).map { |line| line.split(",").first }
  end

  test "a filter's chip and the CSV keep a chosen order, and leave the default out" do
    get verdicts_path(notes: "with", sort: "mentor")

    assert_select "a[href=?]", verdicts_path(sort: "mentor"), text: /Notes: Has notes/
    assert_select "button[aria-controls='mentoring-verdicts-filters-panel'] .badge", text: "1"
    assert_select "a[href=?]", verdicts_path(notes: "with", sort: "mentor", format: :csv)

    get verdicts_path(notes: "with", sort: "mentee")

    assert_select "a[href=?]", verdicts_path, text: /Notes: Has notes/
    assert_select "a[href=?]", verdicts_path(notes: "with", format: :csv)
  end

  test "a deleted mentor is listed after the others, in the Mentor filter as in the Mentor order" do
    rook = mentee_entry(create_person("Rook"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    gone = create_person("Aardvark")
    orphaned = walk(rook, gone, status: PersonMentor::STATUS_PASS)
    unpaired = walk(mentee_entry(create_person("Wren"), @slot.begins + 15.minutes, off_duty: @slot.ends, slot: @slot),
                    nil, status: PersonMentor::STATUS_PASS)
    gone.delete # the walk keeps naming the account

    get verdicts_path(sort: "mentor")

    assert_equal ["verdict-#{@bonked.id}", "verdict-#{@passed.id}", "verdict-#{orphaned.id}", "verdict-#{unpaired.id}"],
                 css_select("tr[id^='verdict-']").map { |row| row["id"] }
    assert_equal ["All", "Cinder", "Ferrous", "Deleted ##{gone.id}", "No mentor"],
                 css_select("select#mentor_id option").map(&:text)
  end

  test "the verdicts filter by notes, and by no mentor" do
    rook = mentee_entry(create_person("Rook"), @slot.begins + 10.minutes, off_duty: @slot.ends, slot: @slot)
    unpaired = walk(rook, nil, status: PersonMentor::STATUS_PASS)

    get verdicts_path(notes: "with")
    assert_select "tr#verdict-#{@passed.id}"
    assert_select "tr#verdict-#{@bonked.id}", count: 0
    assert_includes response.body, "Notes: Has notes"

    get verdicts_path(notes: "without")
    assert_select "tr#verdict-#{@passed.id}", count: 0
    assert_select "tr#verdict-#{@bonked.id}"

    get verdicts_path(mentor_id: "none")
    assert_select "tr[id^='verdict-']", count: 1
    assert_select "tr#verdict-#{unpaired.id}"
    assert_includes response.body, "Mentor: No mentor"
    assert_select "select#mentor_id option:last-child[value=none]", text: "No mentor"
  end

  test "a filter value the page does not offer reads as all" do
    get verdicts_path(status: "promoted", mentor_id: "999999", notes: "maybe", sort: "verdict")

    assert_select "tr#verdict-#{@passed.id}"
    assert_select "tr#verdict-#{@bonked.id}"
  end

  test "a verdict whose timesheet entry was deleted stays, as Shift deleted" do
    Timesheet.find(@passed.timesheet_id).destroy

    get verdicts_path

    assert_select "tr#verdict-#{@passed.id}", text: /Shift deleted/
  end

  test "a year without verdicts says so" do
    get verdicts_path(year: YEAR - 1)

    assert_response :success
    assert_includes response.body, "No mentee shift has a verdict recorded in #{YEAR - 1}."
  end

  test "an In-Person trainer cannot open an ART's verdicts" do
    ensure_role(Role::TRAINER, "Trainer")
    grant_role(person(:echelon_ranger), Role::TRAINER)
    sign_in_as(person(:echelon_ranger))

    get verdicts_path

    assert_redirected_to me_root_path
  end
end
