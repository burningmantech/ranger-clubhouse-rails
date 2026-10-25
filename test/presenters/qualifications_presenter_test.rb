# frozen_string_literal: true

require "test_helper"

# Exercises QualificationsPresenter over hand-built progress items, so each case
# holds exactly the row states under test.
class QualificationsPresenterTest < ActiveSupport::TestCase
  # Threshold and counter per row, in TicketsAndProvisionsProgress order, which
  # breaks ties between equally close rows.
  ROWS = {
    spt: [19, :credits], staff_credential: [38, :credits], all_eats: [130, :all_hours],
    event_week_eats: [60, :event_week], shower_pog: [40, :event_week], shower_access_event_week: [60, :event_week],
    shower_access_entire_event: [130, :all_hours], t_shirt: [18, :pre_event_and_event_week],
    long_sleeve_shirt: [30, :pre_event_and_event_week]
  }.freeze

  EARNED = ROWS.keys.index_with(:earned).freeze

  # Each row is :earned, :on_track, :closed (unearned, and its counter can no longer
  # grow), or needs sign-ups with the given hours or credits still to find; rows not
  # named need their whole threshold.
  def presenter(shiny_penny: false, **states)
    items = ROWS.to_h do |key, (threshold, counter)|
      state = states.fetch(key, threshold)
      item = TicketsAndProvisionsProgress::ProgressItem.new(
        name: key, measure: :hours, value: 0, expected_total: 0, threshold:,
        has_earned: state == :earned, expected_to_earn: %i[earned on_track].include?(state),
        needs_to_work: 0, needs_to_schedule: 0
      )
      item.shortfall = state.is_a?(Integer) ? state : 0
      item.counter = counter
      item.closed = state == :closed
      [key, item]
    end
    QualificationsPresenter.new(items, shiny_penny:)
  end

  test "a goal stands as well as its best row, and a section as its worst goal" do
    qualifications = presenter(spt: :on_track, staff_credential: 20, t_shirt: :earned,
                               shower_pog: :earned, shower_access_event_week: :on_track)

    assert_equal :on_track, qualifications.section_state(:tickets)
    assert_equal :needs_sign_ups, qualifications.section_state(:ranger_clothing)
    assert_equal :on_track, qualifications.section_state(:showers)
    assert_equal({ on_track: 2, earned: 2, needs_sign_ups: 2 }, qualifications.goal_counts)
  end

  test "a Shiny Penny has no clothing goals" do
    qualifications = presenter(shiny_penny: true, **EARNED.except(:t_shirt, :long_sleeve_shirt))

    assert qualifications.all_earned?
    assert_equal({ earned: 4 }, qualifications.goal_counts)
    assert_nil qualifications.section_state(:ranger_clothing)
    assert_nil qualifications.next_step
  end

  test "a lower tier and the combined Wet Spot Access path drop out once the row above is earned" do
    qualifications = presenter(staff_credential: :earned, all_eats: :earned, shower_access_event_week: :earned)

    assert_not qualifications.visible?(:spt)
    assert_not qualifications.visible?(:event_week_eats)
    assert_not qualifications.visible?(:shower_access_entire_event)
    assert qualifications.visible?(:shower_access_event_week)
    assert presenter.visible?(:spt)
  end

  test "the next step is the smallest ask, counting the rows the same sign-ups also earn" do
    step = presenter(spt: 15, event_week_eats: 12, shower_access_event_week: 12, shower_pog: 10).next_step

    assert_equal :shower_pog, step.item.name
    assert_equal 0, step.others

    step = presenter(spt: 15, event_week_eats: 12, shower_access_event_week: 12).next_step
    assert_equal :event_week_eats, step.item.name
    assert_equal 1, step.others
  end

  test "the fewest hours left beats the largest share done" do
    assert_equal :t_shirt, presenter(all_eats: 122, t_shirt: 18).next_step.item.name
  end

  test "an upper tier competes on the size of its ask, but a secured goal's other rows are never the next step" do
    upgrades = presenter(**EARNED, spt: :on_track, staff_credential: 14, event_week_eats: :on_track, all_eats: 66,
                                   shower_access_event_week: 60)

    assert_equal :staff_credential, upgrades.next_step.item.name
    # The combined path already secured Wet Spot Access, so the Event Week path is no step at all.
    assert_nil presenter(**EARNED, shower_access_event_week: 5).next_step
    assert_equal :staff_credential, presenter(**EARNED, staff_credential: 3, long_sleeve_shirt: 20).next_step.item.name
    assert_equal :long_sleeve_shirt, presenter(**EARNED, staff_credential: 25, long_sleeve_shirt: 12).next_step.item.name
  end

  test "nothing to sign up for leaves no next step, whether everything is earned or only on track" do
    earned = presenter(**EARNED)
    on_track = presenter(**EARNED, long_sleeve_shirt: :on_track)

    assert_nil earned.next_step
    assert earned.all_earned?
    assert_nil on_track.next_step
    assert_not on_track.all_earned?
    assert_not on_track.closed_out?
  end

  test "a closed row is never the next step, ranks above one needing sign-ups, and closes the page out only with nothing open" do
    # After event week: the Event Week shower path is closed, the combined path is still open.
    after_event_week = presenter(**EARNED, shower_pog: :closed, shower_access_event_week: :closed,
                                           shower_access_entire_event: 100)

    assert_equal :shower_access_entire_event, after_event_week.next_step.item.name
    assert_equal :needs_sign_ups, after_event_week.section_state(:showers)
    assert_equal({ earned: 4, closed: 1, needs_sign_ups: 1 }, after_event_week.goal_counts)
    assert_not after_event_week.closed_out?

    # After post-event: every open row is closed.
    closed_out = presenter(**EARNED, shower_pog: :closed, shower_access_event_week: :closed,
                                     shower_access_entire_event: :closed, t_shirt: :on_track)
    assert_nil closed_out.next_step
    assert_equal :closed, closed_out.section_state(:showers)
    assert_not closed_out.closed_out? # a shirt is still on track
    assert presenter(**EARNED, shower_pog: :closed, t_shirt: :closed).closed_out?
  end
end
