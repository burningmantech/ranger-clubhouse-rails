# frozen_string_literal: true

# Training › Mentoring › Multiple Shifts: the mentees with more than one mentee
# shift this year -- rangered (an entry, on now or ended) or signed up for a
# shift still to come -- with each shift, the verdict on their latest ended
# one, and their mentors. A mentee back for another shift usually has a verdict
# pending from the first, or has passed and should hold the team's positions
# instead of the mentee position.
class ArtMentoring::MultipleShiftsReport
  RANGERED = "rangered"
  SIGNED_UP = "signed-up"
  KINDS = [RANGERED, SIGNED_UP].freeze

  # One mentee. `on_shift` holds the entries still signed in
  # (ArtMentoring::Shifts); `signups` the shifts still to come they signed up
  # for; `walks` their walks by timesheet id.
  Row = Data.define(:person, :entries, :on_shift, :signups, :walks) do
    def rangered = entries.size
    def on_shift? = on_shift.any?
    def signed_up_again? = rangered.positive? && signups.any?

    # The walk on their latest ended shift; nil while none has ended or it
    # has no mentor yet.
    def latest_walk
      ended = (entries - on_shift).max_by(&:on_duty)
      ended && walks[ended.id]
    end

    # Mentors in the order they walked, a deleted account left out.
    def mentors = entries.flat_map { |entry| walks[entry.id]&.rows || [] }.filter_map(&:mentor).uniq

    # @param kind [String] RANGERED, SIGNED_UP, or anything else for all
    def kind?(kind)
      case kind
      when RANGERED then rangered >= 2
      when SIGNED_UP then signed_up_again?
      else true
      end
    end
  end

  attr_reader :rows

  # @param shifts [ArtMentoring::Shifts] the training and year to report on
  def initialize(shifts)
    entries = shifts.mentee_entries.group_by(&:person_id)
    walks = shifts.walks
    on_shift = shifts.on_shift.to_set(&:last)
    people = entries.values.flatten.to_h { |entry| [entry.person_id, entry.person] }
    signups = Hash.new { |by_person, id| by_person[id] = [] }

    # Shifts' upcoming already leaves out whoever signed in early: they are
    # rangering that shift, not signed up for it.
    shifts.upcoming.each do |shift|
      shift.mentees.each do |person|
        people[person.id] ||= person
        signups[person.id] << shift.slot
      end
    end

    @rows = people.filter_map do |id, person|
      mine = entries.fetch(id, []).sort_by(&:on_duty)
      ahead = signups.fetch(id, [])
      next if mine.size + ahead.size < 2

      Row.new(person:, entries: mine, on_shift: mine.select { |entry| on_shift.include?(entry) }, signups: ahead,
              walks: walks.slice(*mine.map(&:id)))
    end.sort_by { |row| row.person.callsign.to_s.downcase }
  end
end
