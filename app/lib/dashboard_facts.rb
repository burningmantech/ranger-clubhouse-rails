# frozen_string_literal: true

# The substitutable fact set a dashboard task is evaluated against.
#
# Deep (isolating) for scalar facts and +now+; shallow (by-reference pass-through)
# for rich objects like +photo+/+surveys+/+ticketing_package+, whose AR/Setting
# coupling it does not pretend to hide. Built in production from a Milestones via
# +from_milestones+; constructed literally (any subset of attrs) in tests.
#
# These are *task facts*, distinct from the *view facts* (the raw Milestones +
# Person still passed to the task partials).
class DashboardFacts
  # Facts sourced verbatim from a Milestones. Names match Milestones readers so
  # migrating a task is a mechanical `@milestones.x` -> `facts.x`.
  MILESTONE_ATTRS = %i[
    period
    training trainings_available art_trainings needs_full_training is_binary
    online_course_passed online_course_enabled
    timesheet_confirmed timesheets_unverified did_work
    surveys ts_mentor_worked ts_mentor_survey_url
    ticketing_period ticketing_package
    photo missing_bpguid bmid_qualified has_reviewed_pi behavioral_agreement nda_required
    asset_authorized radio_checkout_agreement_enabled
    mvr_eligible mvr_potential ignore_mvr
    pvr_eligible pvr_potential ignore_pvr
    org_vehicle_insurance motorpool_agreement_available motorpool_agreement_signed
    vehicle_requests
    sandman_affidavit_signed sandman_affidavit_required
    is_cheetah_cub cheetah_cub_shift
    alpha_shift alpha_shifts_available alpha_shift_prep_link alpha_shift_publish_date
    dirt_shifts_available shift_signups
    burn_weekend_signup burn_weekend_available
  ].freeze

  # Person predicates the tasks read, as plain boolean facts (the `?` is dropped).
  PERSON_PREDICATES = {
    is_applicant: :is_applicant?,
    is_echelon: :is_echelon?,
    is_auditor: :is_auditor?,
    is_any_bonked: :is_any_bonked?
  }.freeze

  # +now+ keeps the tasks from reading the current time themselves; +status+ drives
  # type routing; +prev_completed+ is threaded by the orchestrator through the
  # applicant/auditor gate cascade.
  EXTRA_ATTRS = %i[status now prev_completed].freeze

  ATTRS = (MILESTONE_ATTRS + PERSON_PREDICATES.keys + EXTRA_ATTRS).freeze

  attr_reader(*ATTRS)

  def initialize(**attrs)
    unknown = attrs.keys - ATTRS
    if unknown.any?
      raise ArgumentError, "unknown DashboardFacts attribute(s): #{unknown.join(", ")}"
    end

    ATTRS.each { |attr| instance_variable_set("@#{attr}", attrs[attr]) }
    freeze
  end

  # Production adapter: the one place a built Milestones + Person is read into facts.
  # This and Milestones both read Current.time, which is pinned under Groundhog Day and
  # otherwise re-read per call — a sub-millisecond difference nothing compares.
  def self.from_milestones(milestones, person)
    attrs = MILESTONE_ATTRS.index_with { |attr| milestones.public_send(attr) }
    PERSON_PREDICATES.each { |fact, predicate| attrs[fact] = person.public_send(predicate) }
    attrs[:status] = person.status
    attrs[:now] = Current.time
    attrs[:prev_completed] = false
    new(**attrs)
  end

  # Facts are frozen; derive a sibling rather than mutate.
  def with_prev_completed(value)
    self.class.new(**to_h.merge(prev_completed: value))
  end

  def to_h
    ATTRS.index_with { |attr| public_send(attr) }
  end
end
