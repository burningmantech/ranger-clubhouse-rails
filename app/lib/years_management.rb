# frozen_string_literal: true

# Years Management module
# Handles computing and updating various year-based fields on Person records
# including signup years, timesheet years, award years, and combined service years.
module YearsManagement
  class << self
    # Update the years of signups for a person based on their slot signups
    #
    # @param person_id [Integer] The ID of the person
    # @return [void]
    def update_signup_years(person_id)
      person = Person.find(person_id)
      person.years_of_signups = PersonSlot
        .joins(:slot)
        .where(person_id: person_id)
        .group("YEAR(slot.begins)")
        .order("YEAR(slot.begins)")
        .pluck(Arel.sql("YEAR(slot.begins)"))

      save_person(person, "signup years recompute")
    end

    # Update the timesheet years for a person
    # Computes years as contributor, years as ranger, and combined years
    #
    # @param person_id [Integer] The ID of the person
    # @return [void]
    def update_timesheet_years(person_id)
      person = Person.find(person_id)
      person.years_as_contributor = Timesheet.compute_years_for_person(person_id, Timesheet::YEARS_AS_CONTRIBUTOR)
      person.years_as_ranger = Timesheet.compute_years_for_person(person_id, Timesheet::YEARS_AS_RANGER)
      person.years_combined = Timesheet.compute_years_for_person(person_id, Timesheet::YEARS_ALL)

      save_person(person, "timesheet years recompute")
    end

    # Update the years of awards for a person
    #
    # @param person_id [Integer] The ID of the person
    # @return [void]
    def update_years_of_awards(person_id)
      person = Person.find(person_id)
      person.years_of_awards = PersonAward
        .where(person_id: person_id)
        .where(awards_grants_service_year: true)
        .distinct
        .order(:year)
        .pluck(:year)

      save_person(person, "award years recompute")
    end

    # Save the person record after computing combined year fields.
    #
    # Public so callers which compute a year column themselves -- AwardManagement's rebuild,
    # for one -- can fold it into years_seen / years_of_service and persist it.
    #
    # @param person [Person] The person record to save
    # @param reason [String] The audit reason for the change
    # @return [void]
    def save_person(person, reason)
      # Combine years_combined and years_of_signups into years_seen
      seen = (person.years_combined + person.years_of_signups).uniq.sort

      person.years_seen = seen

      # Combine ranger years, award years, and contributor years into years_of_service
      service_years = (person.years_as_ranger + person.years_of_awards + person.years_as_contributor).uniq.sort

      person.years_of_service = service_years

      person.audit_reason = reason
      person.save(validate: false)
    end
  end
end
