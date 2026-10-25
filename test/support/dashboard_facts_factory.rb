# frozen_string_literal: true

require "ostruct"

# In-memory adapter for DashboardFacts — the test-only sibling of
# +DashboardFacts.from_milestones+.
#
# +from_milestones+ builds facts from ~40 AR queries + Settings, so most
# archetypes are unreachable from fixtures alone. This factory hand-builds a
# complete, internally-consistent DashboardFacts for a named archetype whose
# +status+ routes Dashboard#type to the intended branch and whose rich facts
# (training, surveys, photo, ...) are supplied as duck-typed stand-ins so the
# selected task partials never NoMethodError.
#
# Usage:
#   DashboardFactsFactory.for(:active_ranger)
#   DashboardFactsFactory.for(:auditor, period: DashboardTask::AFTER_EVENT)
module DashboardFactsFactory
  module_function

  # Build a complete DashboardFacts for +archetype+, with +overrides+ applied last.
  def for(archetype, **overrides)
    defaults = case archetype
               when :active_ranger then active_ranger_defaults
               when :echelon then echelon_defaults
               when :auditor then auditor_defaults
               when :auditor_offseason then auditor_offseason_defaults
               when :applicant_prospective then applicant_prospective_defaults
               when :ticketing_open_ranger then ticketing_open_ranger_defaults
               when :survey_bearing_ranger then survey_bearing_ranger_defaults
               else
                 raise ArgumentError, "unknown DashboardFacts archetype: #{archetype.inspect}"
               end

    DashboardFacts.new(**defaults.merge(overrides))
  end

  # --- duck-typed rich stand-ins -----------------------------------------

  # A photo that is already approved: UploadPhoto/PhotoApproval resolve to
  # skip/completed without reaching the upload action partials.
  def approved_photo
    PersonPhoto::Info.new(
      photo_status: PersonPhoto::APPROVED,
      photo: nil,
      upload_enabled: true,
      rejections: [],
      reject_message: nil
    )
  end

  # No outstanding surveys: every survey task skips.
  def no_surveys
    Survey::UnansweredResult.new(sessions: nil, trainers: nil, alpha_survey: nil)
  end

  # A passed In-Person Training session (duck-typed like Training::EducationInfo).
  def passed_training
    Training::EducationInfo.new(status: Training::PASS)
  end

  # A signed-up shift summary (only read when SignUpForShifts resolves to completed).
  def shift_summary(slot_count: 0, credits: 0.0)
    OpenStruct.new(slot_count:, credits:)
  end

  # An access document fake responding to every predicate TicketHelper.build_tickets
  # reads, plus the +type+/+name+/+type_label+ the _dashboard_tickets partial renders.
  def access_doc(using: false, regular: false, banked: false, qualified: false,
                 type: AccessDocument::STAFF_CREDENTIAL, name: nil, type_label: "Ticket")
    OpenStruct.new(
      is_using?: using,
      regular_ticket?: regular,
      is_banked?: banked,
      is_qualified?: qualified,
      type:,
      name:,
      type_label:
    )
  end

  # A ticketing package whose collections/predicates back TicketHelper.build_tickets
  # and the _dashboard_tickets partial. Defaults model a finished, all-claimed package
  # so TicketingOpen resolves to COMPLETED and the partial exercises its claimed branch.
  def ticketing_package(
    access_documents: [access_doc(using: true, regular: true, type_label: "Setup Access Pass")],
    gift_items: [], lsd_items: [], provisions_banked: true, provision_records: [],
    started_at: Time.utc(2026, 6, 1), finished_at: Time.utc(2026, 6, 2)
  )
    OpenStruct.new(
      access_documents:,
      gift_items:,
      lsd_items:,
      provisions_banked:,
      provision_records:,
      started_at:,
      finished_at:
    )
  end

  # Outstanding surveys of every kind a survey task reads: a training session
  # (TakeStudentSurvey), an alpha survey (TakeAlphaSurvey), and a trainer survey
  # (TrainerSurvey). Built from the production Survey value types the partials iterate.
  def outstanding_surveys
    Survey::UnansweredResult.new(
      sessions: [
        Survey::SurveySession.new(
          id: 101,
          type: Survey::TRAINING,
          begins: "2026-04-12 09:00:00",
          description: "Morning Session",
          position_id: 1,
          position_title: "In-Person Training"
        )
      ],
      trainers: [
        Survey::TrainerSurvey.new(
          id: 201,
          type: Survey::TRAINER,
          description: "Afternoon Session",
          begins: "2026-04-12 13:00:00",
          position_id: 2,
          position_title: "Trainer",
          trainers: []
        )
      ],
      alpha_survey: true
    )
  end

  # --- archetype default fact sets ---------------------------------------

  # Shared facts every coherent archetype needs so the orchestrator and the
  # selected partials have non-nil rich objects to read.
  def common_defaults
    {
      now: Time.zone.local(2026, 8, 25, 12, 0, 0),
      prev_completed: false,
      is_applicant: false,
      is_echelon: false,
      is_auditor: false,
      is_any_bonked: false,
      photo: approved_photo,
      surveys: no_surveys,
      art_trainings: [],
      vehicle_requests: [],
      shift_signups: shift_summary,
      training: passed_training,
      ticketing_package: nil,
      ticketing_period: nil
    }.freeze
  end

  # Active Ranger during the event: most tasks complete/skip cleanly.
  def active_ranger_defaults
    common_defaults.merge(
      status: Person::ACTIVE,
      period: DashboardTask::DURING_EVENT,
      online_course_passed: true,
      online_course_enabled: true,
      has_reviewed_pi: true,
      bmid_qualified: true,
      missing_bpguid: false,
      nda_required: false,
      trainings_available: true,
      dirt_shifts_available: false,
      motorpool_agreement_available: false,
      radio_checkout_agreement_enabled: false,
      asset_authorized: true,
      did_work: false
    )
  end

  # Echelon volunteer: routes through ranger_dashboard's ECHELON_STEPS branch.
  def echelon_defaults
    common_defaults.merge(
      status: Person::ECHELON,
      period: DashboardTask::BEFORE_EVENT,
      is_echelon: true,
      online_course_passed: true,
      online_course_enabled: true,
      has_reviewed_pi: true,
      bmid_qualified: true,
      missing_bpguid: false,
      nda_required: false,
      dirt_shifts_available: true,
      motorpool_agreement_available: false,
      asset_authorized: true,
      did_work: false
    )
  end

  # Auditor: routes Dashboard#type to :auditor (AUDITOR_STEPS).
  def auditor_defaults
    common_defaults.merge(
      status: Person::AUDITOR,
      period: DashboardTask::BEFORE_EVENT,
      is_auditor: true,
      has_reviewed_pi: true,
      online_course_passed: true,
      online_course_enabled: true,
      trainings_available: true
    )
  end

  # Prospective applicant: routes Dashboard#type to :applicant.
  def applicant_prospective_defaults
    common_defaults.merge(
      status: Person::PROSPECTIVE,
      period: DashboardTask::BEFORE_EVENT,
      is_applicant: true,
      training: Training::EducationInfo.new(status: Training::NO_SHIFT),
      photo: approved_photo,
      online_course_passed: false,
      online_course_enabled: true,
      behavioral_agreement: true,
      missing_bpguid: false,
      trainings_available: true,
      alpha_shift: nil,
      alpha_shifts_available: false,
      alpha_shift_prep_link: "https://example.test/alpha-prep",
      alpha_shift_publish_date: "2026-07-08",
      radio_checkout_agreement_enabled: true,
      motorpool_agreement_available: false
    )
  end

  # Auditor in the off-season: routes to :auditor's AUDITOR_OFFSEASON_STEPS, whose
  # only step is RangerInterest -> _ranger_interest_signup (reads step.payload.year).
  def auditor_offseason_defaults
    auditor_defaults.merge(
      period: DashboardTask::AFTER_EVENT
    )
  end

  # Active Ranger with ticketing open and a finished, all-claimed package, so
  # TicketingOpen resolves to COMPLETED and renders _dashboard_tickets against a
  # populated +payload.tickets+ (claimed/provision/banked branches all reachable).
  def ticketing_open_ranger_defaults
    active_ranger_defaults.merge(
      period: DashboardTask::BEFORE_EVENT,
      ticketing_period: "open",
      ticketing_package: ticketing_package
    )
  end

  # Active Ranger with outstanding surveys of every kind, so TakeStudentSurvey /
  # TakeAlphaSurvey / TrainerSurvey all resolve to OPTIONAL and render their
  # partials off +facts.surveys+.
  def survey_bearing_ranger_defaults
    active_ranger_defaults.merge(
      period: DashboardTask::POST_EVENT,
      surveys: outstanding_surveys,
      did_work: true,
      timesheet_confirmed: true,
      timesheets_unverified: false
    )
  end
end
