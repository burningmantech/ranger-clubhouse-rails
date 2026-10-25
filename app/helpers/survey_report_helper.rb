# frozen_string_literal: true

# Formatting for survey feedback reports. The statistics helpers are pure and
# the controller includes this module for its CSV exports, so a number on the
# page and the same number in the export can never disagree.
module SurveyReportHelper
  # Survey ratings run 1-7 (SurveyAnswer::RATING_OPTIONS); the meter is the
  # mean against that ceiling.
  RATING_MAX = 7

  # SurveyBuilder computes variance. Upstream printed it under a "Std. Dev."
  # heading and exported (mean / 7) / 100 in the CSV column of the same name;
  # both are wrong, so the real standard deviation is derived here and used
  # everywhere the label says so.
  def survey_std_dev(variance)
    Math.sqrt(variance.to_f.abs).round(1)
  end

  def survey_rating_percent(mean)
    return 0 unless mean

    ((mean.to_f / RATING_MAX) * 100).round
  end

  # "7x22 6x14" -- rating x how many gave it. Plain text for exports.
  def survey_distribution_text(distribution)
    (distribution || {}).map { |rating, count| "#{rating}x#{count}" }.join(" ")
  end

  # The same distribution for the page, spaced so the pairs stay readable
  # when a question collects every rating.
  def survey_distribution(distribution)
    return tag.span("—", class: "text-stone-muted") if distribution.blank?

    safe_join(
      distribution.map do |rating, count|
        tag.span("#{rating}×#{count}", class: "whitespace-nowrap tabular-nums")
      end,
      tag.span(" · ", class: "text-stone-muted")
    )
  end

  # Who gave an answer. Feedback is anonymous unless the respondent agreed to
  # share their name (SurveyBuilder.build_answer honors that flag), so the
  # absence of a person here is a deliberate state, not missing data.
  #
  # A person id of 0 marks a survey imported from the pre-2020 paper forms,
  # where the callsign was typed in and never matched an account.
  def survey_respondent(person)
    return tag.span("Anonymous", class: "italic text-stone-muted") unless person
    return tag.span(person.callsign, class: "font-semibold") if person.id.to_i.zero?

    link_to person.callsign, person_path(person.id), class: LinkHelper::TABLE_LINK_CLASSES
  end

  # Who answered a survey and what it asked them about. Upstream's labels
  # ("Trainee-for-Training Survey", "ART Mentees Feedback for ART Mentors
  # Survey") name the form; these name the people.
  AUDIENCE_LABELS = {
    Survey::TRAINING => "Trainees on their training",
    Survey::TRAINER => "Trainers on each other",
    Survey::ALPHA => "Alphas on their mentors",
    Survey::MENTEES_FOR_MENTOR => "Mentees on their mentors",
    Survey::MENTOR_FOR_MENTEES => "Mentors on their mentees"
  }.freeze

  def survey_audience_label(survey)
    AUDIENCE_LABELS[survey.type] || survey.type
  end

  # What to call the people a report is about. A mentee-on-mentor survey rates
  # mentors and a mentor-on-mentee survey rates mentees -- calling either of
  # them a trainer is simply wrong.
  SUBJECT_LABELS = {
    Survey::MENTEES_FOR_MENTOR => "Mentor",
    Survey::MENTOR_FOR_MENTEES => "Mentee",
    Survey::ALPHA => "Mentor"
  }.freeze

  def survey_subject_label(survey)
    SUBJECT_LABELS[survey.type] || "Trainer"
  end

  # How many comments a set of questions collected, counted the same way the
  # export walks them.
  def survey_comment_count(questions)
    (questions || []).sum do |question|
      next 0 if question.type == SurveyQuestion::TYPE_RATING

      if question.respond_to?(:slots) && question.slots.present?
        question.slots.sum { |slot| slot.responses.size }
      else
        question.responses.size
      end
    end
  end

  # How many ratings a set of questions collected.
  def survey_rating_total(questions)
    (questions || []).sum do |question|
      (question.type == SurveyQuestion::TYPE_RATING) ? question.rating_count.to_i : 0
    end
  end

  # A rating meter beside its printed value -- the threshold is never carried
  # by color alone. Weak averages are worth noticing, so the bar warns below 5
  # and alarms below 4 of 7.
  def survey_rating_meter(mean)
    percent = survey_rating_percent(mean)
    level = if mean.to_f < 4 then :error
            elsif mean.to_f < 5 then :warning
            else :success
            end

    tag.div(class: "flex items-center gap-2") do
      tag.div(ui_progress_bar(percent, level, size: :sm, aria: { label: "#{mean} out of #{RATING_MAX}" }),
              class: "w-20 shrink-0") +
        tag.span(mean, class: "tabular-nums font-semibold")
    end
  end
end
