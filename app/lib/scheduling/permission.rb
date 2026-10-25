# frozen_string_literal: true

require_relative "../burn_weekend_shift_recommendation"

class Scheduling::Permission
  attr_reader :person,
              :year,
              :all_signups_allowed,
              :online_course_enabled,
              :training_signups_allowed,
              :requirements,
              :recommend_burn_weekend_shift,
              :needs_full_training

  def initialize(person, year)
    @person = person
    @year = year
    @requirements = []

    determine_permission
  end

  private

  def determine_permission
    status = @person.status

    if status == Person::PAST_PROSPECTIVE
      @all_signups_allowed = false
      @training_signups_allowed = false
      @requirements << Scheduling::IS_PAST_PROSPECTIVE
      return
    end

    @online_course_enabled = Setting.get_value(Setting::ONLINE_COURSE_ENABLED)

    is_auditor = (status == Person::AUDITOR)
    is_pnv = status == Person::PROSPECTIVE || status == Person::ALPHA
    is_echelon = (status == Person::ECHELON)

    photo_status = determine_photo_status(is_auditor)
    oc_completed = PersonOnlineCourse.did_complete_for_year?(person.id, @year, Position::TRAINING)

    @training_signups_allowed = is_echelon || oc_completed
    @all_signups_allowed = true

    if is_auditor || is_pnv
      # Auditors & PNVs MUST review their Personal information first before doing anything else.
      # Everyone is allowed to review at their leisure.

      @requirements << Scheduling::MISSING_PI_REVIEW if person.reviewed_pi_at.blank?
      @requirements << (@online_course_enabled ? Scheduling::OC_IS_NOT_COMPLETED : Scheduling::OC_IS_DISABLED) unless oc_completed
    elsif !is_echelon && !oc_completed
      # Online Course not completed. Bad Ranger, no biscuit.
      @training_signups_allowed = false
    end

    unless is_auditor
      # PNVs, Rangers, and Non-Rangers must have an approved callsign, and an approved photo
      unless person.callsign_approved?
        @requirements << Scheduling::MISSING_CALLSIGN_APPROVAL
      end

      if photo_status != PersonPhoto::APPROVED && photo_status != :not_required
        @requirements << Scheduling::MISSING_PHOTO_APPROVAL
      end

      # Everyone except Auditors and Non Rangers need to have BPGUID on file.
      if !is_echelon && person.bpguid.blank?
        @requirements << Scheduling::MISSING_BPGUID
      end
    end

    if @requirements.any?
      @training_signups_allowed = false
      @all_signups_allowed = false
    end

    @needs_full_training, _ = Training.requires_training_full_day?(person)
    @recommend_burn_weekend_shift = BurnWeekendShiftRecommendation.recommend?(person)
  end

  def determine_photo_status(is_auditor)
    return PersonPhoto::APPROVED if person.photo.present?
    return :not_required if is_auditor
    return PersonPhoto::SUBMITTED if person.submitted_photo.present?

    :missing
  end
end
