# frozen_string_literal: true

# Thank You Cards: the mailing list for everyone who rangered during a year.
class Vc::ThankYouCardsController < ApplicationController
  include CsvExportConcern

  CSV_HEADER = ["Team", "First", "Last", "AKA/ Playa Name", "Email Address", "Address", "Apt",
                "Address 2", "City", "State", "Country", "Zip", "BPGUID"].freeze

  layout "vc"

  # The year selector's own floor, which the view reads back through the
  # `year_floor` helper. Left at the 1998 default, a URL could ask for a year
  # the selector cannot show, leaving the heading and the selector disagreeing
  # and no way to pick another year.
  self.year_floor = 2008

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to view the Thank You Cards list."

  def index
    setup_year
    @include_statuses = include_statuses
    @people = ThankYouCardsReport.execute(@year, include_statuses: @include_statuses)

    respond_to do |format|
      format.html { setup_summary }
      format.csv { send_csv(csv_rows, filename: "#{@year}-thank-you-cards.csv") }
    end
  end

  private

  # The figures above the table. Only the page needs them, so the export does
  # not pay for building them.
  def setup_summary
    @address_lines = @people.to_h { |person| [person.id, helpers.thank_you_card_address_lines(person)] }
    @status_counts = @people.map(&:status).tally.sort_by { |status, count| [-count, status] }
    @missing_address_count = @address_lines.count { |_id, lines| lines.empty? }
  end

  # Which of the normally-hidden statuses the reader asked to see. Anything
  # else in the URL is ignored, so a stale link cannot widen the list. Kept in
  # the report's own order so the chips read the same way every time.
  def include_statuses
    values = params[:include_statuses]
    values = [values] if values.is_a?(String)
    return [] unless values.is_a?(Array)

    ThankYouCardsReport::OPTIONAL_STATUSES & values.grep(String)
  end

  # Every Ranger is on the same team as far as the card printer is concerned,
  # and the printer addresses people by their playa name.
  def csv_rows
    [CSV_HEADER] + @people.map do |person|
      ["Rangers", person.first_name, person.last_name, "Ranger #{person.callsign}", person.email,
       person.street1, person.apt, person.street2, person.city, person.state,
       helpers.thank_you_card_country(person.country).upcase, person.zip, person.bpguid]
    end
  end
end
