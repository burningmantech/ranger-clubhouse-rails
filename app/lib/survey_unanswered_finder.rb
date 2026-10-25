# frozen_string_literal: true

# Finds unanswered surveys for a person in a given year.
# Checks training surveys, trainer-on-trainer surveys, alpha surveys, and mentoring surveys.
class SurveyUnansweredFinder
  def initialize(person_id, year, status)
    @person_id = person_id
    @year = year
    @status = status
  end

  def call
    sessions = find_training_sessions
    trainer_surveys = find_trainer_surveys
    alpha_survey = check_alpha_survey
    find_mentoring_sessions(sessions)

    Survey::UnansweredResult.new(
      sessions: sessions,
      trainers: trainer_surveys,
      alpha_survey: alpha_survey
    )
  end

  private

  attr_reader :person_id, :year, :status

  def find_training_sessions
    rows = TraineeStatus.passed.select("trainee_status.*")
                        .joins(:slot)
                        .where(slot: { begins_year: year })
                        .where(person_id:)
                        .where("EXISTS (SELECT 1 FROM survey WHERE survey.active = TRUE AND survey.year=? AND survey.position_id=slot.position_id AND survey.type=? LIMIT 1)", year, Survey::TRAINING)
                        .where("EXISTS (SELECT 1 FROM person_slot WHERE person_slot.slot_id=trainee_status.slot_id AND person_slot.person_id=? LIMIT 1)", person_id)
                        .where("NOT EXISTS (SELECT 1 FROM survey_answer JOIN survey ON survey.id=survey_answer.survey_id WHERE survey.position_id=slot.position_id AND survey.type != 'trainer' AND survey_answer.person_id=? AND survey_answer.slot_id=trainee_status.slot_id LIMIT 1)", person_id)
                        .includes(slot: :position)

    rows.map do |s|
      Survey::SurveySession.new(
        id: s.slot_id,
        type: Survey::TRAINING,
        begins: s.slot.begins.to_s,
        description: s.slot.description,
        position_id: s.slot.position_id,
        position_title: s.slot.position.title
      )
    end
  end

  def find_trainer_surveys
    position_ids = Position::TRAINERS.flat_map { |_training_id, trainer_ids| trainer_ids }

    results = []
    return results unless PersonPosition.have_position?(person_id, position_ids)

    taught = TrainerStatus.joins(:trainer_slot)
                          .where(trainer_slot: { position_id: position_ids, begins_year: year })
                          .where(person_id: person_id, status: TrainerStatus::STATUS_ATTENDED)

    return results unless taught.exists?

    slot_ids = taught.pluck(:slot_id).uniq
    trainer_slots = TrainerStatus.select("trainer_status.*")
                                 .joins(:slot)
                                 .where(slot_id: slot_ids)
                                 .where.not(person_id: person_id)
                                 .where(status: TrainerStatus::STATUS_ATTENDED)
                                 .where("EXISTS (SELECT 1 FROM survey WHERE survey.active = TRUE AND survey.year=? AND survey.position_id=slot.position_id AND survey.type=? LIMIT 1)", year, Survey::TRAINER)
                                 .where("NOT EXISTS (SELECT 1 FROM survey_answer WHERE survey_answer.slot_id=trainer_status.slot_id AND survey_answer.trainer_id=trainer_status.person_id AND survey_answer.person_id=? LIMIT 1)", person_id)
                                 .includes(slot: :position, person: {}, trainer_slot: :position)
                                 .group_by(&:slot_id)

    trainer_slots.each do |_slot_id, trainers|
      slot = trainers.first.slot
      results << Survey::TrainerSurvey.new(
        id: slot.id,
        type: Survey::TRAINER,
        description: slot.description,
        begins: slot.begins.to_s,
        position_id: slot.position_id,
        position_title: slot.position.title,
        trainers: trainers.map do |t|
          Survey::PersonInfo.new(
            id: t.person_id,
            callsign: t.person.callsign,
            position_title: t.trainer_slot&.position&.title
          )
        end
      )
    end

    results
  end

  def check_alpha_survey
    (status == Person::ACTIVE || status == Person::ALPHA) &&
      Timesheet.alpha_entry?(person_id, year) &&
      SurveyAnswer.need_alpha_survey_response?(person_id, year)
  end

  def find_mentoring_sessions(sessions)
    mentoring_surveys = Survey.select("survey.*")
                              .joins("JOIN timesheet ON timesheet.position_id = survey.position_id")
                              .where(year:, active: true)
                              .where("timesheet.person_id = ?", person_id)
                              .where_year("timesheet.on_duty", year)
                              .where.not(timesheet: { off_duty: nil })
                              .where(type: [Survey::MENTEES_FOR_MENTOR, Survey::MENTOR_FOR_MENTEES])
                              .includes(:position)
                              .distinct

    mentoring_surveys.each do |m|
      shifts = Timesheet.for_position(m.position_id)
                        .for_person(person_id)
                        .for_year(year)
                        .where.not(slot_id: nil)
                        .where("NOT EXISTS (SELECT 1 FROM survey_answer WHERE survey_answer.survey_id = ? AND survey_answer.slot_id = timesheet.slot_id AND survey_answer.person_id = ? LIMIT 1)", m.id, person_id)
                        .order(:on_duty)
                        .includes(:slot)

      shifts.each do |shift|
        slot = shift.slot
        next unless slot

        targets = Timesheet.for_position(m.mentoring_position_id)
                           .where(on_duty: (slot.begins - 1.hour)..(slot.begins + 1.hour))
                           .includes(:person)
                           .to_a

        next if targets.empty?

        sessions << Survey::SurveySession.new(
          id: slot.id,
          type: m.type,
          begins: slot.begins.to_s,
          description: slot.description,
          position_id: m.position_id,
          position_title: m.position&.title,
          mentoring: targets.map do |t|
            Survey::PersonInfo.new(
              id: t.person_id,
              callsign: t.person.callsign
            )
          end
        )
      end
    end
  end
end
