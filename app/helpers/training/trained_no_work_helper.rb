# frozen_string_literal: true

module Training::TrainedNoWorkHelper
  FILTER_CHIP_LABELS = { status: "Status", via: "Qualified Via", callsign: "Callsign" }.freeze

  # Why a person is on the list. The icon carries the same meaning as the
  # color, so the two kinds never depend on color alone. chalkboard-user ships
  # in solid only -- :regular renders a tofu box.
  QUALIFICATIONS = {
    passed: ["Passed training", :primary, "graduation-cap"],
    taught: ["Taught session", :secondary, "chalkboard-user"]
  }.freeze

  def trained_no_work_qualification_badge(qualification)
    label, variant, icon = QUALIFICATIONS.fetch(qualification.kind)
    ui_badge label, variant, icon:, icon_type: :solid
  end

  # Status choices carry their counts so the operator can see where the list
  # sits before narrowing it. Statuses no one on the list holds are omitted --
  # a choice that can only return nothing is noise.
  def trained_no_work_status_options(status_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      Person::ACTIVE_STATUSES.filter_map do |status|
        count = status_counts.fetch(status, 0)
        ["#{status} (#{count})", status] if count.positive?
      end
  end

  # Trainee vs trainer, counted the same way as the status choices. A training
  # with no trainer positions never offers "Taught session".
  def trained_no_work_via_options(via_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      QUALIFICATIONS.filter_map do |kind, (label, _)|
        count = via_counts.fetch(kind, 0)
        ["#{label} (#{count})", kind.to_s] if count.positive?
      end
  end

  def trained_no_work_filter_chips(filter_params, slug, year)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:trained_no_work_chip_value)) do |remaining|
      training_trained_no_work_path(slug, **remaining, year:)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def trained_no_work_chip_value(key, value)
    case key
    when :via then QUALIFICATIONS.dig(value.to_sym, 0) || value
    else value
    end
  end
end
