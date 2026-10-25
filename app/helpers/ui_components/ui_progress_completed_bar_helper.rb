# frozen_string_literal: true

module UiComponents
  module UiProgressCompletedBarHelper
    # Shared constants for consistent styling
    PROGRESS_CONTAINER = "progress-container"
    PROGRESS_BAR = "progress-bar"
    PROGRESS_BAR_PULSE = "progress-bar-pulse"
    LABELS_CONTAINER = "progress-labels-container"

    # Shared progress bar rendering with full ARIA support
    def render_progress_bar(completed:, total:, start_label: nil, end_label: nil, aria_label: nil)
      completed = completed.to_i
      total = total.to_i
      progress_percent = total.positive? ? (completed.to_f / total * 100).round : 0
      progress_percent = 5 if progress_percent < 5
      default_aria_label = "Progress: #{completed} of #{total}"
      final_aria_label = aria_label || default_aria_label

      capture do
        concat(content_tag(:div, "",
                           class: PROGRESS_CONTAINER,
                           role: "progressbar",
                           aria: {
                             valuenow: progress_percent,
                             valuemin: 0,
                             valuemax: 100,
                             label: final_aria_label
                           }) do
          concat(content_tag(:div, "",
                             { class: PROGRESS_BAR,
                               style: "width: #{progress_percent}%",
                               aria: { hidden: true }
                             }
                 ))

          if progress_percent > 0 && progress_percent < 100
            concat(content_tag(:div, "",
                               class: PROGRESS_BAR_PULSE,
                               style: "width: #{progress_percent}%",
                               aria: { hidden: true }
                   ))
          end
        end)

        if start_label || end_label
          concat(content_tag(:div, class: LABELS_CONTAINER, aria: { hidden: true }) do
            concat(content_tag(:span, start_label || ""))
            concat(content_tag(:span, end_label || ""))
          end)
        end
      end
    end

    # Shared progress status rendering with ARIA live region
    def render_progress_status(content = nil, &block)
      content = capture(&block) if block_given?

      content_tag(:div, content,
                  role: "status",
                  aria: { live: "polite", atomic: true },
                  class: "mt-2"
      )
    end

    def progress_count_of(completed, total, label)
      # Assuming SUBTITLE_EMPHASIS is needed, but we don't have access to UiProgressBoxHelper constants directly here easily
      # without mixing concerns or moving constants.
      # Let's just use the classes directly since we are trying to be DRY and consistent.
      emphasis_class = "font-medium text-stone-emphasis"

      safe_join([
                  content_tag(:span, completed, class: emphasis_class),
                  " of ",
                  content_tag(:span, total, class: emphasis_class),
                  " #{label}"
                ])
    end
  end
end
