# frozen_string_literal: true

# ART graduation: who on the session's roster may be granted the ART's
# positions, and the grant itself (upstream graduationCandidates /
# graduateCandidates).
#
# DELIBERATE FIX (decided 2026-07-31): candidacy requires an explicit
# passed TraineeStatus. Upstream treated ANY scoring record -- including a
# fail -- as passed; here a failed trainee lists as not-passed.
class TrainingSession::Graduation
  CANDIDATE = "candidate"
  REQUIREMENTS_INCOMPLETE = "requirements-incomplete"
  # An eligibility bucket: anyone whose trainee status is not a pass --
  # pending, no-show and not-passed alike. Spelled like
  # TraineeStatus::STATUS_NOT_PASSED but not the same thing, so the two are
  # never compared or merged.
  NOT_PASSED = "not-passed"
  AUDITOR = "auditor"
  GRADUATED = "graduated"
  FULLY_GRADUATED = "fully-graduated"

  GRANT_REASON = "granted via graduate trainee"

  # Shortfall against the ART's mentee requirements, shown on the override
  # rows. Only present for REQUIREMENTS_INCOMPLETE candidates.
  Gaps = Data.define(:shifts, :req_shifts, :hours, :req_hours, :events, :req_events) do
    def messages
      list = []
      if shifts < req_shifts
        list << "Has #{shifts} eligible #{"shift".pluralize(shifts)} — the minimum is #{req_shifts}."
      end
      if hours < req_hours
        list << "Has #{hours.round(1)} eligible #{"hour".pluralize(hours.ceil)} — the minimum is #{req_hours}."
      end
      if events < req_events
        list << "Has volunteered for #{events} #{"event".pluralize(events)} excluding this one — the minimum is #{req_events}."
      end
      list
    end
  end

  Candidate = Data.define(:person, :eligibility, :gaps) do
    def selectable? = [CANDIDATE, REQUIREMENTS_INCOMPLETE].include?(eligibility)

    def override? = eligibility == REQUIREMENTS_INCOMPLETE
  end

  Result = Data.define(:person_id, :callsign, :status)

  attr_reader :session

  # @param session [TrainingSession]
  def initialize(session)
    @session = session
  end

  # Does this ART grant positions after training at all?
  def offered? = config.present?

  # @return [Array<Array(Integer, String)>] [position id, title] pairs granted
  def positions
    @positions ||= (config&.fetch(:positions) || []).map { |id| [id, position_titles_by_id[id]] }
  end

  def position_titles = positions.map(&:last)

  # The "been there for years" position whose holders are skipped, when the
  # ART defines one.
  # @return [Array(Integer, String), nil]
  def veteran_position
    return nil unless config&.dig(:veteran)

    @veteran_position ||= [config[:veteran], position_titles_by_id[config[:veteran]]]
  end

  # Every signed-up person bucketed by eligibility, callsign order.
  # @return [Array<Candidate>]
  def candidates
    @candidates ||= build_candidates
  end

  def selectable = candidates.select(&:selectable?)

  def ready = candidates.select { |c| c.eligibility == CANDIDATE }

  def overrides = candidates.select(&:override?)

  def ineligible = candidates.reject(&:selectable?)

  # Grant the ART's positions to the chosen candidates. Only candidate /
  # requirements-incomplete people are granted; everyone else in ids reports
  # their eligibility (or not-found) untouched.
  # @param ids [Array<Integer>] person ids picked in the dialog
  # @return [Array<Result>]
  def graduate!(ids)
    by_person_id = candidates.index_by { |c| c.person.id }
    position_ids = positions.map(&:first)

    ids.map do |id|
      candidate = by_person_id[id]
      if candidate.nil?
        Result.new(person_id: id, callsign: nil, status: "not-found")
      elsif candidate.selectable?
        PersonPosition.add_ids_to_person(id, position_ids, GRANT_REASON)
        Result.new(person_id: id, callsign: candidate.person.callsign, status: "success")
      else
        Result.new(person_id: id, callsign: candidate.person.callsign, status: candidate.eligibility)
      end
    end
  end

  private

  def config
    Position::ART_GRADUATE_TO_POSITIONS[session.training.id]
  end

  # One title lookup for the granted + veteran positions together.
  def position_titles_by_id
    @position_titles_by_id ||=
      Position.titles_by_id([*(config&.fetch(:positions) || []), config&.dig(:veteran)].compact)
  end

  def build_candidates
    return [] unless offered?

    roster = PersonSlot.where(slot_id: session.slot.id).includes(:person)
                       .sort_by { |ps| ps.person.callsign.downcase }
    return [] if roster.empty?

    ids = roster.map(&:person_id)
    passed_ids = TraineeStatus.passed.where(slot_id: session.slot.id, person_id: ids)
                              .pluck(:person_id)
                              .to_set
    grant_ids = positions.map(&:first)
    veteran_id = veteran_position&.first
    held = PersonPosition.where(person_id: ids, position_id: [*grant_ids, veteran_id].compact)
                         .pluck(:person_id, :position_id)
                         .group_by(&:first)
                         .transform_values { |pairs| pairs.map(&:last).to_set }

    timesheet_stats = requirement_stats(passed_ids)

    roster.map do |person_slot|
      person = person_slot.person
      eligibility, gaps = resolve_eligibility(person, held[person.id] || Set.new,
                                              passed_ids, grant_ids, veteran_id, timesheet_stats)
      Candidate.new(person:, eligibility:, gaps:)
    end
  end

  def resolve_eligibility(person, held, passed_ids, grant_ids, veteran_id, timesheet_stats)
    return [AUDITOR, nil] if person.status == Person::AUDITOR
    return [FULLY_GRADUATED, nil] if veteran_id && held.include?(veteran_id)
    return [GRADUATED, nil] if grant_ids.any? { |id| held.include?(id) }
    return [NOT_PASSED, nil] unless passed_ids.include?(person.id)

    gaps = requirement_gaps(person, timesheet_stats)
    gaps ? [REQUIREMENTS_INCOMPLETE, gaps] : [CANDIDATE, nil]
  end

  # One grouped shift-count + elapsed-seconds aggregate for everyone who
  # passed (only they reach the requirements check). TIMESTAMPDIFF has no
  # ActiveRecord expression form (upstream selectRaw equivalent).
  # @return [Hash{Integer => Array(Integer, Numeric)}] person_id => [shifts, seconds]
  def requirement_stats(passed_ids)
    requirements = config[:mentee_requirements]
    return {} unless requirements && passed_ids.any?

    scope = Timesheet.where(person_id: passed_ids.to_a)
    scope = scope.where(position_id: requirements[:positions]) if requirements[:positions].present?
    scope.group(:person_id)
         .pluck(:person_id,
                Arel.sql("COUNT(*)"),
                Arel.sql("SUM(TIMESTAMPDIFF(SECOND, on_duty, COALESCE(off_duty, NOW())))"))
         .to_h { |person_id, shifts, seconds| [person_id, [shifts, seconds]] }
  end

  # Nil when requirements are met (or the ART defines none); otherwise the
  # shortfall for the override row.
  def requirement_gaps(person, timesheet_stats)
    requirements = config[:mentee_requirements]
    return nil unless requirements

    shifts, seconds = timesheet_stats[person.id]
    shifts ||= 0
    hours = (seconds || 0) / 3600.0

    req_events = requirements[:event_count] || 0
    events = if req_events.positive?
               (person.years_as_ranger || []).reject { |year| year == Current.year }.size
             else
               0
             end

    return nil if shifts >= requirements[:shift_count] && hours >= requirements[:hour_count] && events >= req_events

    Gaps.new(
      shifts:, req_shifts: requirements[:shift_count],
      hours:, req_hours: requirements[:hour_count],
      events:, req_events:
    )
  end
end
