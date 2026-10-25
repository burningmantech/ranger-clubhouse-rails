# frozen_string_literal: true

# Training › Mentoring › Verdicts: how the year's walks ended, newest shift
# first, and each mentor's season -- the mentor shifts they signed in to, whom
# they walked on each, and how those walks ended.
#
# A walk outlives its mentee's deleted timesheet entry (ruled 2026-10-21): it
# is listed as "Shift deleted" and still counts for its mentor, and no page
# can change it after that. An entry moved off every mentee position keeps its
# walk too; it is listed with that entry's time. An entry corrected onto
# another ART's mentee position takes its walk there, as on the roster.
class ArtMentoring::VerdictsReport
  # What a walk can end with: every result but Pending.
  VERDICTS = (PersonMentor::STATUSES - [PersonMentor::STATUS_PENDING]).freeze
  BONKS = [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].freeze

  # One mentor's season. `person` is nil once the account is deleted.
  Mentor = Data.define(:id, :person, :entries, :walks, :lines) do
    def mentee_count = walks.map(&:person_id).uniq.size
    def count(*statuses) = walks.count { |walk| statuses.include?(walk.status) }

    # Over their ended mentor shifts; nil with none.
    def average_length
      ended = entries.select(&:off_duty)
      ended.sum(&:duration) / ended.size if ended.any?
    end
  end

  # A line of a mentor's details: one of their own mentor shifts with the walks
  # on it, or -- `entry` nil -- other walks starting at `begins`: on a mentee
  # shift they did not sign in to as a mentor (`off_shift`), or on an entry
  # moved off the mentee position, or deleted (`begins` nil).
  Line = Data.define(:entry, :begins, :walks, :off_shift) do
    def initialize(entry:, begins:, walks:, off_shift: false) = super
  end

  attr_reader :shifts, :walks

  # @param shifts [ArtMentoring::Shifts] the training and year to report on
  def initialize(shifts)
    @shifts = shifts
    walks = load_walks
    @entries = shifts.mentee_entries.index_by(&:id)
    elsewhere = walks.map(&:timesheet_id) - @entries.keys
    @entries.merge!(Timesheet.where(id: elsewhere).index_by(&:id)) if elsewhere.any?
    # Newest first; a deleted entry's walk (0) last.
    @walks = walks.sort_by { |walk| -started(walk).to_i }
  end

  # The mentee's timesheet entry a walk was recorded on; nil once deleted.
  def entry_for(walk) = @entries[walk.timesheet_id]

  # When the walk's shift started; nil once its entry is deleted.
  def started(walk) = entry_for(walk)&.on_duty

  # The walks that ended with a verdict, newest shift first.
  def verdicts = walks.select { |walk| VERDICTS.include?(walk.status) }

  # Mentee shifts, not rows: a mentee walked by two mentors passed once.
  def count(*statuses) = walks.select { |walk| statuses.include?(walk.status) }.uniq(&:timesheet_id).size

  # Everyone who signed in to the mentor position this year or walked with a
  # mentee, by callsign.
  def mentors
    @mentors ||= begin
      entries = shifts.mentor_entries.group_by(&:person_id)
      walks_by = walks.group_by(&:mentor_id)
      people = (shifts.mentor_entries.map(&:person) + walks.map(&:mentor)).compact.index_by(&:id)

      (entries.keys | walks_by.keys).map do |id|
        own = entries.fetch(id, []).sort_by(&:on_duty)
        mine = walks_by.fetch(id, [])
        Mentor.new(id:, person: people[id], entries: own, walks: mine, lines: lines_for(own, mine))
      end.sort_by { |mentor| mentor.person&.callsign.to_s.downcase }
    end
  end

  private

  # Every ART walk of the year: the walks on this year's mentee entries
  # (ArtMentoring::Shifts, which finds them by entry), and those filed here
  # whose entry is not among them -- deleted, or moved off every mentee
  # position -- but not one whose entry now sits on another ART's mentee
  # position. Alpha walks leave timesheet_id NULL.
  def load_walks
    return [] unless shifts.mentee_position

    elsewhere = Training.cadre_position_ids(:mentee) - [shifts.mentee_position.id]
    rest = PersonMentor.where(position_id: shifts.mentee_position.id, mentor_year: shifts.year)
                       .where.not(timesheet_id: nil).where.not(timesheet_id: shifts.walks.keys)
                       .where.not(timesheet_id: Timesheet.where(position_id: elsewhere).select(:id))
                       .includes(:mentor).to_a
    walks = shifts.walks.values.flat_map(&:rows) + rest
    ActiveRecord::Associations::Preloader.new(records: walks, associations: :person).call
    walks
  end

  # Each of the mentor's shifts takes the walks on the mentee shift it was
  # signed in around; the walks left over are grouped by their mentee shift,
  # or with none, by when they started.
  def lines_for(entries, walks)
    left = walks
    own = entries.map do |entry|
      here, left = left.partition { |walk| shifts.group_for(walk.timesheet_id)&.mentor_entries&.include?(entry) }
      Line.new(entry:, begins: entry.on_duty, walks: here)
    end
    others = left.group_by { |walk| shifts.group_for(walk.timesheet_id)&.key }.flat_map do |key, list|
      next [Line.new(entry: nil, begins: shifts.group(key).begins, walks: list, off_shift: true)] if key

      list.group_by { |walk| started(walk) }.map { |begins, same| Line.new(entry: nil, begins:, walks: same) }
    end

    (own + others).sort_by { |line| [line.begins ? 0 : 1, line.begins.to_i] }
  end
end
