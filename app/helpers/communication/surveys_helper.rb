# frozen_string_literal: true

# Labels, badges and select choices for the survey management pages. The
# audience wording ("Trainees on their training") comes from SurveyReportHelper,
# so a survey is described the same way here as on the pages that read its
# answers.
module Communication::SurveysHelper
  # The groups the position select offers, in the order it offers them.
  POSITION_GROUP_LABELS = {
    training: "Training positions",
    mentor: "Mentor positions",
    mentee: "Mentee positions",
    alpha: "Alpha"
  }.freeze

  # --- badges ----------------------------------------------------------------

  # Whether the survey is being shown to anyone. Icon and word both, so it
  # does not rest on colour.
  def survey_status_badge(survey)
    if survey.active
      ui_badge "Active", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "Inactive", :warning, icon: "eye-slash", icon_type: :solid
    end
  end

  # Whether anyone has answered yet. A survey with answers is one to think
  # twice about editing.
  def survey_responses_badge(survey)
    if survey.has_responses
      ui_badge "Has responses", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "None yet", :secondary, icon: "circle-minus", icon_type: :solid
    end
  end

  # How a group is reported, for the groups that are reported unusually. A
  # standard group gets no badge: it is the ordinary case.
  def survey_group_type_badge(group, survey)
    case group.type
    when SurveyGroup::TYPE_TRAINER
      ui_badge "Repeats per #{survey_subject_label(survey).downcase}", :secondary,
               icon: "repeat", icon_type: :solid
    when SurveyGroup::TYPE_SEPARATE
      ui_badge "Own report by session: #{group.report_title}", :secondary,
               icon: "file-lines", icon_type: :solid
    when SurveyGroup::TYPE_SUMMARY
      ui_badge "Own summary report: #{group.report_title}", :secondary,
               icon: "file-lines", icon_type: :solid
    end
  end

  # How a question is answered, and whether its ratings are summarized.
  def survey_question_type_badges(question)
    badges = case question.type
             when SurveyQuestion::TYPE_RATING
               [ui_badge("Rating 1-7", :secondary, icon: "star-half-stroke", icon_type: :solid)]
             when SurveyQuestion::TYPE_OPTIONS
               [ui_badge("Options", :secondary, icon: "list-ul", icon_type: :solid)]
             else
               [ui_badge("Text", :secondary, icon: "align-left", icon_type: :solid)]
             end

    if question.summarize_rating
      badges << ui_badge("Summarized", :secondary, icon: "table-list", icon_type: :solid)
    end

    safe_join(badges, " ")
  end

  # --- links -----------------------------------------------------------------

  # Where this survey's answers are read, or nil when there is no page the
  # reader can open. The Alphas' feedback belongs to the Mentors; every other
  # kind is read on the page of the training its cadre belongs to.
  #
  # Both of those pages are gated on roles a survey permission does not imply,
  # so the link is offered only to someone who can follow it -- a survey
  # manager who is not also a trainer would otherwise be sent to the dashboard
  # with a refusal.
  def survey_feedback_path(survey)
    if survey.type == Survey::ALPHA
      return has_role?([Role::ADMIN, Role::MENTOR]) ? mentoring_surveys_path : nil
    end

    training = survey.feedback_training_position
    return nil unless training && has_role?(Training.view_roles(training))

    training_surveys_path(Training.slug(training), year: survey.year)
  end

  # Copy a survey into this year. The same button on the list and on a
  # survey's own page, so the confirmation is worded in one place.
  def survey_duplicate_button(survey)
    button_link "Duplicate", :secondary, duplicate_communication_survey_path(survey),
                icon: "clone", icon_type: :solid,
                aria: { label: "Duplicate #{survey.title}" },
                data: confirm_modal(
                  title: "Duplicate Survey",
                  message: "Copy \"#{survey.title}\" as a #{current_year} survey? " \
                           "The copy starts switched off, so you can review it before anyone sees it.",
                  confirm_label: "Duplicate Survey",
                  method: :post
                )
  end

  # --- select choices --------------------------------------------------------

  # The kinds of survey this person may create, named for the people who
  # answer them.
  def survey_type_options(types)
    types.map { |type| [SurveyReportHelper::AUDIENCE_LABELS[type] || type, type] }
  end

  # The positions this person manages surveys for, grouped by kind. Which
  # group a survey may take its position from depends on its kind, and the
  # survey says so if the two disagree. Inactive positions are still offered,
  # marked, because old surveys sit at them.
  def survey_position_options(manageable_positions, selected)
    groups = POSITION_GROUP_LABELS.filter_map do |category, label|
      positions = manageable_positions[category]
      next if positions.blank?

      [label, positions.map { |position| [title_marking_inactive(position), position.id] }]
    end

    grouped_options_for_select(groups, selected)
  end

  # The position a mentoring survey asks about, from the lists the controller
  # loaded.
  def survey_mentoring_position_options(positions, selected)
    groups = [:mentor, :mentee].map do |category|
      [POSITION_GROUP_LABELS[category],
       positions[category].map { |position| [title_marking_inactive(position), position.id] }]
    end

    grouped_options_for_select(groups, selected)
  end

  # What each kind of group means for the report, spelled out: the choice is
  # made once and lived with for a season.
  def survey_group_type_options
    [
      ["Standard - the questions appear in the survey's main report", SurveyGroup::TYPE_NORMAL],
      ["Per trainer - the questions repeat for each trainer, mentor, or mentee, and are collated in their own feedback",
       SurveyGroup::TYPE_TRAINER],
      ["Separate report, by session - needs a report title", SurveyGroup::TYPE_SEPARATE],
      ["Separate report, summary only - needs a report title, with no session breakdown",
       SurveyGroup::TYPE_SUMMARY]
    ]
  end

  def survey_question_type_options
    [
      ["Rating 1 to 7", SurveyQuestion::TYPE_RATING],
      ["Text response", SurveyQuestion::TYPE_TEXT],
      ["Options (pick one)", SurveyQuestion::TYPE_OPTIONS]
    ]
  end
end
