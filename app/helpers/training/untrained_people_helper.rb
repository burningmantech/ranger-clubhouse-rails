# frozen_string_literal: true

module Training::UntrainedPeopleHelper
  FILTER_CHIP_LABELS = { blocker: "Blocker", callsign: "Callsign" }.freeze

  # Why a person is on the list. The icon carries the same meaning as the
  # color, so the two never depend on color alone.
  BLOCKERS = {
    Training::UntrainedPeopleReport::NO_SIGNUP => [:error, "calendar-xmark"],
    Training::UntrainedPeopleReport::NOT_PASSED => [:warning, "hourglass-half"]
  }.freeze

  def untrained_people_blocker_badge(blocker)
    variant, icon = BLOCKERS.fetch(blocker)
    ui_badge Training::UntrainedPeopleReport::BLOCKER_LABELS.fetch(blocker), variant,
             icon:, icon_type: :solid, class: "whitespace-nowrap"
  end

  # One stat box per blocker, colored from the same BLOCKERS table as the
  # badges so the two can never disagree; zero-count blockers are omitted.
  def untrained_people_blocker_stat_boxes(blocker_counts)
    boxes = BLOCKERS.filter_map do |blocker, (variant, _icon)|
      count = blocker_counts.fetch(blocker, 0)
      next if count.zero?

      ui_stat_box count.to_s, Training::UntrainedPeopleReport::BLOCKER_LABELS.fetch(blocker), variant:
    end
    safe_join(boxes)
  end

  # Blocker choices carry their counts so the operator can see where the list
  # sits before narrowing it; a choice that can only return nothing is noise.
  def untrained_people_blocker_options(blocker_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      BLOCKERS.keys.filter_map do |blocker|
        count = blocker_counts.fetch(blocker, 0)
        ["#{Training::UntrainedPeopleReport::BLOCKER_LABELS.fetch(blocker)} (#{count})", blocker] if count.positive?
      end
  end

  def untrained_people_filter_chips(filter_params, slug, year)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:untrained_people_chip_value)) do |remaining|
      training_untrained_people_path(slug, **remaining, year:)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def untrained_people_chip_value(key, value)
    (key == :blocker) ? Training::UntrainedPeopleReport::BLOCKER_LABELS.fetch(value, value) : value
  end
end
