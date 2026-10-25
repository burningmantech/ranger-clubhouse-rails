# frozen_string_literal: true

module Training::SessionsHelper
  # How the session page shows each trainee status, in the order the score
  # dialog offers them. The dialog, the card badge, the stat tile and the
  # trainer's report mark all read this one table, so they never disagree, and
  # the stored codes never print. Every badge carries an icon, so no status
  # reads by colour alone. Pending has no mark: the trainer's report is printed
  # before the session, so an undecided trainee gets the tick box instead.
  # IntakeHelper#training_status_badge is a different chip, keyed by Intake's
  # own words.
  TRAINEE_STATUS_BADGES = {
    TraineeStatus::STATUS_PENDING => { label: "Pending", variant: :secondary, icon: "hourglass-half" },
    TraineeStatus::STATUS_PASSED => { label: "Passed", variant: :success, icon: "circle-check", mark: "Y" },
    TraineeStatus::STATUS_NO_SHOW => { label: "No Show", variant: :error, icon: "user-slash", mark: "NS" },
    TraineeStatus::STATUS_NOT_PASSED => { label: "Not Passed", variant: :error, icon: "circle-xmark", mark: "N" }
  }.freeze

  # [label, value] pairs for the score dialog's select.
  def trainee_status_options
    TRAINEE_STATUS_BADGES.map { |status, badge| [badge[:label], status] }
  end

  def trainee_status_badge(status)
    badge = TRAINEE_STATUS_BADGES.fetch(status)
    ui_badge badge[:label], badge[:variant], icon: badge[:icon], icon_type: :solid
  end

  # Coloured only when there is something to count, the rule the page already
  # applies to its Inactive / Retired tile.
  def trainee_status_stat_box(status, count)
    badge = TRAINEE_STATUS_BADGES.fetch(status)
    ui_stat_box count.to_s, badge[:label], variant: count.positive? ? badge[:variant] : :secondary
  end

  def trainee_report_mark(status)
    TRAINEE_STATUS_BADGES.dig(status, :mark)
  end

  # Why a roster member cannot be picked in the graduation dialog.
  def graduation_ineligibility_reason(graduation, candidate)
    case candidate.eligibility
    when TrainingSession::Graduation::AUDITOR
      "Is an auditor"
    when TrainingSession::Graduation::NOT_PASSED
      "Has not been marked as passed"
    when TrainingSession::Graduation::GRADUATED
      "Already holds: #{graduation.position_titles.to_sentence}"
    when TrainingSession::Graduation::FULLY_GRADUATED
      "Already holds: #{graduation.veteran_position.last}"
    else
      candidate.eligibility.humanize
    end
  end
end
