# frozen_string_literal: true

# Maps a prospective application's status and review checks onto the five
# stage cards that structure the VC application review page.
#
# Stage states:
#   :done    - complete; collapses to a one-line summary
#   :problem - a check failed and needs a VC decision (hold/reject/edit)
#   :waiting - on hold; the ball is in the applicant's court
#   :todo    - reviewable now
#
# The first actionable stage (:todo or :problem) renders expanded. Once a
# final decision is made (approved / created / rejected / duplicate) nothing
# is actionable and every stage collapses to a read-only recap.
class Vc::ReviewStages
  Stage = Data.define(:key, :title, :jump_label, :state, :summary) do
    # Waiting stages are parked with the applicant; done stages are finished.
    def actionable? = state == :todo || state == :problem
  end

  def initialize(application)
    @application = application
  end

  def stages
    @stages ||= [eligibility, paragraph, personal_info, callsign, decision]
  end

  def first_actionable
    return nil if post_decision?

    stages.find(&:actionable?)
  end

  def open?(stage)
    stage == first_actionable
  end

  def post_decision?
    @application.decided?
  end

  private

  def eligibility
    state, summary =
      if @application.status_hold_qualification_issue?
        [:waiting, "On hold — applicant asked to confirm event attendance"]
      elsif @application.status_hold_age_issue?
        [:waiting, "On hold — applicant asked to confirm age"]
      elsif @application.status_hold_rrn_check?
        [:waiting, "On hold — awaiting RRN verification"]
      elsif !@application.is_over_18
        [:problem, "Applicant is under 18"]
      elsif !@application.brc_experience_okay?
        [:problem, @application.experience_issue || "Event attendance issue"]
      else
        [:done, "Events okay · 18 or older"]
      end
    Stage.new(key: :eligibility, title: "Eligibility", jump_label: "Review Eligibility", state:, summary:)
  end

  def paragraph
    state, summary =
      case @application.why_volunteer_review
      when ProspectiveApplication::WHY_VOLUNTEER_REVIEW_OKAY
        [:done, "Reviewed — okay"]
      when ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM
        if @application.status_hold_why_ranger_question?
          [:waiting, "On hold — answer issue raised with the applicant"]
        else
          [:problem, "Marked as a problem"]
        end
      else
        [:todo, "Not reviewed yet"]
      end
    Stage.new(key: :paragraph, title: "Why Ranger?", jump_label: "Review Why Ranger?", state:, summary:)
  end

  def personal_info
    state, summary =
      if @application.status_hold_pii_issue?
        if @application.personal_info_issues?
          [:waiting, "On hold — applicant asked for: #{@application.blank_personal_info.join(", ")}"]
        else
          [:todo, "Issues resolved — approve the application to notify the applicant"]
        end
      elsif @application.personal_info_issues?
        [:problem, "Missing: #{@application.blank_personal_info.join(", ")}"]
      else
        [:done, "Complete"]
      end
    Stage.new(key: :personal_info, title: "Personal Info", jump_label: "Resolve Personal Info", state:, summary:)
  end

  def callsign
    state, summary =
      if @application.approved_handle.present?
        [:done, "Approved callsign: #{@application.approved_handle}"]
      elsif @application.status_more_handles?
        [:waiting, "On hold — more handles requested from the applicant"]
      elsif @application.status_handle_check?
        [:todo, "Cleared for processing — vet the submitted handles"]
      elsif @application.handle_list.empty?
        [:todo, "No handles submitted"]
      else
        [:todo, "#{@application.handle_list.size} handles submitted, none assigned"]
      end
    Stage.new(key: :callsign, title: "Callsign", jump_label: "Process Callsign", state:, summary:)
  end

  def decision
    state, summary =
      if @application.stop_status?
        [:done, @application.status_label]
      elsif @application.status_created?
        [:done, "Approved — the account was created"]
      elsif @application.status_approved?
        [:done, "Approved — awaiting account creation"]
      else
        [:todo, "Not decided yet"]
      end
    Stage.new(key: :decision, title: "Decision", jump_label: "Make the Decision", state:, summary:)
  end
end
