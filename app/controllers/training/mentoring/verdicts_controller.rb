# frozen_string_literal: true

# Training › Mentoring › Verdicts: how the year's mentee shifts ended, and each
# mentor's season (ArtMentoring::VerdictsReport). Read-only, behind the
# training's view gate (Training::BaseController). The filters narrow the
# Verdicts table and the CSV follows them; the Mentors table is the season.
class Training::Mentoring::VerdictsController < Training::Mentoring::BaseController
  include CsvExportConcern

  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  def index
    @report = ArtMentoring::VerdictsReport.new(@shifts)
    @filter_params = filter_params
    @verdicts = @report.verdicts.select { |walk| shown?(walk) }

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: "#{training_slug}-mentoring-verdicts-#{@year}.csv") }
    end
  end

  private

  # A value the page does not offer -- a stale bookmark, a typo -- reads as all.
  def filter_params
    mentor_ids = @report.verdicts.filter_map { |walk| walk.mentor_id&.to_s }
    { status: UiComponents::FilterBarHelper.known_filter(params[:status], ArtMentoring::VerdictsReport::VERDICTS),
      mentor_id: UiComponents::FilterBarHelper.known_filter(params[:mentor_id], mentor_ids) }
  end

  def shown?(walk)
    status, mentor_id = @filter_params.values_at(:status, :mentor_id)
    (status == ALL_FILTER || walk.status == status) && (mentor_id == ALL_FILTER || walk.mentor_id.to_s == mentor_id)
  end

  def csv_rows
    header = %w[Mentee Verdict Mentor Shift Length Notes]
    @verdicts.each_with_object([header]) do |walk, rows|
      entry = @report.entry_for(walk)
      rows << [helpers.person_display_name(walk.person, walk.person_id),
               helpers.mentor_result_label(walk.status),
               helpers.person_display_name(walk.mentor, walk.mentor_id, blank: nil),
               entry ? entry.on_duty.strftime(DateTimeHelper::CSV_TIME) : Training::MentoringHelper::SHIFT_DELETED,
               entry ? helpers.hour_minute_format(entry.duration) : "",
               walk.notes.to_s]
    end
  end
end
