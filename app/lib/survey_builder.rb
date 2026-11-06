# frozen_string_literal: true

class SurveyBuilder
  # Represents a person in survey context (trainer, mentor, or target)
  class SurveyPerson
    attr_reader :id, :callsign, :position_id, :position_title, :photo

    def initialize(id:, callsign:, photo:, position_id: nil, position_title: nil)
      @id = id
      @callsign = callsign
      @position_id = position_id
      @position_title = position_title
      @photo = photo
    end
  end

  # Represents a survey report container
  class SurveyReport
    attr_accessor :id, :type, :questions, :summarized_ratings, :trainers

    def initialize(id:, type:)
      @id = id
      @type = type
      @questions = []
      @summarized_ratings = []
      @trainers = []
    end
  end

  # Represents a slot-specific response with optional statistics
  class SlotResponse
    attr_accessor :slot_id, :slot_begins, :slot_description,
                  :mean, :variance, :distribution, :rating_count, :responses

    def initialize(slot_id:, slot_begins:, slot_description:)
      @slot_id = slot_id
      @slot_begins = slot_begins
      @slot_description = slot_description
      @responses = []
    end
  end

  # Represents question data with responses or statistics
  class QuestionData
    attr_accessor :id, :type, :description, :responses, :slots,
                  :mean, :variance, :distribution, :rating_count, :option_list

    # option_list: what a multiple-choice question offers, in its order.
    def initialize(id:, type:, description:, option_list: [])
      @id = id
      @type = type
      @description = description
      @option_list = option_list
      @responses = []
      @slots = []
    end
  end

  # Represents a summarized rating across slots or responses
  class SummarizedRating
    attr_accessor :description, :slots, :responses, :trainers

    def initialize(description:)
      @description = description
      @slots = []
      @responses = []
      @trainers = []
    end
  end

  # Represents a trainer-specific report
  class TrainerReport
    attr_accessor :trainer_id, :callsign, :photo, :questions

    def initialize(trainer_id:, callsign:, photo:)
      @trainer_id = trainer_id
      @callsign = callsign
      @photo = photo
      @questions = []
    end
  end

  # Represents a trainer summary with ratings and statistics
  class TrainerSummary
    attr_accessor :trainer_id, :callsign, :ratings,
                  :mean, :variance, :distribution, :rating_count

    def initialize(trainer_id:, callsign:)
      @trainer_id = trainer_id
      @callsign = callsign
      @ratings = []
    end
  end

  # Represents a question response with optional statistics
  class QuestionResponse
    attr_accessor :description, :type, :responses,
                  :mean, :variance, :distribution, :rating_count, :option_list

    def initialize(description:, type:, option_list: [])
      @description = description
      @type = type
      @option_list = option_list
      @responses = []
    end
  end

  # Represents an answer result with optional person reference
  class AnswerResult
    attr_reader :answer, :person

    def initialize(answer:, person: nil)
      @answer = answer
      @person = person
    end
  end

  # Represents a person reference in an answer
  class PersonReference
    attr_reader :id, :callsign

    def initialize(id:, callsign:)
      @id = id
      @callsign = callsign
    end
  end

  # Represents trainer feedback with report data
  class TrainerFeedback
    attr_accessor :id, :callsign, :photo, :report

    def initialize(id:, callsign:, photo:, report:)
      @id = id
      @callsign = callsign
      @photo = photo
      @report = report
    end
  end

  class SurveyTargets
    attr_accessor :slot, :targets, :survey

    def initialize(slot: nil, targets: nil, survey: nil)
      @slot = slot
      @targets = targets
      @survey = survey
    end
  end

  # Retrieve the slot record, the survey for the type, position & year and the attending trainers
  #
  # @param type [String]
  # @param slot_id [Integer]
  # @param person [Person]
  # @return [SurveyTargets]
  # @raise [ArgumentError]
  def self.retrieve_slot_survey_trainers(type, slot_id, person)
    person_id = person.id
    slot = Slot.find(slot_id)

    survey = Survey.find_for_type_position_year(type, slot.position_id, slot.begins.year)
    trainers = TrainerStatus.where(slot_id:)
                            .where(status: TrainerStatus::STATUS_ATTENDED)
                            .where.not(
      SurveyAnswer.where("survey_answer.slot_id = trainer_status.slot_id")
                  .where("survey_answer.trainer_id = trainer_status.person_id")
                  .where(person_id:)
                  .arel.exists
    ).includes(person: { photo: { profile_attachment: :blob } }, trainer_slot: :position).map do |t|
      p = t.person
      SurveyPerson.new(
        id: t.person_id,
        callsign: p.callsign,
        position_id: t.trainer_slot.position_id,
        position_title: t.trainer_slot.position&.title || "Position ##{t.trainer_slot.position_id}",
        photo: p.photo.profile
      )
    end.sort_by(&:callsign)

    case type
    when Survey::TRAINING
      unless TraineeStatus.did_person_pass_session?(person_id, slot_id)
        raise ArgumentError, "You are not marked as having attended the training session."
      end

    when Survey::TRAINER
      me = trainers.find { |t| t.id == person_id }
      unless me
        raise ArgumentError, "You are not marked as having taught the training session."
      end
      # Exclude the person's answers.
      trainers = trainers.reject { |t| t.id == person_id }

    else
      raise ArgumentError, "Unknown survey type [#{type}]"
    end

    SurveyTargets.new(slot:, survey:, targets: trainers)
  end

  # Retrieve the alpha survey for a given year and person's mentors
  #
  # @param year [Integer]
  # @param person [Person]
  # @return [SurveyTargets]
  def self.retrieve_alpha_survey(year, person)
    person_id = person.id
    unless Timesheet.alpha_entry?(person_id, year)
      raise ArgumentError, "Person was not an alpha in the given year"
    end

    survey = Survey.find_for_type_position_year(Survey::ALPHA, Position::ALPHA, year)
    mentors = PersonMentor.where(mentor_year: year, position_id: Position::ALPHA)
                          .where(person_id: person_id)
                          .includes(mentor: { photo: { profile_attachment: :blob } })
                          .filter_map do |t|
      # A deleted mentor has nothing to rate, and a mentor without an approved
      # photo is shown without one (the view checks for it).
      p = t.mentor
      next unless p

      SurveyPerson.new(
        id: p.id,
        callsign: p.callsign,
        photo: p.photo&.profile
      )
    end.sort_by(&:callsign)

    SurveyTargets.new(survey:, targets: mentors)
  end

  # Retrieve the slot record, the survey for the type, position & year and the attending targets
  #
  # @param type [String]
  # @param slot_id [Integer]
  # @param person [Person]
  # @return [SurveyTargets]
  def self.retrieve_mentoring_survey(type, slot_id, person)
    slot = Slot.find(slot_id)
    survey = Survey.find_for_type_position_year(type, slot.position_id, slot.begins.year)
    targets = Timesheet.where(position_id: survey.mentoring_position_id)
                       .where(on_duty: (slot.begins - 1.hour)..(slot.begins + 1.hour))
                       .includes(:person, :position)
                       .includes(person: { photo: { profile_attachment: :blob } })
                       .map do |t|
      p = t.person
      SurveyPerson.new(
        id: t.person_id,
        callsign: p.callsign,
        position_id: t.position_id,
        position_title: t.position&.title || "Position ##{t.position_id}",
        photo: p.photo
      )
    end.sort_by(&:callsign)

    SurveyTargets.new(survey:, slot:, targets:)
  end

  # Build up a survey response. The response is broken up into two parts:
  # the venue/class responses (material presentation, exercise quality, etc.) and the trainer ratings and responses
  #
  # Trainer feedback is handled in two different ways:
  # 1) A trainer-on-trainer survey (not group, survey.type='trainer') will loop thru ALL survey questions with each trainer
  # 2) A student-on-trainer survey group (survey_group.type='trainer') thru all group questions with each trainer
  #
  # @param survey [Survey]
  # @param trainer_id [Integer, nil] (optional) if set, report only on the trainer
  # @param include_person [Boolean]
  # @param data [SurveyData, nil] preloaded survey data; built here when omitted
  # @return [Array<SurveyReport>]
  def self.build_survey_reports(survey, trainer_id = nil, include_person = false, data: nil)
    trainer_id = trainer_id&.to_i
    data ||= load_survey_data(survey, trainer_id:, include_person:)

    slots = data.slots
    survey_groups = data.groups
    questions_by_group_id = data.questions.group_by(&:survey_group_id)

    # Filtered here as well as in load_survey_data: a caller walking every
    # trainer (all_trainers_report) passes the whole survey's answers.
    survey_answers = trainer_id ? data.answers.select { |a| a.trainer_id == trainer_id } : data.answers
    answers_by_question_id = survey_answers.group_by(&:survey_question_id)

    # Find all the trainers
    trainer_ids = survey_answers.select { |a| a.trainer_id&.positive? }.map(&:trainer_id).uniq
    trainers = data.people.select { |person| trainer_ids.include?(person.id) }

    main_report = SurveyReport.new(id: "main", type: SurveyGroup::TYPE_NORMAL)

    reports = []

    survey_groups.each do |group|
      questions_for_group = questions_by_group_id[group.id]
      next unless questions_for_group

      if trainer_id
        # Skip group if no answers were given
        next unless survey_answers.any? { |a| a.survey_group_id == group.id && a.trainer_id == trainer_id }
      end

      if group.type == SurveyGroup::TYPE_NORMAL
        report = main_report
      else
        report = SurveyReport.new(
          id: group.get_report_id,
          type: group.type
        )
        reports << report
      end

      case group.type
      when SurveyGroup::TYPE_NORMAL, SurveyGroup::TYPE_SEPARATE
        build_group_report(survey, report, slots, questions_for_group, answers_by_question_id, trainer_id, include_person)
      when SurveyGroup::TYPE_TRAINER
        build_trainer_group_report(survey, report, trainers, slots, questions_for_group, survey_answers, include_person)
      when SurveyGroup::TYPE_SUMMARY
        build_summary_group_report(report, questions_for_group, answers_by_question_id, include_person)
      end
    end

    # Add the main report on top if it holds anything. Ranked ratings alone
    # count: a trainer-on-trainer survey's peers may rate without commenting,
    # and upstream kept such a report too (its questions start as []).
    reports.unshift(main_report) unless main_report.questions.empty? && main_report.summarized_ratings.empty?

    reports
  end

  # Everything a survey's reports are built from. A caller that walks every
  # trainer (all_trainers_report) loads this once and filters it per trainer,
  # instead of loading per trainer -- that loop cost 394 queries and 328ms on
  # the 2026 trainer-on-trainer survey's 54 trainers. A report on one trainer
  # loads only the answers about them: a survey holds up to 5,000 answers.
  SurveyData = Struct.new(:slots, :groups, :questions, :answers, :people, keyword_init: true)

  # Both choices must match the report built from the data: loaded for one
  # trainer it holds no one else's answers, and loaded without include_person
  # a report that names people reads each one with a query of its own. Neither
  # has a default, so every caller says which it means.
  #
  # @param survey [Survey]
  # @param include_person [Boolean] preload who answered, for a report that may name them
  # @param trainer_id [Integer, nil] load only the answers about this person
  # @return [SurveyData]
  def self.load_survey_data(survey, include_person:, trainer_id: nil)
    answers = SurveyAnswer.where(survey_id: survey.id).where.not(response: "")
    answers = answers.where(trainer_id:) if trainer_id
    answers = answers.includes(:person) if include_person
    answers = answers.to_a

    trainer_ids = answers.filter_map { |answer| answer.trainer_id if answer.trainer_id&.positive? }.uniq
    people = if trainer_ids.empty?
               []
             else
               Person.select(:id, :callsign).where(id: trainer_ids).includes(:photo).to_a
             end

    SurveyData.new(
      slots: survey.retrieve_slots.to_a,
      groups: SurveyGroup.find_all_for_survey(survey.id).to_a,
      questions: SurveyQuestion.find_all_for_survey(survey.id),
      answers:,
      people:
    )
  end

  # Build up a group report (either main or separate) by running through each training session and questions.
  #
  # @param survey [Survey]
  # @param report [SurveyReport]
  # @param slots [Array]
  # @param questions [Array]
  # @param answers_by_question_id [Hash]
  # @param trainer_id [Integer, nil]
  # @param include_person [Boolean]
  def self.build_group_report(survey, report, slots, questions, answers_by_question_id, trainer_id, include_person)
    is_alpha = (survey.type == Survey::ALPHA)
    questions.each do |question|
      answers_for_question = answers_by_question_id[question.id]
      next unless answers_for_question

      slot_responses = []
      is_rating = (question.type == SurveyQuestion::TYPE_RATING) || question.summarize_rating
      overall_ratings = []

      if is_alpha
        alpha_responses = []
        answers_for_question.each do |answer|
          if is_rating
            overall_ratings << answer.response.to_i
          elsif !question.summarize_rating
            alpha_responses << build_answer(answer, include_person)
          end
        end
      else
        answers_group_by_slot = answers_for_question.group_by(&:slot_id)

        slots.each do |slot|
          answers_for_slot = answers_group_by_slot[slot.id]
          if trainer_id && !answers_for_slot
            # Don't bother if only a single trainer is being looked up.
            next
          end

          responses = []
          ratings = []
          answers_for_slot&.each do |answer|
            if is_rating
              rating = answer.response.to_i
              overall_ratings << rating
              ratings << rating
            elsif !question.summarize_rating
              responses << build_answer(answer, include_person)
            end
          end

          slot_response = build_slot_response(slot)

          if is_rating
            compute_statistics(ratings, slot_response)
          else
            slot_response.responses = responses
          end
          slot_responses << slot_response
        end
      end

      # An Alpha survey has no sessions or subjects for a summarized rating to
      # rank, so a summarize_rating question degrades to a plain rating
      # question. The old branch built a SummarizedRating from the always-empty
      # alpha_responses and dropped the collected ratings on the floor.
      if question.summarize_rating && !is_alpha
        sort_statistics(slot_responses)
        summarized = SummarizedRating.new(description: question.description)
        summarized.slots = slot_responses
        report.summarized_ratings << summarized
      else
        data = QuestionData.new(
          id: question.id,
          type: question.type,
          description: question.description,
          option_list: question.option_list
        )
        if is_alpha
          data.responses = alpha_responses
        else
          data.slots = slot_responses
        end
        compute_statistics(overall_ratings, data) if is_rating
        report.questions << data
      end
    end
  end

  # Build up a trainer group report. Iterate through each trainer, then training session, and questions.
  #
  # @param survey [Survey]
  # @param report_results [SurveyReport]
  # @param trainers [Array<Person>]
  # @param slots [Array]
  # @param questions [Array]
  # @param survey_answers [Array]
  # @param include_person [Boolean]
  def self.build_trainer_group_report(survey, report_results, trainers, slots, questions, survey_answers, include_person)
    trainer_reports = []
    answers_by_trainer_id = survey_answers.select { |a| a.trainer_id&.positive? }.group_by(&:trainer_id)

    question_summary_ratings = {}

    is_alpha = survey.type == Survey::ALPHA
    trainers.each do |trainer|
      answers = answers_by_trainer_id[trainer.id]
      next unless answers

      report = TrainerReport.new(
        trainer_id: trainer.id,
        callsign: trainer.callsign,
        photo: trainer.photo
      )

      answers_for_trainer_group_by_question = answers.group_by(&:survey_question_id)

      questions.each do |question|
        slot_responses = []
        is_rating = (question.type == SurveyQuestion::TYPE_RATING) || question.summarize_rating
        overall_ratings = []
        answers_for_question = answers_for_trainer_group_by_question[question.id]

        next unless answers_for_question

        if is_alpha
          alpha_responses = []
          ratings = []
          answers_for_question.each do |answer|
            if is_rating
              rating = answer.response.to_i
              overall_ratings << rating
              ratings << rating
            elsif question.summarize_rating
              next
            else
              alpha_responses << build_answer(answer, include_person)
            end
          end
        else
          answers_group_by_slot = answers_for_question.group_by(&:slot_id)
          slots.each do |slot|
            answers_for_slot = answers_group_by_slot[slot.id]
            next unless answers_for_slot

            responses = []
            ratings = []
            answers_for_slot.each do |answer|
              if is_rating
                rating = answer.response.to_i
                overall_ratings << rating
                ratings << rating
              elsif question.summarize_rating
                next
              else
                responses << build_answer(answer, include_person)
              end
            end

            slot_response = build_slot_response(slot)

            if is_rating
              compute_statistics(ratings, slot_response)
            else
              slot_response.responses = responses
            end
            slot_responses << slot_response
          end
        end

        if question.summarize_rating
          summary = TrainerSummary.new(
            trainer_id: trainer.id,
            callsign: trainer.callsign
          )
          summary.ratings = overall_ratings
          compute_statistics(overall_ratings, summary)
          question_summary_ratings[question.id] ||= []
          question_summary_ratings[question.id] << summary
        else
          data = QuestionData.new(
            id: question.id,
            type: question.type,
            description: question.description,
            option_list: question.option_list
          )

          if is_alpha
            data.responses = alpha_responses
          else
            data.slots = slot_responses
          end
          compute_statistics(overall_ratings, data) if is_rating
          report.questions << data
        end
      end
      trainer_reports << report
    end

    unless question_summary_ratings.empty?
      summarized_ratings = []
      question_summary_ratings.each do |question_id, summary|
        question = questions.find { |q| q.id == question_id }
        sort_statistics(summary)
        summarized = SummarizedRating.new(description: question.description)
        summarized.trainers = summary
        summarized_ratings << summarized
      end
      report_results.summarized_ratings = summarized_ratings
    end

    trainer_reports.sort_by! { |a| a.callsign.downcase }
    report_results.trainers = trainer_reports
  end

  # Build up a summary group - run through all the responses and
  # group together into one big report. (NOT broken down by slot)
  #
  # @param report [SurveyReport]
  # @param questions [Array]
  # @param answers_by_question_id [Hash]
  # @param include_person [Boolean]
  def self.build_summary_group_report(report, questions, answers_by_question_id, include_person)
    question_responses = []
    questions.each do |question|
      answers = answers_by_question_id[question.id]
      next unless answers

      ratings = []
      responses = []
      is_rating = (question.type == SurveyQuestion::TYPE_RATING)
      answers.each do |answer|
        if is_rating
          ratings << answer.response.to_i
        else
          responses << build_answer(answer, include_person)
        end
      end

      question_response = QuestionResponse.new(description: question.description, type: question.type,
                                               option_list: question.option_list)
      if is_rating
        compute_statistics(ratings, question_response)
      else
        question_response.responses = responses
      end
      question_responses << question_response
    end

    report.questions = question_responses
  end

  # Build a basic slot response object
  #
  # @param slot [Slot]
  # @return [SlotResponse]
  def self.build_slot_response(slot)
    SlotResponse.new(
      slot_id: slot.id,
      slot_begins: slot.begins.to_s,
      slot_description: slot.description
    )
  end

  # Compute the statistics (mean, variance, distribution) for a rating array
  #
  # @param ratings [Array<Integer>] An array of integers
  # @param response [Object] Object with mean, variance, distribution, rating_count attributes
  def self.compute_statistics(ratings, response)
    sum = ratings.sum
    count = ratings.count
    distribution = {}
    if count.positive?
      mean = sum.to_f / count
      std_dev = 0.0
      ratings.each do |rating|
        std_dev += (rating - mean) * (rating - mean)
        distribution[rating] = (distribution[rating] || 0) + 1
      end
      variance = std_dev / count
      distribution = distribution.sort.to_h
    else
      mean = 0.0
      variance = 0.0
    end

    response.mean = mean.round(1)
    response.variance = variance.round(1)
    response.distribution = distribution
    response.rating_count = count
  end

  # Sort responses based on the stats. Mean in descending order, then rating responses
  #
  # @param stats [Array] Array of objects with mean and rating_count attributes
  def self.sort_statistics(stats)
    stats.sort_by! do |a|
      [-(a.mean || 0), -(a.rating_count || 0)]
    end
  end

  # Build the answer with the respondent's name (optional).
  #
  # can_share_name is the respondent's own choice, recorded per trainer when the
  # survey is taken (Me::SurveysController's share_name_<trainer_id> field).
  # Trainee feedback is anonymous unless they opted in, so an answer that was
  # NOT shared never carries its person -- no report may attribute it.
  #
  # Answers imported into the Clubhouse for surveys 2019 and earlier, there may not
  # be an actual person id, the callsign field on the survey form was not validated.
  # In the case where person_id is 0, it means the callsign could not be associated with
  # a Clubhouse account.
  #
  # @param answer [SurveyAnswer]
  # @param include_person [Boolean]
  # @return [AnswerResult]
  def self.build_answer(answer, include_person)
    if include_person && answer.can_share_name
      # The survey created before the Clubhouse started hosting them may not
      # have a person_id due to typos in the user's callsign when it was entered on the form.
      person = if answer.person_id && answer.person
                 PersonReference.new(id: answer.person.id, callsign: answer.person.callsign)
               else
                 PersonReference.new(id: 0, callsign: answer.callsign)
               end

      AnswerResult.new(answer: answer.response, person:)
    else
      AnswerResult.new(answer: answer.response)
    end
  end

  # How often each option of a multiple-choice question was picked, in the
  # order the question offers them: { "Great" => 4, "OK" => 1 }. An answer no
  # longer among them -- an option since reworded -- goes last, ties broken by
  # its text so the order holds from one load to the next; an option nobody
  # picked is left out.
  #
  # @param question [QuestionData, QuestionResponse]
  # @return [Hash{String => Integer}]
  def self.option_tally(question)
    answers = question.try(:slots).presence&.flat_map(&:responses) || question.responses
    order = question.option_list
    answers.map(&:answer).tally.sort_by { |option, count| [order.index(option) || order.size, -count, option] }.to_h
  end

  # Report on all trainers who have feedback for a given survey
  #
  # @param survey [Survey]
  # @return [Array<TrainerFeedback>]
  def self.all_trainers_report(survey)
    # Find all the trainers with feedback for a given survey
    found_trainers = SurveyAnswer.joins("JOIN person ON survey_answer.trainer_id = person.id")
                                 .select("survey_answer.trainer_id", "person.callsign")
                                 .where(survey_id: survey.id)
                                 .group("survey_answer.trainer_id", "person.callsign")
                                 .includes(trainer: :photo)

    # Loaded once and filtered per trainer; rebuilding it per trainer is what
    # made this report cost hundreds of queries.
    data = load_survey_data(survey, include_person: true)

    trainers = []
    found_trainers.each do |trainer|
      reports = SurveyBuilder.build_survey_reports(survey, trainer.trainer_id, true, data:)
      trainers << TrainerFeedback.new(
        id: trainer.trainer_id,
        callsign: trainer.callsign,
        photo: trainer.trainer.photo,
        report: reports[0] || SurveyReport.new(id: "empty", type: SurveyGroup::TYPE_NORMAL)
      )
    end

    trainers.sort_by! { |a| a.callsign.downcase }

    trainers
  end
end
