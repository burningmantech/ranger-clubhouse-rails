# frozen_string_literal: true

# The Roll Call board — whole burn-night crews signed in and out by tapping
# names on a roster, instead of one Ranger at a time at an HQ window.
#
# Port of the Ember rollcall-sign-in / rollcall-sign-out components. Two
# rosters, drawn as the same row: the sign-ups for one shift, and everyone
# still out. The writes themselves are ShiftManage's — this module only decides
# who appears and in what state.
module Rollcall
  # Burn positions float to the top of the position picker: on the night this
  # page is used, they are what it is used for. Upstream unshifts each of
  # [Sandman, Burn Perimeter, Art Car Wrangler] onto the front in turn, which
  # lands them in the reverse of that order — spelled out here rather than
  # re-derived, so the displayed order is readable at a glance.
  BURN_POSITION_ORDER = [Position::ART_CAR_WRANGLER, Position::BURN_PERIMETER,
                         Position::SANDMAN].freeze

  # One person on a roster, with whatever open timesheet entry they have.
  # +entry+ is nil for someone not out, and keeps its Timesheet after a
  # sign-off so the row can offer to resume the shift it just ended.
  Row = Data.define(:person_id, :callsign, :avatar, :entry) do
    def on_duty? = entry.present? && entry.off_duty.nil?

    # Out on some position other than the one being signed into. The red state
    # on the sign-in roster: this Ranger is already somewhere else.
    #
    # Both sides must be real ids. nil.to_i is 0, so a missing position_id
    # would otherwise make every on-duty row read as "elsewhere", and an entry
    # whose position_id is nil -- possible, since every save here skips
    # validation -- would do the same to a Ranger who is right where the row
    # says they are.
    def elsewhere?(position_id)
      return false unless on_duty? && entry.position_id.present? && position_id.present?

      entry.position_id != position_id.to_i
    end
  end

  # A position and the rollcall-window shifts (or on-duty rows) under it.
  Group = Data.define(:position, :members) do
    def id = position.id
    def title = position.title
    def burn? = BURN_POSITION_ORDER.include?(position.id)
  end

  class << self
    # Which roster a request is about.
    #
    # The mode rides in form params as the symbol's own to_s, so "sign_out" is
    # the wire spelling and this is the single place it is compared. The routes
    # spell their paths "sign-in" and "sign-out" — a different alphabet for a
    # different job, and reading one as the other silently turns every sign-out
    # tap into a sign-in tap.
    def mode_from(param) = (param.to_s == "sign_out") ? :sign_out : :sign_in

    # Shifts open for rollcall, grouped by position. The window itself
    # (now − 4h .. now + 2h) is Slot.find_for_query's, not spelled again here.
    #
    # active: true is not optional. SignInBlocker#check_slots only ever
    # considers active slots, so a cancelled shift left in the picker would be
    # signed against while the timing blocker judged the check-in against a
    # different shift entirely — or none.
    def shift_groups
      slots = Slot.find_for_query(for_rollcall: true, active: true).to_a
      # No FK on slot.position_id in the Laravel-shared schema, so the
      # association can read nil even though it is not declared optional.
      group_by_position(slots.select(&:position))
    end

    # Everyone signed up for one shift, alphabetically, each with their open
    # entry if they have one.
    #
    # Deliberately not Slot.retrieve_sign_ups: its include_photo branch calls
    # PersonPhoto.retrieve_profile_url_for_person, which does not exist in this
    # codebase, and its on-duty branch answers a Hash through a singleton
    # method rather than the Timesheet the tap actions need.
    def sign_in_roster(slot)
      people = signed_up_scope(slot.id).includes(:avatar_photo_attachment).order(:callsign).to_a
      entries = open_entries_for(people.map(&:id))
      people.map { |person| row_for(person, entries[person.id]) }
    end

    # Positions with somebody still out, for the Sign Out picker. Deliberately
    # carries no people and no avatars: the picker needs an id and a title, and
    # on burn night the whole board is ~400 entries whose photos would be
    # loaded and thrown away to draw a <select>.
    def sign_out_positions
      position_ids = on_duty_scope.distinct.pluck(:position_id)
      order_groups(Position.where(id: position_ids)
                           .map { |position| Group.new(position: position, members: []) })
    end

    # The crew still out on one position.
    def sign_out_roster(position_id)
      entries = on_duty_scope.where(position_id: position_id)
                             .includes(:position, person: :avatar_photo_attachment)
                             .to_a
      entries.sort_by! { |entry| entry.person.callsign.downcase }
      entries.map { |entry| row_for(entry.person, entry) }
    end

    # The two roster headline numbers, counted in the database rather than by
    # rebuilding the roster. Every tap redraws this, and rebuilding a 178-person
    # sign-in roster — people, photos, attachments, blobs — to produce two
    # integers costs eight queries and some six hundred objects each time.
    #
    # Takes ids, not a Slot: every tap recounts, and the POST already carries
    # both — loading the Slot again would buy nothing but a query.
    #
    # total counts through signed_up_scope, the same join the roster is built
    # from, rather than person_slot rows. The schema carries no app-domain
    # foreign keys, so a sign-up whose Ranger has been deleted would otherwise
    # be counted and never drawn, leaving a denominator nothing can reach.
    def sign_in_counts(slot_id, position_id)
      signed_up = signed_up_scope(slot_id)
      { signed_in: on_duty_scope.where(position_id: position_id,
                                       person_id: signed_up.select("person.id")).count,
        total: signed_up.count }
    end

    # position_id is required: where(position_id: nil) is IS NULL, which would
    # silently count orphaned entries as this position's headline number.
    def on_duty_count(position_id)
      return 0 if position_id.blank?

      on_duty_scope.where(position_id: position_id).count
    end

    # The single row for one person, rebuilt after a write so a streamed row
    # shows committed state rather than what the tap assumed. The entry is
    # always supplied: every caller has just saved, found or ruled it out, and
    # a sentinel meaning "go and look it up" only ever bought a query the
    # caller had already paid for.
    def row_for(person, entry)
      Row.new(person_id: person.id, callsign: person.callsign,
              avatar: person.avatar_photo, entry: entry)
    end

    private

    # Every "who is out" question on this page, asked the same way — the
    # picker, the headline count and the roster all read this, so they cannot
    # disagree about who is out.
    #
    # Year-scoped, like Timesheet.find_person_on_duty and so like the "already
    # on duty" flag on the sign-in roster. It also keeps a never-closed entry
    # from a past event off a board where one tap would stamp it off duty now
    # and record a shift tens of thousands of hours long. Those belong to Mass
    # Signout, which shows them precisely so they can be handled deliberately.
    #
    # The joins are inner joins doing real work, not preloading: the
    # Laravel-shared schema has no app-domain foreign keys, so an entry can
    # name a Ranger or a position that no longer exists. Such an entry cannot
    # be signed off at all (TimesheetLog needs the person), and dropping it
    # here rather than in the roster alone is what stops the picker offering a
    # position with nothing tappable under it and the count reporting a
    # Ranger the operator can never find.
    def on_duty_scope
      Timesheet.for_year(Current.year).on_duty_now.joins(:person).joins(:position)
    end

    # Everyone signed up for a shift, spelled once so the roster and the
    # denominator counting it cannot drift apart. The inner join is the point:
    # a person_slot row whose Ranger is gone is neither drawn nor counted.
    def signed_up_scope(slot_id)
      Person.joins(:person_slot).where(person_slot: { slot_id: slot_id })
    end

    def open_entries_for(person_ids)
      return {} if person_ids.empty?

      Timesheet.for_year(Current.year)
               .on_duty_now
               .where(person_id: person_ids)
               .includes(:position)
               .index_by(&:person_id)
    end

    # Group records under their #position, burn positions first and everything
    # else alphabetical.
    def group_by_position(records)
      order_groups(records.group_by(&:position)
                          .map { |position, members| Group.new(position:, members:) })
    end

    # Burn positions first — on the night this page is used, they are what it
    # is used for — then everything else alphabetically.
    def order_groups(groups)
      burn, rest = groups.partition(&:burn?)
      burn.sort_by! { |group| BURN_POSITION_ORDER.index(group.position.id) }
      rest.sort_by! { |group| group.title.to_s.downcase }
      burn + rest
    end
  end
end
