# frozen_string_literal: true

# Alpha Sign-Out -- end the shift for Alphas still on duty after an Alpha walk.
#
# Port of upstream Ember mentor/alpha-signout, which drove the TimesheetController
# index/signoff pair one HTTP request at a time. Both halves live here so the rows
# the page offers and the rows the POST accepts cannot diverge: +for_slot+ /
# +on_duty_everywhere+ draw the page, and +sign_out+ re-derives the same "open
# Alpha entry" rule before every write.
module AlphaSignOut
  # How far either side of a shift's start an Alpha's check-in may fall.
  #
  # Upstream's on-screen copy says "one hour before til one after"; its code
  # (alpha-signout.js changeSlot) subtracts one hour and adds two. The code is
  # what has been running on playa, so it is what is ported -- and the page
  # states the resulting clock times rather than repeating the sentence.
  HOURS_PRIOR = 1.hour
  HOURS_AFTER = 2.hours

  # Alphas still on duty, and (in slot mode) those already signed out on the
  # same shift.
  Roster = Data.define(:on_duty, :signed_out) do
    def any? = on_duty.any? || signed_out.any?

    # Shifts short enough to look like an accidental check-in. Badged rather
    # than blocked: ShiftManageConcern's per-person "too short?" modal cannot
    # interrupt a forty-row bulk action, so the reader is shown which rows to
    # uncheck instead. Upstream does not check at all.
    def too_short_count = on_duty.count(&:too_short?)
  end

  # What became of every id the form submitted, plus anyone whose account
  # ShiftManage converted back to Active on the way out.
  Outcome = Data.define(:results, :now_active)

  class << self
    # Every Alpha entry that opened in the window around a shift, split into
    # those still on duty and those already closed.
    #
    # +is_on_duty+ is deliberately NOT passed, unlike upstream: the closed rows
    # are what answers "did everyone get out?", which is the question that
    # brings a mentor lead back to this page a second time. The window bounds
    # the query to a three-hour band, so dropping the filter does not widen it.
    def for_slot(slot, keep_ids: [])
      rows = Timesheet.find_for_query(position_id: Position::ALPHA,
                                      on_duty_start: slot.begins - HOURS_PRIOR,
                                      on_duty_end: slot.begins + HOURS_AFTER)

      keep = keep_ids.to_set
      on_duty, signed_out = rows.partition { |entry| entry.off_duty.nil? || keep.include?(entry.id) }
      Roster.new(on_duty:, signed_out:)
    end

    # Every Alpha still on duty anywhere, ignoring shift boundaries -- upstream's
    # "All Alphas on shift" option. Deliberately unbounded by year: an entry left
    # open since a previous event is exactly the stuck row this mode exists to
    # catch. There is no bounded closed set to show alongside it.
    def on_duty_everywhere(keep_ids: [])
      rows = Timesheet.find_for_query(position_id: Position::ALPHA, is_on_duty: true)

      # The rows just signed out are no longer on duty, so the query above drops
      # them -- they are read back by id and held on the page one last time.
      missing = keep_ids.to_a - rows.map(&:id)
      rows += Timesheet.where(id: missing).includes(:person, :position).to_a if missing.any?

      Roster.new(on_duty: rows.sort_by { |entry| entry.person.callsign.downcase }, signed_out: [])
    end

    # End every submitted shift, one entry at a time, and report what became of
    # each id.
    #
    # The position and the open-shift check are re-derived here rather than
    # trusted from the form. Upstream POSTs whatever id the client holds and the
    # API signs off any timesheet the user may touch, so a hand-edited form could
    # end an unrelated Ranger's shift from the Alpha page.
    #
    # No wrapping transaction: each sign-off stands alone, so one refused row
    # does not roll back the other thirty-nine. That is the same per-person
    # independence upstream got from one HTTP request per Alpha.
    def sign_out(ids, user:)
      entries = Timesheet.where(id: ids, position_id: Position::ALPHA)
                         .includes(:person, :position).index_by(&:id)
      now_active = []

      results = ids.index_with do |id|
        entry = entries[id]
        next :not_eligible if entry.nil?
        next :already_signed_out if entry.off_duty.present?

        result = ShiftManage.sign_off(entry, user:)
        now_active << entry.person.callsign if result.now_active
        result.status == :success ? :signed_out : :already_signed_out
      end

      Outcome.new(results:, now_active:)
    end
  end
end
