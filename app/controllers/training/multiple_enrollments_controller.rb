# frozen_string_literal: true

# The multiple enrollments report page (Ember training/multiple-enrollments).
# Read-only; resolution, the TrainingPolicy view gate, and @year come from the
# base controller.
class Training::MultipleEnrollmentsController < Training::BaseController
  include CsvExportConcern

  CSV_HEADER = ["Position", "Callsign", "First Name", "Last Name", "Email", "Session",
                "Date", "Timezone"].freeze

  def index
    @report = Training::MultipleEnrollmentReport.execute(@training, @year)

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-multiple-enrollments.csv") }
    end
  end

  private

  # One row per sign-up (upstream has no export at all). Dates stay
  # spreadsheet-sortable; the page renders the house shift format instead.
  #
  # slot.begins is already the session's LOCAL wall-clock time -- the page
  # stamps the zone onto it rather than converting (DateTimeHelper's
  # parse_time_in_zone). Slot#begins_adjusted converts instead, which shifts
  # any session outside the app zone: this report's Green Dot sessions run in
  # BST, MDT and PDT, and a converted MDT session lands an hour late. Hence the
  # raw strftime, plus a Timezone column so two sessions in different zones can
  # actually be compared.
  def csv_rows
    rows = [CSV_HEADER]

    @report.sections.each do |section|
      section.trainees.each do |trainee|
        person = trainee.person

        trainee.slots.each do |slot|
          rows << [section.position_title, person.callsign, person.first_name, person.last_name,
                   person.email, slot.description,
                   slot.begins.strftime(DateTimeHelper::CSV_TIME), slot.timezone_abbr]
        end
      end
    end

    rows
  end
end
