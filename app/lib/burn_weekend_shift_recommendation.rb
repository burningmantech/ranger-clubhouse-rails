# frozen_string_literal: true

module BurnWeekendShiftRecommendation
  # Determine if a burn weekend shift should be recommended to the person.
  #
  # @param person [Person]
  # @return [Boolean] true if the person should consider signing up for a burn weekend shift
  def self.recommend?(person)
    return false unless person.is_ranger?
    return false unless available_burn_weekend_shifts_for_person?(person)

    start_time, end_time = EventDate.retrieve_burn_weekend_period

    return false if Current.time > end_time

    !Scheduling::Query.signup_in_period?(person.id, start_time, end_time)
  end

  # Are there burn weekend shifts available for the person?
  #
  # @param person [Person]
  # @return [Boolean]
  def self.available_burn_weekend_shifts_for_person?(person)
    start_date, end_date = EventDate.retrieve_burn_weekend_period

    Slot.joins(position: :person_position)
        .where(person_position: { person_id: person.id })
        .where(position: { active: true })
        .where(slot: { active: true })
        .where(begins_year: Current.year)
        .where("(slot.begins BETWEEN :start AND :end) OR (slot.ends BETWEEN :start AND :end)",
               start: start_date, end: end_date)
        .exists?
  end
end
