# frozen_string_literal: true

# One ART mentoring training's mentee shifts for a year, as the Mentoring pages
# read them: the mentee timesheet entries grouped into mentoring shifts, the
# mentors signed in around each, the walk (person_mentor row) recorded for each
# entry, and the shifts still to come with who signed up for them.
#
# Grouping (ruled 2026-10-21). A mentee entry joins the mentee shift it was
# signed in to (timesheet.slot_id) or, with none, the one starting within
# WINDOW of its sign-in -- the nearer of two. Entries that match no shift are
# grouped with each other: the earliest is the anchor, and an entry signing in
# within WINDOW of the anchor joins it. A mentor is on a group's shift when the
# mentor shift they signed in to -- or, with none, their sign-in -- starts
# within WINDOW of the group's start.
#
# WINDOW is these pages' own hour. Alpha Sign-Out and the Mentor Shift Report
# keep different windows on purpose; do not unify them.
#
# Who is on shift, who needs a mentor and who awaits a verdict are counted by
# mentee entry, not by group, and each entry is in one state: no mentor yet
# (needs one -- on shift or after, since a verdict waits on a mentor), paired
# and signed out with the result still Pending (awaits a verdict), or done.
#
# Built once per request, one query per source. A training whose team has no
# ART mentee position flagged lists nothing.
class ArtMentoring::Shifts
  WINDOW = 1.hour
  # A mentee shift runs hours, not days: an entry still open after this was
  # never signed out, and its shift is over (Timesheet.open_within).
  ON_SHIFT_WITHIN = 1.day

  # One mentor of a walk as the roster's slot holds it: the mentor's id (nil
  # for "No mentor"), their notes, and the mentor the slot showed when the page
  # was drawn, whose notes its box held -- the mentor itself, on a stored
  # walk's rows. A submitted row (ArtMentoring::Assignment::Row) reads as these
  # too.
  WalkMentor = Data.define(:id, :notes, :loaded_id) do
    def initialize(id:, notes:, loaded_id: id) = super
  end

  # One entry's walk: its person_mentor rows, one per mentor who walked it,
  # which share a status (ArtMentoring::Assignment writes them together;
  # year_verdict settles rows that disagree), each with its own notes. A pass
  # recorded without a mentor (owner, 2026-10-28) is one row naming none, and
  # has no mentors.
  Walk = Data.define(:rows) do
    def mentor_ids = rows.filter_map(&:mentor_id)
    def status = PersonMentor.year_verdict(rows.map(&:status))
    def mentors = rows.filter_map { |row| WalkMentor.new(id: row.mentor_id, notes: row.notes.to_s) if row.mentor_id }
    def without_mentor? = mentor_ids.empty?
  end

  # One mentoring shift. A group whose entries matched no shift has no slot: it
  # starts at the anchor's sign-in, and its key is "t" plus the anchor's
  # timesheet id, since there is no slot id to put in a URL.
  #
  # `walks` is each entry's Walk by timesheet id, for the entries that have one.
  # Only a pass is recorded without a mentor, so an entry with no walk is a
  # mentee no one has been paired with. `on_shift_entries` are the entries still
  # signed in (ON_SHIFT_WITHIN).
  Group = Data.define(:key, :slot, :begins, :mentee_entries, :on_shift_entries, :mentor_entries, :walks) do
    def unmatched? = slot.nil?
    def ends = slot&.ends
    def in_progress? = on_shift_entries.any?
    def walk_for(entry) = walks[entry.id]
    def mentors = mentor_entries.map(&:person).uniq
    def mentee_count_for(mentor) = walks.values.count { |walk| walk.mentor_ids.include?(mentor.id) }
    def needing_mentor = mentee_entries.reject { |entry| walks.key?(entry.id) }
    # Each mentee's first entry: someone signed in twice is one mentee, and the
    # roster shows their general notes on that entry's rows.
    def first_entries = mentee_entries.uniq(&:person_id)

    # The sign-ins it lists: the hour either side of a shift's start, or the
    # hour from an unmatched group's anchor (an earlier one would have been the
    # anchor).
    def window = (unmatched? ? begins : begins - WINDOW)..(begins + WINDOW)
    def passed = mentee_entries.select { |entry| walks[entry.id]&.status == PersonMentor::STATUS_PASS }

    # The entries signed out with a mentor and no verdict yet (still Pending).
    def awaiting_verdict
      (mentee_entries - on_shift_entries).select { |entry| walks[entry.id]&.status == PersonMentor::STATUS_PENDING }
    end
  end

  # A mentee shift still to come: who signed up for it (less anyone already
  # signed in to it early), and who signed up for the mentor shift paired with it.
  Upcoming = Data.define(:slot, :mentees, :mentors) do
    def needs_mentor? = mentees.any? && mentors.empty?
  end

  # `mentee_entries` and `mentor_entries` are every entry of the year on each
  # position, in a group or on its shift or not; `walks` the mentee entries'
  # Walks by timesheet id.
  attr_reader :training, :year, :now, :mentee_position, :mentor_position, :groups, :upcoming, :mentee_entries,
              :mentor_entries, :walks

  # @param training [Position] an ART mentoring training (has_art_mentoring)
  # @param year [Integer]
  def initialize(training, year)
    @training = training
    @year = year
    @now = Current.time
    @mentee_position = find_position(Training.mentee_position_id(training))
    @mentor_position = find_position(Training.mentor_position_id(training))
    @groups = []
    @upcoming = []
    @mentee_entries = []
    @mentor_entries = []
    @walks = {}
    load_shifts if @mentee_position
  end

  def group(key) = groups.find { |group| group.key == key }

  # The group a mentee entry belongs to; nil for an entry outside this year's.
  def group_for(timesheet_id)
    @group_for ||= groups.flat_map { |group| group.mentee_entries.map { |entry| [entry.id, group] } }.to_h
    @group_for[timesheet_id]
  end

  def upcoming_shift(key) = upcoming.find { |shift| shift.slot.id.to_s == key }

  def in_progress = groups.select(&:in_progress?)

  # Newest first: the shift that just ended is the one waiting on verdicts.
  def completed = groups.reject(&:in_progress?).reverse

  # Every mentee signed in now, with their group.
  # @return [Array<Array(Group, Timesheet)>]
  def on_shift = groups.flat_map { |group| group.on_shift_entries.map { |entry| [group, entry] } }

  def needing_mentor_count = groups.sum { |group| group.needing_mentor.size }

  def awaiting_verdict_count = groups.sum { |group| group.awaiting_verdict.size }

  def upcoming_signup_count = upcoming.sum { |shift| shift.mentees.size }

  # Everyone holding the mentor position, callsign-sorted: the mentor select
  # offers them after the mentors on the shift (ruled 2026-10-21), and the save
  # accepts them. Only what the select and the save read is loaded.
  def mentor_holders
    @mentor_holders ||= if mentor_position
                          Person.joins(:person_position).where(person_position: { position_id: mentor_position.id })
                                .order(:callsign).select(:id, :callsign).to_a
                        else
                          []
                        end
  end

  # What a pass can also do for these mentees: join the training's team, lose
  # the mentee positions (ArtMentoring::Pass).
  def pass = @pass ||= ArtMentoring::Pass.new(training, mentee_position)

  # Who may be recorded as a mentee's mentor on this group's shift. A mentor
  # already recorded on a walk stays recordable on it after losing the position
  # (ArtMentoring::Assignment), or a re-save would fail for a past walk.
  def assignable_mentor_ids(group) = (group.mentors.map(&:id) + mentor_holders.map(&:id)).to_set

  # Each person's entries in the year's other groups, with the group: the walks
  # a mentor reads before passing someone who walked before.
  # @return [Array<Array(Group, Timesheet)>]
  def other_entries(person_ids, except: nil)
    ids = person_ids.to_set
    groups.reject { |group| group.equal?(except) }.flat_map do |group|
      group.mentee_entries.filter_map { |entry| [group, entry] if ids.include?(entry.person_id) }
    end
  end

  private

  def find_position(id) = id && Position.find_by(id:)

  def load_shifts
    mentee_slots = slots_for(mentee_position)
    mentor_slots = slots_for(mentor_position)
    # Sign-ups are read only for shifts still to come, and for the mentor
    # shifts within the hour of one.
    ActiveRecord::Associations::Preloader.new(
      records: (mentee_slots + mentor_slots).select { |slot| slot.begins > now - WINDOW }, associations: :sign_ups
    ).call
    @mentee_entries = entries_for(mentee_position)
    @mentor_entries = entries_for(mentor_position)
    # By entry alone, the walk's key: an entry corrected onto this position
    # from another ART's mentee position brings its walk, and the next save
    # files the walk here (ArtMentoring::Assignment).
    @walks = PersonMentor.where(timesheet_id: mentee_entries.map(&:id)).includes(:mentor).order(:id)
                         .group_by(&:timesheet_id).transform_values { |rows| Walk.new(rows:) }

    @groups = build_groups(mentee_slots, mentor_slots)
    @upcoming = build_upcoming(mentee_slots, mentor_slots)
  end

  def slots_for(position)
    return [] unless position

    Slot.for_year(year).for_position(position.id).ordered_by_begins.to_a
  end

  def entries_for(position)
    return [] unless position

    Timesheet.for_year(year).for_position(position.id).includes(:person).ordered_by_on_duty.to_a
  end

  def build_groups(mentee_slots, mentor_slots)
    slots_by_id = mentee_slots.index_by(&:id)
    by_slot = Hash.new { |members, slot| members[slot] = [] }
    loose = []

    mentee_entries.each do |entry|
      slot = slots_by_id[entry.slot_id] || nearest(mentee_slots, entry.on_duty)
      slot ? by_slot[slot] << entry : loose << entry
    end

    starts = by_slot.map { |slot, members| [slot.id.to_s, slot, slot.begins, members] } +
             cluster(loose).map { |members| ["t#{members.first.id}", nil, members.first.on_duty, members] }

    # Each mentor's start as an integer, once: every group compares against
    # every mentor entry.
    mentor_slot_starts = mentor_slots.to_h { |slot| [slot.id, slot.begins] }
    mentor_starts = mentor_entries.map { |entry| (mentor_slot_starts[entry.slot_id] || entry.on_duty).to_i }
    window = WINDOW.to_i
    starts.map do |key, slot, begins, members|
      at = begins.to_i
      on_shift = mentor_entries.select.with_index { |_entry, i| (mentor_starts[i] - at).abs <= window }
      Group.new(key:, slot:, begins:, mentee_entries: members, on_shift_entries: members.select { |entry| signed_in?(entry) },
                mentor_entries: on_shift, walks: walks.slice(*members.map(&:id)))
    end.sort_by(&:begins)
  end

  def signed_in?(entry) = entry.off_duty.nil? && entry.on_duty.between?(now - ON_SHIFT_WITHIN, now)

  def nearest(slots, time)
    slots.select { |slot| (slot.begins - time).abs <= WINDOW }.min_by { |slot| (slot.begins - time).abs }
  end

  # Sorted by sign-in, so an entry can only belong to the newest cluster.
  def cluster(entries)
    entries.sort_by(&:on_duty).each_with_object([]) do |entry, clusters|
      if clusters.any? && entry.on_duty - clusters.last.first.on_duty <= WINDOW
        clusters.last << entry
      else
        clusters << [entry]
      end
    end
  end

  # Shifts still to start that someone has signed up for: an empty future
  # shift asks nothing of anyone. A mentee who signed in early is on the
  # shift's roster instead, so a shift whose sign-ups have all arrived is gone.
  def build_upcoming(mentee_slots, mentor_slots)
    mentee_slots.filter_map do |slot|
      next if slot.begins <= now

      signed_in = (group(slot.id.to_s)&.mentee_entries || []).to_set(&:person_id)
      mentees = slot.sign_ups.reject { |person| signed_in.include?(person.id) }
      mentors = mentor_slots.select { |mentor_slot| (mentor_slot.begins - slot.begins).abs <= WINDOW }
                            .flat_map(&:sign_ups).uniq
      next if mentees.empty? && (signed_in.any? || mentors.empty?)

      Upcoming.new(slot:, mentees: by_callsign(mentees), mentors: by_callsign(mentors))
    end
  end

  def by_callsign(people) = people.sort_by { |person| person.callsign.to_s.downcase }
end
