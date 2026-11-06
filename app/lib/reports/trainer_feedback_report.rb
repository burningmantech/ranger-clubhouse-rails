# frozen_string_literal: true

# What the people a person taught or mentored said about them, a year at a
# time: Me › Trainer/Mentor Feedback (upstream me/trainer-feedback).
#
# Anonymous by design. The reports are built with include_person off, as
# upstream's trainerReportForYear builds them, so the page never says who wrote
# an answer -- not even a fellow trainer who chose, on the trainer-on-trainer
# form, to share their name with this person. The admin per-trainer page
# (SurveyReportingConcern#trainer) is the one that names respondents.
#
# Mentor-on-mentee surveys are left out (chosen 2026-11-05, reversible; upstream
# showed them): their answers are about the mentee, an assessment of the
# person rather than feedback on their teaching or mentoring.
#
# SurveyBuilder reports a person in more than one shape, folded here into one
# list each of ratings, multiple-choice tallies and comment questions:
#   * a trainer group (trainees, Alphas and mentees on whoever taught them)
#     files its questions under the person, and its ranked ratings hold them
#     alone
#   * any other group asks about them directly -- a trainer-on-trainer survey
#     files every answer this way -- so its ranked ratings rank their sessions
#   * an Alpha survey's answers carry no session, so they come back ungrouped
class TrainerFeedbackReport
  # One survey's feedback about the person. session_ids are every session it
  # came from.
  Row = Data.define(:survey, :ratings, :choices, :questions, :session_ids) do
    def comment_count = questions.sum { |question| question.groups.sum { |_slot_response, answers| answers.size } }

    def rating_count = ratings.sum { |rating| rating.stats.rating_count }

    def choice_count = choices.sum(&:count)
  end

  # A line of the ratings table. stats answers mean, variance, distribution and
  # rating_count; where a survey ranks the person's sessions, it is the session.
  Rating = Data.define(:description, :stats) do
    def slot_response = (stats if stats.is_a?(SurveyBuilder::SlotResponse))
  end

  # A multiple-choice question and how often each option was picked
  # (SurveyBuilder.option_tally): { "Great" => 4, "OK" => 1 }.
  Choice = Data.define(:description, :tally) do
    def count = tally.values.sum
  end

  # A text question and its answers, by the session they came from:
  # [[SlotResponse, or nil where answers carry no session, [AnswerResult, ...]], ...]
  Question = Data.define(:description, :groups)

  # Every year anyone said something about the person, newest first: upstream's
  # index of years, which the page offers as its year selector.
  def self.years(person_id) = surveys(person_id).distinct.order(year: :desc).pluck(:year)

  # Has anyone said something about the person this page lists? The menu
  # offers the page on it, so the two can never disagree.
  def self.any_for?(person_id) = surveys(person_id).exists?

  # A Row for each of the year's surveys holding something about the person the
  # page can show.
  def self.for_year(person_id, year)
    surveys(person_id).where(year:).order(:title).filter_map do |survey|
      # include_person: false -- see the top of this file.
      reports = SurveyBuilder.build_survey_reports(survey, person_id, false)
      row = Row.new(survey:, ratings: reports.flat_map { |report| ratings(report) },
                    choices: reports.flat_map { |report| choices(report) },
                    questions: reports.flat_map { |report| questions(report) },
                    session_ids: reports.flat_map { |report| session_ids(report) }.uniq)
      row if [row.ratings, row.choices, row.questions].any?(&:any?)
    end
  end

  # Every survey holding an answer about the person that a report can show
  # (SurveyBuilder.load_survey_data drops blank ones), of every kind but
  # mentor-on-mentee. Not Survey.find_all_for_trainer_year: without a type it
  # leaves out the Alpha survey, which upstream linked on a page of its own.
  def self.surveys(person_id)
    answered = SurveyAnswer.where(trainer_id: person_id).where.not(response: "").select(:survey_id)
    Survey.where(id: answered).where.not(type: Survey::MENTOR_FOR_MENTEES)
  end

  # The questions a report asks about the person. Only one of the two is ever
  # filled: a trainer group files them under the person it reports on, and any
  # other group holds them itself.
  def self.asked(report) = report.questions + report.trainers.flat_map(&:questions)

  # Ranked ratings first, then each plain rating question's own totals. A
  # summary ranks either the person (a trainer group) or their sessions (any
  # other group), never both.
  def self.ratings(report)
    ranked = report.summarized_ratings.flat_map do |summary|
      (summary.trainers + summary.slots).map { |stats| Rating.new(description: summary.description, stats:) }
    end
    plain = asked(report).select { |question| question.type == SurveyQuestion::TYPE_RATING }
                         .map { |question| Rating.new(description: question.description, stats: question) }

    (ranked + plain).select { |rating| rating.stats.rating_count.to_i.positive? }
  end

  # Multiple-choice questions, each tallied.
  def self.choices(report)
    asked(report).filter_map do |question|
      next unless question.type == SurveyQuestion::TYPE_OPTIONS

      tally = SurveyBuilder.option_tally(question)
      Choice.new(description: question.description, tally:) if tally.any?
    end
  end

  # Every other question is a comment question: what people wrote, by session.
  def self.questions(report)
    asked(report).filter_map do |question|
      next if [SurveyQuestion::TYPE_RATING, SurveyQuestion::TYPE_OPTIONS].include?(question.type)

      groups = answer_groups(question)
      Question.new(description: question.description, groups:) if groups.any?
    end
  end

  # A question's answers by the session they came from. An Alpha survey's
  # answers, and a manual-review group's (which has no sessions to group by),
  # come back as one group with no session.
  def self.answer_groups(question)
    if question.respond_to?(:slots) && question.slots.present?
      question.slots.filter_map { |slot| [slot, slot.responses] if slot.responses.present? }
    elsif question.responses.present?
      [[nil, question.responses]]
    else
      []
    end
  end

  # Every session the person's feedback came from: the ones any question's
  # answers fall under -- rating and multiple-choice ones included, since a
  # report on one person keeps only sessions with answers -- and the ones a
  # trainer-on-trainer survey ranks.
  def self.session_ids(report)
    (asked(report).flat_map { |question| question.try(:slots) || [] } + report.summarized_ratings.flat_map(&:slots))
      .map(&:slot_id)
  end

  private_class_method :surveys, :asked, :ratings, :choices, :questions, :answer_groups, :session_ids
end
