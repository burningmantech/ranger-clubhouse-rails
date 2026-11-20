# frozen_string_literal: true

# What the public voucher page (/voucher/:id) may say about one person. The
# page is read without signing in, by someone checking a person who has applied
# to an approved Burning Man Regional Event, so this class is the whole gate:
# the view prints only what #shows? allows.
class Voucher
  STATES = {
    Person::ACTIVE => :ranger,
    Person::INACTIVE => :ranger,
    Person::INACTIVE_EXTENSION => :ranger,
    Person::RETIRED => :ranger,
    Person::ALPHA => :applicant,
    Person::PROSPECTIVE => :applicant,
    Person::ECHELON => :echelon,
    Person::PAST_PROSPECTIVE => :not_ranger,
    Person::BONKED => :not_ranger,
    Person::UBERBONKED => :not_ranger,
    Person::AUDITOR => :not_ranger,
    Person::RESIGNED => :not_ranger,
    Person::DISMISSED => :not_ranger,
    Person::DECEASED => :not_ranger,
    Person::SUSPENDED => :unavailable
  }.freeze

  SHOWS = {
    ranger: %i[photo callsign status years positions],
    applicant: %i[photo callsign status],
    echelon: %i[photo callsign],
    not_ranger: %i[photo],
    unavailable: []
  }.freeze

  attr_reader :person, :state

  # nil for an id no one has, and for a status this page has no rule for: a
  # new status shows nothing until someone decides what it may show.
  def self.find(uuid)
    return if uuid.blank?

    person = Person.find_by(uuid:)
    state = STATES[person&.status]
    new(person, state) if state
  end

  def initialize(person, state)
    @person = person
    @state = state
  end

  def shows?(part) = SHOWS.fetch(state).include?(part)

  # Seconds on duty by position title, in title order. Alpha shifts and
  # training sessions are not volunteering, and a shift still running has no
  # length yet. An entry signed out before it was signed in counts as nothing
  # (EventYearSpan::ENTRY_SECONDS), never as a debit.
  def positions
    @positions ||= countable_entries.group("position.title").order("position.title")
                                    .sum(EventYearSpan::ENTRY_SECONDS)
  end

  private

  def countable_entries
    # type is nullable, and NULL != "Training" is not true in SQL.
    untrained = Position.where.not(type: Position::TYPE_TRAINING).or(Position.where(type: nil))
    Timesheet.where(person_id: person.id).where.not(off_duty: nil)
             .where.not(position_id: Position::ALPHA)
             .joins(:position).merge(untrained)
  end
end
