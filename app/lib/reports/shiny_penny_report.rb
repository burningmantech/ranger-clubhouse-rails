# frozen_string_literal: true

# Shiny Pennies: people who became Active during a year and walked an Alpha
# shift in that same year. Anyone whose status moved back off Active before the
# year ended was minted by mistake and is left out.
class ShinyPennyReport
  # Times are compared with YEAR() rather than a Time.zone range: the column
  # values are stored in system-local time, so a zoned range boundary lands an
  # hour off and drags neighbouring-year records in.
  #
  # @param year [Integer]
  # @return [Array<Person>] sorted by callsign
  def self.execute(year)
    alphas = Timesheet.where(position_id: Position::ALPHA).where("YEAR(on_duty) = ?", year).select(:person_id)

    # Plucked oldest-first, so to_h leaves each person's final status of the
    # year. Ending on Active implies they were minted during it, so no separate
    # "became Active" pass is needed.
    penny_ids = PersonStatus.where(person_id: alphas)
                            .where("YEAR(created_at) = ?", year)
                            .order(:created_at, :id)
                            .pluck(:person_id, :new_status)
                            .to_h
                            .filter_map { |person_id, status| person_id if status == Person::ACTIVE }

    Person.where(id: penny_ids).order(:callsign).to_a
  end
end
