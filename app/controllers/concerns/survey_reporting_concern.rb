# frozen_string_literal: true

# A survey's feedback report and the per-subject drill-down beneath it, shared
# by the two interfaces that read surveys: a training position's own surveys
# (Training::SurveysController) and the Mentors' Alpha surveys
# (Mentoring::SurveysController).
#
# Everything here is scope-free -- it walks whatever SurveyBuilder returns and
# knows nothing about which surveys the page serves. The host controller
# supplies that, plus the URLs the shared views link to:
#
#   load_survey              set @survey, or redirect
#   authorize_survey_report  the read gate for @survey
#   surveys_index_path       the index this page hangs off
#   surveys_index_label      what a back link calls that index
#   survey_report_url(survey, report_id, **extra)
#   survey_person_url(person_id, **extra)
#   csv_slug                 what a download filename calls this interface
#
# session_url defaults to "no session page"; an interface that has one
# overrides it.
module SurveyReportingConcern
  extend ActiveSupport::Concern

  include CsvExportConcern
  # For survey_std_dev / survey_distribution_text: the exports and the page
  # share one set of statistics formatters.
  include SurveyReportHelper

  included do
    # Declared here, in the order they must run: the host defines the first
    # two, so a host that forgets one fails loudly rather than rendering a
    # report it never authorized.
    before_action :load_survey, only: [:report, :trainer]
    before_action :authorize_survey_report, only: [:report, :trainer]
    before_action :load_report_links, only: [:report, :trainer]
    before_action :load_slots, only: [:report, :trainer]

    helper_method :trainer_survey?, :session_url, :report_path,
                  :trainer_key, :trainer_questions,
                  :surveys_index_path, :surveys_index_label,
                  :survey_report_url, :survey_person_url
  end

  def report
    if trainer_survey?
      # A trainer-on-trainer survey has no per-group split: the whole survey
      # is one report, built one trainer at a time.
      @trainers = SurveyBuilder.all_trainers_report(@survey)
    else
      reports = SurveyBuilder.build_survey_reports(@survey, nil, true)
      @report = reports.find { |report| report.id.to_s == params[:report_id] }
      @trainers = @report&.trainers || []
    end

    @summarized_ratings = rankable_ratings(@report)

    respond_to do |format|
      # The totals are the page's stat boxes and roster counts. Counting them
      # walks the whole report twice over, and an export reads none of them.
      format.html do
        count_totals
        @trainer_ratings = count_trainer_ratings
      end
      format.csv { send_report_csv }
    end
  end

  def trainer
    @person = Person.find_by(id: params[:person_id])
    unless @person
      redirect_to report_path, error: "That person was not found."
      return
    end

    load_trainer_feedback

    respond_to do |format|
      format.html { count_totals }
      format.csv do
        send_csv(feedback_csv_rows, filename: csv_filename("#{@person.callsign}-comments"))
      end
    end
  end

  private

  # --- host seams ------------------------------------------------------------

  # Where a session's own page lives, or nil when it has none -- mentor,
  # mentee, and Alpha surveys hang off shifts, which have no session page. The
  # shared view asks for the URL rather than for permission to build one, so it
  # never has to name an interface's routes.
  def session_url(_slot)
    nil
  end

  # --- loading ---------------------------------------------------------------

  # The survey's own report list -- also the page's report navigation. Shared
  # with the index through Survey#report_list, so a link the index offers can
  # never be a report this page rejects.
  def load_report_links
    @report_links = @survey.report_list
    current = @report_links.find { |link| link[:id].to_s == params[:report_id] }
    @report_title = current&.dig(:title)

    return if current
    # The per-subject page hangs off a survey, not a single report, so it has
    # no report_id to check.
    return if action_name == "trainer"

    redirect_to surveys_index_path, error: "That survey report was not found."
  end

  # Full slot records for the sessions the survey covers. SurveyBuilder's slot
  # responses carry only id, a stringified begins, and a description; display
  # needs the timezone, and the session link needs the position.
  def load_slots
    @slots = Slot.where(begins_year: @survey.year, position_id: @survey.position_id).index_by(&:id)
  end

  # One subject's feedback. A trainer-on-trainer survey reports through its
  # main group; a student-on-trainer group nests the same questions under the
  # trainer, so both shapes normalize to one list of questions here.
  def load_trainer_feedback
    reports = SurveyBuilder.build_survey_reports(@survey, @person.id, true)

    report = if trainer_survey?
               reports.first
             else
               reports.find { |candidate| candidate.type == SurveyGroup::TYPE_TRAINER }
             end

    @questions = if trainer_survey?
                   report&.questions || []
                 else
                   report&.trainers&.first&.questions || []
                 end
    @summarized_ratings = rankable_ratings(report)
  end

  # A summarized rating with neither people nor sessions under it has nothing
  # to rank, so it never renders as an empty ranked table. SurveyBuilder no
  # longer produces one -- an Alpha summarize_rating question degrades to a
  # plain rating question there -- so this is a cheap invariant, not a filter
  # that hides answers.
  def rankable_ratings(report)
    (report&.summarized_ratings || []).select do |summary|
      summary.trainers.present? || summary.slots.present?
    end
  end

  # --- shared helpers --------------------------------------------------------

  def trainer_survey?
    @survey.type == Survey::TRAINER
  end

  # The report the reader came from. The drill-down routes carry no
  # :report_id segment, so the roster links pass it as a ?report_id= query
  # param -- without it the per-person back link would land on "main", which
  # for a trainee or Alpha survey is a report with no roster on it.
  def report_path
    survey_report_url(@survey, params[:report_id] || "main")
  end

  # The report is part of the name: a survey's venue and trainer reports would
  # otherwise both download as "2026-in-person-feedback.csv".
  def csv_filename(suffix)
    parts = [@survey.year, csv_slug, @report_title, suffix]
    "#{parts.compact.map { |part| part.to_s.parameterize }.join("-")}.csv"
  end

  # --- CSV -------------------------------------------------------------------

  # Two exports: the page's feedback, and the ratings behind its ranked tables.
  # Anything else the page shows is a restatement of these.
  def send_report_csv
    if params[:kind] == "ratings"
      send_csv(ratings_csv_rows, filename: csv_filename("ratings"))
    else
      send_csv(feedback_csv_rows, filename: csv_filename("comments"))
    end
  end

  # One row per respondent per session (per subject, where the report names
  # one), with a column per free-text question -- upstream's shape.
  #
  # Upstream keyed those rows by the respondent's id, which anonymous answers
  # do not have, so every anonymous answer for a session collapsed onto one
  # row and all but the last were lost. Anonymous answers cannot be joined
  # across questions without undoing the anonymity, so each one takes its own
  # row here: sparser, but nothing is dropped.
  def feedback_csv_rows
    rows = {}
    columns = {}
    anonymous = 0

    each_feedback_answer do |trainer_callsign, slot_response, question, response|
      person = response.person
      key = if person
              [slot_response&.slot_id, trainer_callsign, person.id, person.callsign]
            else
              [slot_response&.slot_id, trainer_callsign, :anonymous, anonymous += 1]
            end

      slot = @slots[slot_response&.slot_id]
      row = (rows[key] ||= {
        session: slot ? slot.begins.strftime(DateTimeHelper::CSV_TIME) : "",
        location: slot_response&.slot_description.presence || slot&.description || "",
        trainer: trainer_callsign,
        respondent: person&.callsign.presence || "Anonymous"
      })

      columns[question.description] = true
      row[question.description] = response.answer
    end

    build_csv_table(rows.values, columns.keys)
  end

  # Header order is fixed; question columns follow in the order the report
  # walks them. Two columns are conditional, because a column of nothing is
  # worse than no column: the subject is named for what the survey rates (an
  # Alpha survey says Mentor) and is dropped when no report on the page names
  # one, and an Alpha survey drops the Session/Location pair its answers
  # never fill. Every other survey keeps the stable pair even where a summary
  # group leaves it blank -- downstream sheets key on the column positions.
  def build_csv_table(rows, question_columns)
    named_trainer = rows.any? { |row| row[:trainer].present? }
    by_session = @survey.type != Survey::ALPHA

    header = []
    header.concat(["Session", "Location"]) if by_session
    header << survey_subject_label(@survey) if named_trainer
    header << "Respondent"

    table = [header + question_columns]

    rows.sort_by { |row| [row[:session], row[:trainer].to_s, row[:respondent].to_s] }.each do |row|
      line = []
      line.concat([row[:session], row[:location]]) if by_session
      line << row[:trainer] if named_trainer
      line << row[:respondent]
      table << line + question_columns.map { |column| row[column] }
    end

    table
  end

  # Walks every free-text answer the page shows, whatever report shape it came
  # from, yielding the subject it is about (nil when the report names none),
  # the session it came from (nil for a summary report, and for every Alpha
  # answer -- SurveyBuilder does not group those by slot), the question, and
  # the answer.
  def each_feedback_answer(&block)
    if @person
      # The per-subject page: one person's questions.
      walk_questions(@questions, @person.callsign, &block)
    elsif trainer_survey?
      @trainers.each { |feedback| walk_questions(feedback.report&.questions, feedback.callsign, &block) }
    else
      # A venue or manual-review report asks the room; a trainer group nests
      # the same questions under each trainer. A group that collected no
      # answers leaves @report nil, and walks nothing.
      walk_questions(@report&.questions, nil, &block)
      @trainers.each { |trainer| walk_questions(trainer.questions, trainer.callsign, &block) }
    end
  end

  def walk_questions(questions, trainer_callsign)
    questions&.each do |question|
      next if question.type == SurveyQuestion::TYPE_RATING

      # A summary group's questions hold responses directly; every other shape
      # groups them by session.
      if question.respond_to?(:slots) && question.slots.present?
        question.slots.each do |slot_response|
          slot_response.responses.each { |response| yield(trainer_callsign, slot_response, question, response) }
        end
      else
        question.responses.each { |response| yield(trainer_callsign, nil, question, response) }
      end
    end
  end

  # The numbers behind the page's ranked tables. One file covers both shapes
  # (people and sessions) by naming the question and its subject, rather than
  # upstream's separate wide-format export per summary section.
  def ratings_csv_rows
    rows = [["Question", "Subject", "Session Date", "Avg Rating", "Std Dev", "Ratings", "Distribution"]]

    ratings_sources.each do |description, subject, slot_id, stats|
      slot = @slots[slot_id]
      rows << [description,
               subject,
               slot ? slot.begins.strftime(DateTimeHelper::CSV_TIME) : "",
               stats.mean,
               survey_std_dev(stats.variance),
               stats.rating_count,
               survey_distribution_text(stats.distribution)]
    end

    rows
  end

  # Every rating the page shows, as [question, subject, slot id, statistics]:
  # the ranked summaries first (SurveyBuilder has already sorted them
  # best-first), then each plain rating question's own totals.
  def ratings_sources
    sources = []

    @summarized_ratings.each do |summary|
      summary.trainers.each { |trainer| sources << [summary.description, trainer.callsign, nil, trainer] }
      summary.slots.each { |slot| sources << [summary.description, slot.slot_description, slot.slot_id, slot] }
    end

    each_rating_question do |subject, question|
      sources << [question.description, subject, nil, question]
    end

    sources
  end

  # Rating questions and who each set of numbers is about. A trainer group
  # keeps its questions under the people it rates; a venue or manual-review
  # report asks the room as a whole.
  def each_rating_question
    if @person
      rating_questions(@questions).each { |question| yield(@person.callsign, question) }
    else
      @trainers.each do |feedback|
        rating_questions(trainer_questions(feedback)).each { |question| yield(feedback.callsign, question) }
      end
      rating_questions(@report&.questions).each { |question| yield("All respondents", question) }
    end
  end

  def rating_questions(questions)
    (questions || []).select { |question| question.type == SurveyQuestion::TYPE_RATING }
  end

  # --- page totals -----------------------------------------------------------

  # The stat boxes, counted off the same walks the exports use so the page
  # cannot claim a number its CSV does not contain.
  def count_totals
    @comment_count = 0
    session_ids = []

    each_feedback_answer do |_trainer, slot_response, _question, _response|
      @comment_count += 1
      session_ids << slot_response.slot_id if slot_response
    end

    @session_count = session_ids.uniq.size
    @rating_count = ratings_sources.sum { |source| source.last.rating_count.to_i }
  end

  # How many ratings each subject received. A question flagged to be
  # summarized reports through the ranked tables rather than under the person,
  # so the roster has to count both places or it reads zero beside a ranked
  # table that just showed eight.
  def count_trainer_ratings
    totals = Hash.new(0)

    @summarized_ratings.each do |summary|
      summary.trainers.each { |trainer| totals[trainer.trainer_id] += trainer.rating_count.to_i }
    end

    @trainers.each do |feedback|
      totals[trainer_key(feedback)] += survey_rating_total(trainer_questions(feedback))
    end

    totals
  end

  # A trainer-on-trainer survey reports people as TrainerFeedback (id, with
  # their questions under .report); a student-on-trainer group reports them as
  # TrainerReport (trainer_id, questions directly). These two resolve that
  # split everywhere it shows up.
  def trainer_key(feedback)
    feedback.try(:trainer_id) || feedback.id
  end

  def trainer_questions(feedback)
    feedback.respond_to?(:report) ? feedback.report&.questions : feedback.questions
  end
end
