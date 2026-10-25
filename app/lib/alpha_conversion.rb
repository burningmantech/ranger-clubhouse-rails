# frozen_string_literal: true

# What this year's mentor verdicts say to do with each Alpha, and the act of
# doing it. Ported from upstream's Mentor page backed by
# MentorController::{verdicts,convertAlphas} and Alpha::retrieveVerdicts.
#
# Eligibility lives here alone: `roster` draws the page and `convert` re-checks
# every submitted id against the same two rules -- the person holds Alpha status,
# and their verdict points at the outcome being asked for -- so a row the page
# offers and a row the POST accepts cannot diverge. Upstream's endpoint checks
# neither, and would flip any person id to either status on request; its own
# client never exercises that, so nothing is lost by closing it.
module AlphaConversion
  # Written to the status-history audit trail, verbatim from upstream.
  AUDIT_REASON = "mentor conversion"

  # The only two outcomes this page produces, and the verdicts that earn each.
  # Upstream validates the requested status against these same two values but
  # never looks at the verdict behind it -- this table is what makes the pairing
  # enforceable.
  VERDICTS_FOR_TARGET = {
    Person::ACTIVE => [PersonMentor::STATUS_PASS].freeze,
    Person::BONKED => [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].freeze
  }.freeze

  # One roster row: the person, their verdict for the year, and the callsigns of
  # whoever walked with them.
  Row = Data.define(:person, :verdict, :mentors) do
    def mint? = verdict == PersonMentor::STATUS_PASS
    def bonk? = [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK].include?(verdict)
  end

  module_function

  # Everyone the page may offer, callsign-ordered: people who hold Alpha status
  # and carry a non-pending verdict for `year`.
  #
  # `keep_ids` holds people on the page who have just been converted. They are
  # no longer Alphas, so the status rule would drop them and the reader would
  # never see what happened -- see the controller's 422 re-render.
  #
  # @return [Array<Row>]
  def roster(year, keep_ids: [])
    verdicts = verdicts_for_year(year)
    keep = keep_ids.to_set
    ids = verdicts.keys.to_set | keep
    return [] if ids.empty?

    # The status filter is in the query rather than in Ruby because by the end of
    # a season most of the year's verdicts belong to people already converted --
    # loading the whole judged cohort to show the remainder gets steadily more
    # wasteful. `keep_ids` is OR-ed back in for exactly those people: they are no
    # longer Alphas, and the filter would drop them off the results render.
    people = Person.where(id: ids, status: Person::ALPHA)
                   .or(Person.where(id: keep.to_a))
                   .order(:callsign)
                   .to_a
    mentors = mentor_callsigns(people.map(&:id), year)

    people.map do |person|
      Row.new(person:, verdict: verdicts[person.id], mentors: mentors[person.id] || [])
    end
  end

  # One verdict per person for the year, as `{ person_id => status }`.
  #
  # Two deliberate differences from upstream's correlated subquery
  # (`SELECT status ... GROUP BY status LIMIT 1` with `HAVING status != pending`):
  #
  #   * The pick is repeatable, and it is the cautious one -- see
  #     PersonMentor::VERDICT_PRECEDENCE. `LIMIT 1` over a grouped set is
  #     arbitrary when a person's same-year rows disagree, so which verdict
  #     upstream reports can change between two reads of the same data.
  #   * A person with both a pending row and a real verdict is listed on the
  #     verdict. Upstream's arbitrary pick might land on "pending", and its
  #     HAVING would then drop the person from the report entirely -- a recorded
  #     verdict that no one can act on.
  #
  # Alphas with no verdict at all are absent from both, which is upstream's
  # behavior and the point of the Alpha Status page.
  #
  # `among` narrows to a submitted selection, so a conversion does not aggregate
  # a whole season's verdicts while it holds row locks.
  def verdicts_for_year(year, among: nil)
    scope = PersonMentor.where(mentor_year: year, position_id: Position::ALPHA)
    scope = scope.where(person_id: among) if among

    scope.where.not(status: PersonMentor::STATUS_PENDING)
         .distinct
         .pluck(:person_id, :status)
         .group_by(&:first)
         .transform_values { |pairs| PersonMentor.year_verdict(pairs.map(&:last)) }
  end

  # Who walked with each of `person_ids` in `year`, as
  # `{ person_id => [callsign] }`. Deliberately year-scoped rather than reusing
  # PersonMentor.retrieve_all_mentors_for_ids, which loads every year a person
  # was ever mentored so this page can discard all but one. The
  # deleted-mentor label matches that method so the two read alike.
  def mentor_callsigns(person_ids, year)
    PersonMentor.where(person_id: person_ids, mentor_year: year, position_id: Position::ALPHA)
                .includes(:mentor)
                .group_by(&:person_id)
                .transform_values do |rows|
                  rows.map { |row| row.mentor&.callsign || "Deleted ##{row.mentor_id}" }.uniq.sort
                end
  end

  # Convert the checked Alphas to `target`, in one transaction with the rows
  # locked. The submitted list is stale by definition -- another mentor may have
  # acted since the page was drawn -- so ids that are no longer Alphas, or whose
  # verdict does not point at `target`, are dropped rather than trusted.
  #
  # Saving is what carries out the conversion: PersonStatusManagement, reached
  # through Person's status callback, writes the status-history row, grants the
  # Shiny Penny position on the way to active, and strips positions and future
  # sign-ups on the way to bonked.
  #
  # @param ids [Array<Integer>] the people a mentor checked
  # @param target [String] Person::ACTIVE or Person::BONKED
  # @param year [Integer]
  # @return [Array<Person>] the people actually converted, by callsign
  def convert(ids, target:, year:)
    verdicts = VERDICTS_FOR_TARGET.fetch(target)

    Person.transaction do
      # Locked before the verdict check, so no one's status can move between
      # being judged eligible and being converted.
      people = Person.where(id: ids, status: Person::ALPHA).order(:callsign).lock.to_a
      allowed = verdicts_for_year(year, among: people.map(&:id))
                .select { |_person_id, verdict| verdicts.include?(verdict) }

      people.select { |person| allowed.key?(person.id) }.each do |person|
        person.status = target
        person.audit_reason = AUDIT_REASON
        person.save!(validate: false)
      end
    end
  end
end
