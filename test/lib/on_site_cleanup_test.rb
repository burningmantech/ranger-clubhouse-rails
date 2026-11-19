# frozen_string_literal: true

require "test_helper"

class OnSiteCleanupTest < ActiveSupport::TestCase
  # The Saturday after Labor Day 2026, when the nightly job first runs.
  NOW = Time.zone.local(2026, 9, 12, 4, 0, 0)

  setup do
    Current.reset
    travel_to NOW
    @admin = person(:echelon_ranger)
    Current.person = @admin
    @ranger = person(:active_ranger)
    on_site(@ranger)
  end

  teardown { Current.reset }

  test "someone on duty, holding an asset or with a shift to come stays, and why is told" do
    holder = on_site(person(:retired_ranger))
    scheduled = on_site(person(:inactive_ranger))
    timesheet(@ranger, NOW - 2.hours, nil)
    asset_loan(holder, NOW - 3.days, nil)
    sign_up(scheduled, NOW + 6.hours, NOW + 12.hours)

    cleanup = OnSiteCleanup.new

    assert_empty cleanup.leaving
    assert_equal({ @ranger.id => [OnSiteCleanup::ON_DUTY], holder.id => [OnSiteCleanup::ASSET_OUT],
                   scheduled.id => [OnSiteCleanup::UPCOMING_SHIFT] },
                 cleanup.staying.to_h { [it.person.id, it.blockers] })
  end

  # An asset from an earlier year is someone else's problem, and a shift that
  # is over holds no one. One still running does: they may be working it.
  test "last year's asset and a finished shift hold no one; a shift still running does" do
    working = on_site(person(:retired_ranger))
    asset_loan(@ranger, NOW - 1.year, nil)
    sign_up(@ranger, NOW - 10.hours, NOW - 4.hours)
    sign_up(working, NOW - 2.hours, NOW + 4.hours)

    cleanup = OnSiteCleanup.new

    assert_equal [@ranger.id], cleanup.leaving.map { it.person.id }
    assert_equal [working.id], cleanup.staying.map { it.person.id }
  end

  test "the mark is dated at the later of the last sign-out and the last asset return" do
    arrived(@ranger, NOW - 10.days)
    entry = timesheet(@ranger, NOW - 3.days, NOW - 3.days + 6.hours)
    asset_loan(@ranger, NOW - 9.days, NOW - 4.days)
    returner = on_site(person(:retired_ranger))
    timesheet(returner, NOW - 5.days, NOW - 5.days + 6.hours)
    loan = asset_loan(returner, NOW - 9.days, NOW - 1.day)

    left_at = OnSiteCleanup.new.leaving.to_h { [it.person.id, it.left_at] }

    assert_equal({ @ranger.id => entry.reload.off_duty, returner.id => loan.reload.checked_in }, left_at)
  end

  # Activity from before the on-site mark says nothing about leaving, and a mark
  # dated then would sort ahead of the on-site mark it is meant to close.
  test "with no activity since they were marked on site, the mark is dated now" do
    idle = on_site(person(:retired_ranger))
    timesheet(@ranger, NOW - 9.days, NOW - 9.days + 6.hours)
    arrived(@ranger, NOW - 8.days)

    left_at = OnSiteCleanup.new.leaving.to_h { [it.person.id, it.left_at] }

    assert_equal({ @ranger.id => NOW, idle.id => NOW }, left_at)
  end

  test "run! marks the leavers off site, automatic, at the time they left, and leaves the rest" do
    holder = on_site(person(:retired_ranger))
    asset_loan(holder, NOW - 3.days, nil)
    arrived(@ranger, NOW - 10.days)
    entry = timesheet(@ranger, NOW - 3.days, NOW - 3.days + 6.hours)

    assert_equal 1, OnSiteCleanup.new.run!

    assert_not @ranger.reload.on_site
    assert holder.reload.on_site
    row = PersonOnSite.history_for(@ranger).first
    assert_equal [PersonOnSite::OFF_SITE, PersonOnSite::AUTOMATIC, @admin.id],
                 [row.action, row.reason, row.creator_person_id]
    # Read back from both records: a zone slip in the grouped maximum would show here.
    assert_equal entry.reload.off_duty, row.created_at
    audit = ActionLog.where(event: "person-update", target_person_id: @ranger.id).order(:id).last
    assert_equal [OnSiteCleanup::AUDIT_REASON, @admin.id], [audit.message, audit.person_id]

    assert_no_difference -> { PersonOnSite.count } do
      assert_equal 0, OnSiteCleanup.new.run!
    end
  end

  private

  def on_site(person)
    person.update_columns(on_site: true)
    person
  end

  # The on-site mark that opened their stay.
  def arrived(person, at)
    PersonOnSite.create!(person:, action: PersonOnSite::ON_SITE, created_at: at)
  end

  def timesheet(person, on_duty, off_duty)
    Timesheet.create!(person:, position: positions(:ood_position), on_duty:, off_duty:,
                      additional_notes: "worked a shift")
  end

  def asset_loan(person, checked_out, checked_in)
    @asset ||= asset(:radio_current_year)
    PersonAsset.create!(person:, asset: @asset, checked_out:, checked_in:)
  end

  def sign_up(person, begins, ends)
    slot = Slot.create!(position: positions(:ood_position), begins:, ends:, max: 10, active: true)
    PersonSlot.create!(person:, slot:)
  end
end
