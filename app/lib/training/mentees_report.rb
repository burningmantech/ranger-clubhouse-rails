# frozen_string_literal: true

# The ART Current Mentees report (Laravel ARTMenteesReport): who still holds
# one of an ART's mentee positions, what year each was granted, and what year
# they last rangered it. Current state, not year-scoped.
#
# Only Tow Truck and Green Dot have mentee positions (Training.has_mentees?);
# every other training returns an empty result, same as upstream.
#
# Deliberate delta from upstream: ARTMenteesReport runs one Timesheet query per
# person PER POSITION -- a nested loop that costs ~200 round trips for Green
# Dot. The last-rangered years are read here in one grouped MAX(on_duty).
class Training::MenteesReport
  # One position's standing for one person. granted_year is nil when no open
  # person_position_log row exists (grant tracking only began in 2023);
  # last_rangered_year is nil when they have never rangered it.
  Grant = Data.define(:position, :granted, :granted_year, :last_rangered_year) do
    def granted? = granted
    def never_rangered? = granted && last_rangered_year.nil?
  end

  Mentee = Data.define(:person, :grants) do
    def callsign = person.callsign
    def status = person.status
    def last_rangered_year = grants.filter_map(&:last_rangered_year).max
    # Never rangered ANY of their mentee positions -- the person-level question
    # the page is asked. Per-position gaps are common and normal (a Green Dot
    # mentee rarely also ranges Sanctuary), so a per-grant `any?` here would
    # flag nearly the whole roster and mean nothing.
    def never_rangered? = last_rangered_year.nil?
  end

  Result = Data.define(:positions, :people)

  class << self
    # @param training [Position] the training position
    # @param only [Array<Integer>, nil] restrict the roster to these person ids
    #   -- the turbo_stream row replacement rebuilds one row rather than the
    #   whole report
    # @return [Result]
    def execute(training, only: nil)
      position_ids = Training.mentee_position_ids(training)
      return empty if position_ids.empty?

      # The roster IS the grant list -- everyone listed holds at least one of
      # the positions, so someone who never had one never appears.
      scope = PersonPosition.where(position_id: position_ids)
      scope = scope.where(person_id: only) if only
      grants = scope.pluck(:person_id, :position_id).to_set
      return empty if grants.empty?

      positions = Position.where(id: position_ids).order(:title).to_a
      person_ids = grants.map(&:first).uniq

      Result.new(positions:, people: build_people(positions, person_ids, grants))
    end

    private

    def empty = Result.new(positions: [], people: [])

    def build_people(positions, person_ids, grants)
      granted_years = granted_years_for(positions, person_ids)
      rangered_years = rangered_years_for(positions, person_ids)

      Person.where(id: person_ids).order(:callsign).map do |person|
        grant_list = positions.map do |position|
          key = [person.id, position.id]
          Grant.new(position:,
                    granted: grants.include?(key),
                    granted_year: granted_years[key],
                    last_rangered_year: rangered_years[key])
        end

        Mentee.new(person:, grants: grant_list)
      end
    end

    # { [person id, position id] => year } from the still-open grant log rows.
    # A person with several open rows for one position keeps the earliest --
    # that is when the grant they still hold actually started.
    def granted_years_for(positions, person_ids)
      PersonPositionLog.where(position_id: positions.map(&:id), person_id: person_ids, left_on: nil)
                       .pluck(:person_id, :position_id, :joined_on)
                       .each_with_object({}) do |(person_id, position_id, joined_on), years|
        year = joined_on&.year
        key = [person_id, position_id]
        years[key] = year if year && (years[key].nil? || year < years[key])
      end
    end

    # { [person id, position id] => year } of the most recent timesheet.
    # on_duty is stored UTC, so it is shifted to local before the year is read
    # -- a New Year's Eve shift belongs to the year the person rangered it.
    def rangered_years_for(positions, person_ids)
      Timesheet.where(position_id: positions.map(&:id), person_id: person_ids)
               .group(:person_id, :position_id)
               .maximum(:on_duty)
               .transform_values { |on_duty| on_duty&.getlocal&.year }
               .compact
    end
  end
end
