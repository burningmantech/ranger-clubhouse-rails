# frozen_string_literal: true

# Looks up person records for a pasted list of callsigns and email addresses.
#
# Lines with an @ are matched as email addresses, everything else as callsigns
# with capitalisation, punctuation, and accents ignored. Lines that match
# no one, or that match more than one person, are listed back so the reader
# can sort them out and run the list again. The matches and the misses each
# export as their own CSV, rebuilt from the posted list.
#
# Not year scoped: the lookup reads each person's record as it stands today.
class People::BulkLookupController < ApplicationController
  include CsvExportConcern

  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to look up people in bulk."

  # A generous ceiling. Real lists run to a few hundred lines; far past that
  # the request would grind, so it refuses instead.
  MAX_LINES = 1000

  FOUND_CSV_HEADER = ["Callsign", "Legal First Name", "Preferred Name", "Last Name",
                      "Status", "Email", "Last Rangered", "Vintage", "Years Rangered",
                      "Address", "Apt", "Address 2", "City", "State", "Postal Code",
                      "Country", "Home Phone"].freeze

  def index
  end

  # Renders the results under the form. The pasted list rides in the request
  # body, so a fresh page load could not rebuild the results -- they render
  # straight from this post instead.
  def lookup
    # Only a plain string is a pasted list. Sent as ?lines[]=x it arrives as
    # an array and as ?lines[a]=b a Parameters object, and either one would
    # travel to the page and print itself where the list belongs.
    @lines = params[:lines].is_a?(String) ? params[:lines] : ""
    line_count = BulkLookupReport.lines(@lines).size

    if line_count.zero?
      @refusal = "Enter at least one callsign or email address, one per line."
    elsif line_count > MAX_LINES
      @refusal = "That list has #{line_count} lines. " \
                 "Split it into lists of #{MAX_LINES} lines or fewer."
    else
      @results = BulkLookupReport.execute(@lines)
    end

    respond_to do |format|
      format.html { render :index, status: :unprocessable_entity }
      format.csv { send_subset_csv }
    end
  end

  private

  # Refuses to guess which file was meant: an export request must name one of
  # the two lists, and a refused lookup has no lists to export.
  def send_subset_csv
    return head :unprocessable_entity if @refusal

    case params[:subset]
    when "found" then send_csv(found_rows, filename: "bulk-lookup-found.csv")
    when "not_found" then send_csv(not_found_rows, filename: "bulk-lookup-not-found.csv")
    else head :bad_request
    end
  end

  def found_rows
    [FOUND_CSV_HEADER] + @results.found.map do |person|
      years = person.years_as_ranger
      [person.callsign, person.first_name, person.preferred_name, person.last_name,
       person.status, person.email, years.last || "never", csv_yes_no(person.vintage),
       years.size, person.street1, person.apt, person.street2, person.city,
       person.state, person.zip, person.country, formatted_phone(person)]
    end
  end

  def not_found_rows
    [["Not Found Callsign/Email"]] +
      (@results.not_found + @results.ambiguous).map { |line| [line] }
  end

  # A phone written as digits with a leading plus would be misread as a
  # formula by a spreadsheet; formatting it sidesteps that. A number too odd
  # to format goes out as typed.
  def formatted_phone(person)
    person.home_phone_formatted.presence || person.home_phone
  end
end
