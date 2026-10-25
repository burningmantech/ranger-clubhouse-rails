# frozen_string_literal: true

# Section registry for /mentoring/alpha-status. The rank chips, filter options
# and note pills the rows render are the shared pipeline ones and stay in
# UnifiedFlaggingHelper; only the sectioning is this page's own.
#
# Sections are ordered by what a mentor does next rather than by severity, and
# a person falls into the FIRST one that matches -- see
# Mentoring::AlphaStatusController#section_of. That is why each title is an
# action and each `who` line says who is in the section: someone with a
# Personnel flag and no training sign-up appears only under "Resolve first",
# which is surprising unless the page says so. The page says it in its About
# This Report card, where each line answers "Who is under <title>?".
module Mentoring::AlphaStatusHelper
  # A Personnel flag or a current rank 3/4 or bonk -- Intake's two severity
  # groups, as opposed to :other. Same names as the sibling page uses.
  ISSUE_GROUPS = %i[personnel flagged].freeze

  SECTIONS = [
    {
      key: :resolve,
      title: "Resolve First",
      icon: "triangle-exclamation",
      badge_color: :error,
      who: "Anyone with a Personnel Black Flag, a rank 3 or 4 from any intake team, or a bonk. " \
           "People land there whatever their training standing. Take no action on them until the concern is resolved.",
      empty: "No one in this year's class has a flag, a rank of 3 or 4, or a bonk."
    },
    {
      key: :ready,
      title: "Ready for Alpha Status",
      icon: "user-plus",
      badge_color: :warning,
      who: "Anyone who passed training and is still a Prospective. Those are the people to convert.",
      empty: "No Prospective has passed training without already being made an Alpha."
    },
    {
      key: :alpha,
      title: "Became an Alpha",
      icon: "seedling",
      badge_color: :success,
      who: "Anyone already made an Alpha this year. Some may have moved on to Active since — " \
           "select a name and the status beside it says which.",
      empty: "No one has been made an Alpha yet this year."
    },
    {
      key: :waiting,
      title: "Waiting on Training",
      icon: "hourglass-half",
      badge_color: :secondary,
      who: "Anyone who has not passed a training session yet. Chase the people with no sign-up first.",
      empty: "Everyone in this year's class has passed training or been made an Alpha."
    }
  ].freeze

  # "Waiting on training" splits by how far off training is, worst first. The
  # values are Intake's training_status strings; IntakeHelper#intake_training_status_text
  # already names the outcome on each row, so these headings only have to say what
  # the mentor does about the block.
  WAITING_SUBGROUPS = [
    { status: "none", title: "No Training Sign-Up", badge_color: :error },
    { status: "pending", title: "Signed Up for a Session", badge_color: :warning },
    { status: "not passed", title: "Did Not Pass a Session", badge_color: :error }
  ].freeze

  # Why this section is empty: the filters hid everyone, or there is genuinely
  # no one in it. Same order of precedence as the sibling page.
  def alpha_status_empty_message(section, filtering:)
    return "No one in #{section[:title].downcase} matched those filters." if filtering

    section[:empty]
  end
end
