# frozen_string_literal: true

class Dashboard
  RESULT_PRIORITIES = {
    DashboardTask::STATUS_URGENT => 1,
    DashboardTask::STATUS_ACTION_NEEDED => 2,
    # 3 is "sticky completed"
    DashboardTask::STATUS_WAITING => 4,
    DashboardTask::STATUS_NOT_AVAILABLE => 5,
    DashboardTask::STATUS_OPTIONAL => 6,
    DashboardTask::STATUS_COMPLETED => 7
  }.freeze

  attr_reader :facts

  TYPE_APPLICANT = :applicant
  TYPE_AUDITOR = :auditor
  TYPE_BONKED = :bonked
  TYPE_PAST_PROSPECTIVE = :past_prospective
  TYPE_RANGER = :ranger

  def initialize(facts)
    @facts = facts
  end

  def type
    case @facts.status
    when Person::PAST_PROSPECTIVE
      TYPE_PAST_PROSPECTIVE
    when Person::BONKED, Person::UBERBONKED
      TYPE_BONKED
    when Person::PROSPECTIVE, Person::ALPHA
      TYPE_APPLICANT
    when Person::AUDITOR
      TYPE_AUDITOR
    else
      TYPE_RANGER
    end
  end

  def groups
    @dashboard_groups ||= case type
                          when :past_prospective, :bonked
                            # no dashboard tasks
                            nil
                          when :applicant
                            applicant_dashboard
                          when :auditor
                            auditor_dashboard
                          else
                            ranger_dashboard
                          end
  end

  def ranger_dashboard
    steps_list = @facts.is_echelon ? ECHELON_STEPS : RANGER_STEPS
    groups = []

    processed = process_step_group(steps_list)
    immediate_steps = processed[:immediate_steps]
    steps = processed[:steps]
    completed = processed[:completed]
    note = processed[:note]
    is_post_event = @facts.period == DashboardTask::POST_EVENT
    is_after_event = @facts.period == DashboardTask::AFTER_EVENT

    if immediate_steps.any?
      groups << StepGroup.new("IMMEDIATE ACTION REQUIRED", immediate_steps, true, true)
      groups << StepGroup.new("Important Note", note, true, true) if note.any?
    elsif steps.empty?
      groups << StepGroup.new("Important Note", note, true, true) if note.any?

      no_more_step = (is_post_event || is_after_event) ? AFTER_EVENT_NO_MORE_THINGS_STEP : BEFORE_EVENT_NO_MORE_THINGS_STEP
      steps << no_more_step
    elsif note.any?
      groups << StepGroup.new("Important Note", note, true, true)
    end

    if !is_after_event || !is_post_event || steps.any?
      title = case @facts.period
              when DashboardTask::BEFORE_EVENT
                "Preparation for Playa"
              when DashboardTask::DURING_EVENT
                "Event Action Items"
              when DashboardTask::AFTER_EVENT
                "Off Season Action Items"
              else
                "Post Event Action Items"
              end
      groups << StepGroup.new(title, steps, immediate_steps.empty?)
    end

    groups << StepGroup.new("Completed", completed) if completed.any?
    groups.last.is_last = true if groups.any?

    groups
  end

  def applicant_dashboard
    groups = []
    completed = []
    have_active_group = false
    prev_completed = true

    APPLICANT_TASK_GROUPS.each do |group|
      have_action = false
      steps_completed = true
      steps = []

      group[:steps].each do |step_class|
        check = evaluate_step(step_class, prev_completed:)
        next if check.result == DashboardTask::STATUS_SKIP

        check.title ||= step_class.title

        if check.result == DashboardTask::STATUS_COMPLETED
          completed << check
        else
          if check.result != DashboardTask::STATUS_OPTIONAL
            steps_completed = false
            if !have_action || check.result == DashboardTask::STATUS_ACTION_NEEDED
              check.is_active = true
              have_action = true
            end
          end
          steps << check
        end
      end

      next if steps.empty?

      actions = StepGroup.new(group[:title], steps)

      prev_completed = false if !steps_completed && prev_completed

      if !have_active_group && have_action
        actions.is_active = true
        have_active_group = true
      elsif have_active_group
        steps.each do |t|
          if t.result == DashboardTask::STATUS_ACTION_NEEDED || t.result == DashboardTask::STATUS_URGENT
            t.result = DashboardTask::STATUS_NOT_AVAILABLE
          end
        end
      end

      if actions.is_active
        actions.have_urgent_actions = steps.any? { |t| t.result == DashboardTask::STATUS_URGENT }
        actions.have_actions = steps.any? { |t| ![DashboardTask::STATUS_COMPLETED, DashboardTask::STATUS_WAITING, DashboardTask::STATUS_OPTIONAL].include?(t.result) }
        actions.have_waiting = steps.any? { |t| t.result == DashboardTask::STATUS_WAITING }
      end

      groups << actions
    end

    if completed.any?
      groups << StepGroup.new("Completed", completed)
    end

    groups.last.is_last = true if groups.any?
    groups
  end

  def auditor_dashboard
    steps = []
    prev_completed = true

    is_off_season = [DashboardTask::AFTER_EVENT, DashboardTask::POST_EVENT].include?(@facts.period)
    period_steps = is_off_season ? AUDITOR_OFFSEASON_STEPS : AUDITOR_STEPS

    period_steps.each do |step_class|
      check = evaluate_step(step_class, prev_completed:)
      next if check.result == DashboardTask::STATUS_SKIP

      check.title ||= step_class.title

      if check.result != DashboardTask::STATUS_COMPLETED && check.result != DashboardTask::STATUS_OPTIONAL
        if check.result == DashboardTask::STATUS_ACTION_NEEDED || check.result == DashboardTask::STATUS_URGENT
          check.is_active = true
        elsif check.result != DashboardTask::STATUS_BLOCKED
          check.result = DashboardTask::STATUS_NOT_AVAILABLE
        end
        prev_completed = false
      end
      steps << check
    end

    return [] if steps.empty?

    group = StepGroup.new("Auditor Action Items", steps, true)
    group.is_last = true
    [group]
  end

  private

  def process_step_group(checks)
    period = @facts.period
    have_action = false
    steps = []
    immediate_steps = []
    completed = []
    note = []

    checks.each do |step_class|
      if match_period(step_class.period, period, true) || match_period(step_class.skip_period, period, false)
        next
      end

      check = step_class.check(@facts)
      next if check.result == DashboardTask::STATUS_SKIP

      check.title ||= step_class.title

      if check.result != DashboardTask::STATUS_COMPLETED
        if !have_action || [DashboardTask::STATUS_ACTION_NEEDED, DashboardTask::STATUS_OPTIONAL, DashboardTask::STATUS_URGENT].include?(check.result)
          check.is_active = true
          have_action = true
        end
      end

      if check.result == DashboardTask::STATUS_COMPLETED
        completed << check
      elsif check.immediate || step_class.immediate
        immediate_steps << check
      elsif check.result == DashboardTask::STATUS_NOTE
        note << check
      else
        steps << check
      end
    end

    sort_steps(steps)
    sort_steps(immediate_steps)
    sort_steps(completed)

    { steps:, immediate_steps:, completed:, note: }
  end

  def evaluate_step(step_class, prev_completed:)
    step_class.check(@facts.with_prev_completed(prev_completed))
  end

  def match_period(action_period, current_period, does_not_equal)
    return false if action_period.empty?

    if does_not_equal
      action_period.is_a?(Array) ? !action_period.include?(current_period) : action_period != current_period
    else
      action_period.is_a?(Array) ? action_period.include?(current_period) : action_period == current_period
    end
  end

  def sort_steps(steps)
    steps.each_with_index { |s, idx| s.sort_index = idx }
    steps.sort! do |a, b|
      p_a = a.sticky ? 3 : RESULT_PRIORITIES[a.result] || 99
      p_b = b.sticky ? 3 : RESULT_PRIORITIES[b.result] || 99

      comp = p_a <=> p_b
      (comp == 0) ? a.sort_index <=> b.sort_index : comp
    end
  end

  class StepGroup
    attr_accessor :title, :steps, :is_active, :is_urgent, :is_last, :include_photo_step
    attr_accessor :have_urgent_actions, :have_actions, :have_waiting

    def initialize(title, steps, is_active = false, is_urgent = false)
      @title = title
      @steps = steps
      @is_active = is_active
      @is_urgent = is_urgent
      @is_last = false
    end
  end

  # Lists of steps

  RANGER_STEPS = [
    DashboardTasks::BmidWillNotBePrinted,
    DashboardTasks::SignNda,
    DashboardTasks::UploadPhoto,
    DashboardTasks::PhotoApproval,
    DashboardTasks::MissingBpguid,
    DashboardTasks::VerifyTimesheets,
    DashboardTasks::TicketingOpen,
    DashboardTasks::VerifyPersonalInfo,
    DashboardTasks::OnlineCourse,
    DashboardTasks::SignUpForTraining,
    DashboardTasks::AttendTraining,
    DashboardTasks::GreenDotMenteeShift,
    DashboardTasks::AttendGreenDotMenteeShift,
    DashboardTasks::SignMotorPoolProtocol,
    DashboardTasks::MvrRequest,
    DashboardTasks::SignRadioCheckoutAgreement,
    DashboardTasks::VerifyTimesheetsFinished,
    DashboardTasks::ArtTraining,
    DashboardTasks::BurnWeekendShift,
    DashboardTasks::SignUpForShifts,
    DashboardTasks::TakeStudentSurvey,
    DashboardTasks::TakeAlphaSurvey,
    DashboardTasks::TrainerSurvey,
    DashboardTasks::CheetahCubShift,
    DashboardTasks::AttendCheetahCubShift,
    DashboardTasks::TroubleshooterMentorSurvey,
    DashboardTasks::TicketingClosed,
    DashboardTasks::SandmanAffidavit,
    DashboardTasks::VehicleRequests,
    DashboardTasks::AfterEventStatusAdvisory
  ].freeze

  ECHELON_STEPS = [
    DashboardTasks::SignNda,
    DashboardTasks::UploadPhoto,
    DashboardTasks::PhotoApproval,
    DashboardTasks::MissingBpguid,
    DashboardTasks::OnlineCourse,
    DashboardTasks::TicketingOpen,
    DashboardTasks::TicketingClosed,
    DashboardTasks::VehicleRequests,
    DashboardTasks::VerifyTimesheets,
    DashboardTasks::VerifyPersonalInfo,
    DashboardTasks::SignUpForShifts,
    DashboardTasks::SignMotorPoolProtocol,
    DashboardTasks::MvrRequest,
    DashboardTasks::SignRadioCheckoutAgreement,
    DashboardTasks::VerifyTimesheetsFinished
  ].freeze

  SETUP_ACCOUNT_STEPS = [
    DashboardTasks::UploadPhoto,
    DashboardTasks::PhotoApproval,
    DashboardTasks::VerifyPersonalInfo,
    DashboardTasks::SignBehavioralAgreement,
    DashboardTasks::MissingBpguid
  ].freeze

  TRAINING_STEPS = [
    DashboardTasks::OnlineCourse,
    DashboardTasks::SignUpForTraining,
    DashboardTasks::AttendTraining,
    DashboardTasks::TakeStudentSurvey
  ].freeze

  ALPHA_STEPS = [
    DashboardTasks::SignRadioCheckoutAgreement,
    DashboardTasks::SignMotorPoolProtocol,
    DashboardTasks::SignUpForAlphaShift,
    DashboardTasks::AttendAlphaShift,
    DashboardTasks::TakeAlphaSurvey
  ].freeze

  APPLICANT_TASK_GROUPS = [
    { title: "Set Up Your Clubhouse Account", steps: SETUP_ACCOUNT_STEPS },
    { title: "Train to Be a Ranger", steps: TRAINING_STEPS },
    { title: "Attend Your Alpha Shift", steps: ALPHA_STEPS }
  ].freeze

  AUDITOR_STEPS = [
    DashboardTasks::VerifyPersonalInfo,
    DashboardTasks::OnlineCourse,
    DashboardTasks::SignUpForTraining,
    DashboardTasks::AttendTraining,
    DashboardTasks::TakeStudentSurvey,
    DashboardTasks::RangerInterest
  ].freeze

  AUDITOR_OFFSEASON_STEPS = [
    DashboardTasks::RangerInterest
  ].freeze

  AFTER_EVENT_NO_MORE_THINGS_STEP = DashboardTaskResult.new(
    title: "Watch Announce and Thank You!",
    result: DashboardTask::STATUS_NOTE,
    partial: "after_event_no_more_things",
    is_active: true
  ).freeze

  BEFORE_EVENT_NO_MORE_THINGS_STEP = DashboardTaskResult.new(
    title: "Watch the Announce Mailing List",
    result: DashboardTask::STATUS_ACTION_NEEDED,
    partial: "no_things_at_the_moment",
    is_active: true
  ).freeze
end
