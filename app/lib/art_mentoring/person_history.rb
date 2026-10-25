# frozen_string_literal: true

# One person's ART walks for Me › Mentoring and Person › Mentoring: the shifts
# they walked as a mentee and the ones they mentored, one section per ART,
# each a cohort per year, newest first, in the shape the Alpha sections use.
# Alpha walks (timesheet_id NULL) are the Alpha readers' and are left out.
# Read-only: a walk is recorded on the ART's roster.
#
# A walk belongs to the ART its mentee entry sits on NOW, as the roster and
# the Verdicts page file it: an entry corrected onto another ART's mentee
# position takes its walk there. With the entry deleted, or moved off every
# mentee position, the walk stays under the position it was recorded for.
# Its year is the entry's, or mentor_year once the entry is gone. A position
# whose team has no ART mentoring training lists its walks under its own
# title, and a position row that no longer exists under "Position #id".
class ArtMentoring::PersonHistory
  # One walk as the page prints it: the person on the other side of it (the
  # mentor of a shift walked, the mentee of a shift mentored; nil once their
  # account is deleted, `other_id` kept for the name), their photo, when the
  # shift started (nil once the entry is deleted), the result, and whether
  # Send Message may be offered to the other person.
  Row = Data.define(:other, :other_id, :avatar, :on_duty, :status, :can_message?)

  # One year of one side, with its tallies (VerdictsReport counts the same way).
  Cohort = Data.define(:year, :rows) do
    def count(*statuses) = rows.count { |row| statuses.include?(row.status) }
    def passed = count(PersonMentor::STATUS_PASS)
    def bonked = count(*ArtMentoring::VerdictsReport::BONKS)
    def pending = count(PersonMentor::STATUS_PENDING)
    # People, not walks: a mentee walked twice in a year is one mentee.
    def mentee_count = rows.map(&:other_id).uniq.size
  end

  # `training` is nil when the walks sit under a position with no ART
  # mentoring training; `as_mentee` and `as_mentor` are cohorts, newest first.
  Section = Data.define(:training, :title, :as_mentee, :as_mentor)

  attr_reader :sections

  # @param person_id [Integer]
  def initialize(person_id)
    @sections = build(person_id)
  end

  # Every walk listed, both sides.
  def shift_count = sections.sum { |section| (section.as_mentee + section.as_mentor).sum { |cohort| cohort.rows.size } }

  private

  def build(person_id)
    walks = PersonMentor.where(person_id:).or(PersonMentor.where(mentor_id: person_id))
                        .where.not(timesheet_id: nil)
                        .includes(:timesheet, mentor: :avatar_photo_attachment, person: :avatar_photo_attachment)
                        .sort_by { |walk| [-walk.timesheet&.on_duty.to_i, walk.id] }
    position_ids = walks.flat_map { |walk| [walk.position_id, walk.timesheet&.position_id] }.compact.uniq
    positions = Position.where(id: position_ids).index_by(&:id)
    trainings = Training.art_mentoring_trainings_by_team(positions.values.filter_map(&:team_id))

    walks.group_by { |walk| home_of(walk, positions, trainings) }.map do |home, list|
      mentee, mentor = list.partition { |walk| walk.person_id == person_id }
      Section.new(training: (home if home.is_a?(Position) && home.has_art_mentoring),
                  title: home.is_a?(Position) ? home.title : "Position ##{home}",
                  as_mentee: cohorts(mentee, :mentor), as_mentor: cohorts(mentor, :person))
    end.sort_by { |section| section.title.downcase }
  end

  # Where a walk is filed: its ART training, else the position it is under,
  # else that position's id once the row is gone.
  def home_of(walk, positions, trainings)
    entry_position = positions[walk.timesheet&.position_id]
    position = positions[walk.position_id]
    position = entry_position if entry_position&.is_art_mentee && trainings[entry_position.team_id]
    (position && trainings[position.team_id]) || position || walk.position_id
  end

  def year_of(walk) = walk.timesheet ? walk.timesheet.on_duty.year : walk.mentor_year

  # The walks as cohorts by year, newest first; `other` names the side of
  # each walk the page prints.
  def cohorts(walks, other)
    walks.group_by { |walk| year_of(walk) }.sort.reverse.map do |year, list|
      Cohort.new(year:, rows: list.map { |walk| row(walk, other) })
    end
  end

  def row(walk, other)
    person, id = (other == :mentor) ? [walk.mentor, walk.mentor_id] : [walk.person, walk.person_id]
    Row.new(other: person, other_id: id, avatar: person&.avatar_photo, on_duty: walk.timesheet&.on_duty,
            status: walk.status, can_message?: person.present? && PersonMentor.can_message?(person))
  end
end
