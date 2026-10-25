# frozen_string_literal: true

# Training › Mentoring › Multiple Shifts: the mentees with more than one mentee
# shift this year (ArtMentoring::MultipleShiftsReport). Read-only, behind the
# training's view gate (Training::BaseController). The filters narrow the
# table and the CSV follows them.
class Training::Mentoring::MultipleShiftsController < Training::Mentoring::BaseController
  include CsvExportConcern

  def index
    @report = ArtMentoring::MultipleShiftsReport.new(@shifts)
    @filter_params = { kind: UiComponents::FilterBarHelper.known_filter(params[:kind], ArtMentoring::MultipleShiftsReport::KINDS),
                       callsign: params[:callsign].to_s.strip }
    callsign = @filter_params[:callsign].downcase
    @rows = @report.rows.select do |row|
      row.kind?(@filter_params[:kind]) && row.person.callsign.to_s.downcase.include?(callsign)
    end

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{training_slug}-multiple-mentee-shifts-#{@year}.csv") }
    end
  end

  private

  def csv_rows
    header = ["Mentee", "Rangered", "Signed Up", "Shifts", "Latest Verdict", "Mentors"]
    @rows.each_with_object([header]) do |row, rows|
      shifts = row.entries.map { |entry| "#{entry.on_duty.strftime(DateTimeHelper::CSV_TIME)}#{" (on shift)" if row.on_shift.include?(entry)}" } +
               row.signups.map { |slot| "#{slot.begins.strftime(DateTimeHelper::CSV_TIME)} (signed up)" }
      walk = row.latest_walk
      rows << [row.person.callsign, row.rangered, row.signups.size, shifts.join("; "),
               walk ? helpers.mentor_result_label(walk.status) : "", row.mentors.map(&:callsign).join(", ")]
    end
  end
end
