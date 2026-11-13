# frozen_string_literal: true

module Vc::ApplicationsHelper
  # STATUS_COLORS -> a ui_badge variant. ui_badge has no info or neutral
  # variant, so the two waiting states say secondary outright.
  STATUS_BADGE_VARIANTS = { "success" => :success, "warning" => :warning, "error" => :error,
                            "info" => :secondary, "neutral" => :secondary }.freeze

  # Badge for an application status, colored by workflow stage.
  def application_status_badge(status, size: nil)
    variant = STATUS_BADGE_VARIANTS.fetch(ProspectiveApplication::STATUS_COLORS[status], :secondary)
    label = ProspectiveApplication::STATUS_LABELS[status] || "Bug [#{status}]"
    ui_badge label, variant, size: size
  end

  def application_link(application)
    link_to application.application_id, vc_application_path(application), class: "underline font-semibold"
  end

  # Who is reviewing this application, as the hero panel's one-sentence
  # description. Prose rather than a pill: a chip here would compete with the
  # title and repeat the chip language of the action bar directly below it, and
  # a fixed-height one clips -- "Assigned to Julia Croft / Gadget (Org BMID
  # Person)" wraps to three lines at 375px. Plain text in the panel's own
  # description style: the sentence carries the meaning, not ink or weight.
  def application_assignment_note(application, viewer)
    if application.assigned_person_id == viewer.id
      "Assigned to you."
    elsif application.assigned_person_id
      "Assigned to #{application.assigned_person&.callsign}."
    else
      "Application is unassigned."
    end
  end

  FILTER_CHIP_LABELS = { "status" => "Status", "assigned_to" => "Assigned To", "name" => "Last Name",
                         "experience" => "BRC Experience", "age" => "Age" }.freeze

  # One filter_bar chip per filter that narrows the list. Each chip's URL sets
  # that one filter to "all" and keeps the rest -- dropping it instead would
  # put the status back to its Awaiting Review default, not remove it.
  def application_filter_chips(filter, vcs, year)
    values = filter.filter_values
    labels = {
      "status" => option_label(filter.status_options, filter.status),
      "assigned_to" => option_label(filter.assigned_to_options(vcs), filter.assigned_to),
      "name" => filter.name,
      "experience" => option_label(Vc::ApplicationFilterForm::EXPERIENCE_OPTIONS, filter.experience),
      "age" => option_label(Vc::ApplicationFilterForm::AGE_OPTIONS, filter.age)
    }

    values.filter_map do |key, value|
      next if value == UiComponents::FilterBarHelper::ALL_FILTER

      { label: "#{FILTER_CHIP_LABELS.fetch(key)}: #{labels[key] || value}",
        url: vc_applications_path(year:, Vc::ApplicationFilterForm::PARAM_SCOPE => values.merge(key => UiComponents::FilterBarHelper::ALL_FILTER)) }
    end
  end

  # The label a [label, value] / [group_label, [[label, value], ...]] option
  # list gives a value.
  def option_label(options, value)
    options.each do |label, option_value|
      if option_value.is_a?(Array)
        found = option_label(option_value, value)
        return found if found
      elsif option_value.to_s == value.to_s
        return label
      end
    end
    nil
  end

  # The six clickable dashboard groups on the applications index.
  def status_dashboard_groups(counts)
    [
      { label: "Pending", count: counts[:pending] || 0, icon: "clock", variant: :secondary,
        filter: ProspectiveApplication::STATUS_PENDING },
      { label: "Callsign", count: counts[:callsign] || 0, icon: "id-badge", variant: :secondary,
        filter: Vc::ApplicationFilterForm::GROUP_CALLSIGN },
      { label: "On Hold", count: counts[:held] || 0, icon: "circle-pause", variant: :warning,
        filter: Vc::ApplicationFilterForm::GROUP_HELD },
      { label: "Approved", count: counts[:approved] || 0, icon: "thumbs-up", variant: :success,
        filter: ProspectiveApplication::STATUS_APPROVED },
      { label: "Created", count: counts[:created] || 0, icon: "user-check", variant: :success,
        filter: ProspectiveApplication::STATUS_CREATED },
      { label: "Rejected", count: counts[:rejected] || 0, icon: "ban", variant: :error,
        filter: Vc::ApplicationFilterForm::GROUP_REJECTED }
    ]
  end

  # Build <option>/<optgroup> markup from a mixed list of [label, value]
  # pairs and [group_label, [[label, value], ...]] groups.
  def grouped_filter_options(options, selected)
    safe_join(options.map do |label, value|
      if value.is_a?(Array)
        content_tag(:optgroup, options_for_select(value, selected), label: label)
      else
        options_for_select([[label, value]], selected)
      end
    end)
  end

  # Review-progress strip states -> vc-progress-* modifier, each spelled out so
  # the class exists as written.
  VC_PROGRESS_CLASSES = {
    success: "vc-progress-success", warning: "vc-progress-warning", danger: "vc-progress-danger",
    pending: "vc-progress-pending", neutral: "vc-progress-neutral"
  }.freeze

  def vc_progress_class(state)
    "vc-progress-item #{VC_PROGRESS_CLASSES.fetch(state)}"
  end

  # The five review checks paired with the stage-card anchors they link to.
  def application_checks(application)
    [[application_events_check(application), "#stage-eligibility"],
     [application_age_check(application), "#stage-eligibility"],
     [application_paragraph_check(application), "#stage-paragraph"],
     [application_pii_check(application), "#stage-personal-info"],
     [application_handle_check(application), "#stage-callsign"]]
  end

  def application_checks_passed(checks)
    checks.count { |(state, _icon, _label), _anchor| state == :success }
  end

  STAGE_STATE_BADGES = {
    done: [:success, "circle-check", "Done"],
    problem: [:error, "circle-exclamation", "Problem"],
    waiting: [:warning, "hourglass-half", "Waiting"],
    todo: [:secondary, "arrow-right", "To do"]
  }.freeze

  # State badge shown in a stage card's summary row.
  def vc_stage_badge(stage)
    variant, icon, label = STAGE_STATE_BADGES[stage.state]
    ui_badge label, variant, icon:, icon_type: :solid
  end

  # Anchor pill for one review check; icon_only collapses the label to
  # screen-reader text (used in the action bar).
  def vc_check_link(check, anchor, icon_only: false)
    state, icon, label = check
    label_html = icon_only ? content_tag(:span, label, class: "sr-only") : " #{label}"
    link_to safe_join([fa_icon(icon, :solid), label_html]), anchor,
            class: class_names("no-decoration", vc_progress_class(state), "vc-check-chip": icon_only),
            title: label
  end

  def application_events_check(application)
    if application.all_events.empty?
      [:danger, "ban", "No Events"]
    elsif application.brc_experience_okay?
      [:success, "check", "BRC Events"]
    else
      [:danger, "xmark", "BRC Issue"]
    end
  end

  def application_age_check(application)
    application.is_over_18 ? [:success, "check", "Age 18+"] : [:danger, "xmark", "Under 18"]
  end

  def application_paragraph_check(application)
    case application.why_volunteer_review
    when ProspectiveApplication::WHY_VOLUNTEER_REVIEW_OKAY then [:success, "check", "Paragraph"]
    when ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM then [:danger, "ban", "Paragraph"]
    else [:warning, "question", "Paragraph"]
    end
  end

  def application_pii_check(application)
    application.personal_info_issues? ? [:warning, "exclamation", "PII"] : [:success, "check", "PII"]
  end

  def application_handle_check(application)
    if application.approved_handle.present?
      [:success, "check", "Handle"]
    elsif application.processing_callsign?
      [:pending, "hourglass-half", "Handle"]
    else
      [:neutral, "minus", "Handle"]
    end
  end
end
