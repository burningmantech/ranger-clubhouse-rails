# frozen_string_literal: true

# The all-trainee-notes report page (Ember training/:position_id/notes, "All
# ART Trainee Notes"). Read-only; resolution, the view gate, and @year come
# from the base controller.
#
# Upstream's TrainingPolicy::trainingNotes requires is_art plus
# ART_INTERFACE_BASE | position.id -- that composed role is this app's
# ART_TRAINER_BASE (the same 0x1000000 bit), which is exactly what
# Training.view_roles already demands of an ART. So the inherited gate is the
# whole role check, and the only rule left to add is the ART restriction.
class Training::AllNotesController < Training::BaseController
  include CsvExportConcern

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER
  # The notes filter is a checkbox, so it is either on or inactive.
  NOTES_ONLY = "1"

  CSV_HEADER = ["Callsign", "Status", "Standing", "Session", "Timezone", "Description",
                "Rank", "Passed", "Notes"].freeze

  before_action :require_art_training

  def index
    @report = Training::TraineeNotesReport.execute(@training, @year)
    @notes_only = params[:notes] == NOTES_ONLY
    @filter_params = filter_params
    @people = filtered(@report)
    @standing_counts = @report.group_by(&:standing).transform_values(&:size)

    respond_to do |format|
      format.html
      # The export is the whole report, not the current view -- the filters
      # narrow the page to read, the CSV is the record of the year.
      format.csv { send_csv(csv_rows, filename: "#{@year}-#{training_slug}-all-notes.csv") }
    end
  end

  private

  # In-Person Training has no ART interface role to hold, and upstream's policy
  # refuses the endpoint outright for it. The menu leaves the item off the
  # In-Person category for the same reason; this catches the typed URL.
  def require_art_training
    return if Training.art?(@training)

    redirect_to training_path(training_slug, year: @year),
                error: "All Trainee Notes is an ART report — In-Person Training does not have one."
  end

  # The checkbox is spelled as a filter-bar sentinel so it draws a chip and
  # drops out of URLs like every other filter (FilterBarHelper.active_filters).
  def filter_params
    { standing: params[:standing].presence || ALL_FILTER,
      notes: @notes_only ? NOTES_ONLY : ALL_FILTER }
  end

  # In memory: the report is already a small array, and re-querying would have
  # to re-derive the whole thing.
  def filtered(people)
    standing = @filter_params[:standing]

    people.select do |trainee|
      (standing == ALL_FILTER || trainee.standing == standing) && (!@notes_only || trainee.notes?)
    end
  end

  # One row per session entry, so a person who passed twice exports twice and a
  # note left on a session they did not pass exports against that session --
  # hence the Passed column.
  #
  # slot.begins is already the session's LOCAL wall-clock time, so it is
  # exported raw and paired with its zone; Slot#begins_adjusted would CONVERT
  # it and shift every session outside the app zone (a real hazard here: 2026's
  # Green Dot sessions run in seven zones, BST through PDT).
  def csv_rows
    rows = [CSV_HEADER]

    @report.each do |trainee|
      trainee.sessions.each do |entry|
        rows << [trainee.callsign,
                 trainee.status,
                 trainee.standing,
                 entry.slot.begins.strftime(DateTimeHelper::CSV_TIME),
                 entry.slot.timezone_abbr,
                 entry.slot.description,
                 entry.rank,
                 entry.passed ? "Yes" : "No",
                 note_text(entry.notes)]
      end
    end

    rows
  end

  # Upstream's format: a lone note exports as itself, several are numbered so
  # they stay readable inside one cell.
  def note_text(notes)
    return notes.first&.note.to_s if notes.size <= 1

    notes.each_with_index.map { |note, index| "Note ##{index + 1}:\n#{note.note}\n" }.join
  end
end
