# frozen_string_literal: true

module UiComponents
  # DaisyUI Progress Bar Helper
  # See: https://daisyui.com/components/progress/
  module UiProgressBarHelper
    PROGRESS_CONTAINER_BASE = "w-full bg-base-300 rounded-full"
    PROGRESS_BAR_BASE = "rounded-full flex items-center justify-end overflow-hidden"

    # Size classes for height
    SIZE_CLASSES = {
      sm: "h-1.5",
      md: "h-2.5",
      lg: "h-4.5",
      xl: "h-6"
    }.freeze

    # Color variant classes
    VARIANT_BG_CLASSES = {
      primary: "bg-primary",
      secondary: "bg-secondary",
      success: "bg-success",
      error: "bg-error",
      warning: "bg-warning"
    }.freeze

    # Color variant classes
    VARIANT_FG_CLASSES = {
      primary: "text-primary-content",
      secondary: "text-secondary-content",
      success: "text-success-content",
      error: "text-error-content",
      warning: "text-warning-content"
    }.freeze

    # Options:
    #   :size - size of the progress bar (:sm, :md, :lg, :xl) - default: :md (or :lg if label is present)
    #   :variant - color variant (:primary, :secondary, :success, :error, :warning) - default: :primary
    #   :label - text to display inside the bar. If true, displays the percentage. It sits inside
    #            the fill and is clipped when the fill is narrower than the text.
    #   :bar_class - additional CSS classes for the bar itself; "progress-projected" stripes it
    #                as an estimate, not yet earned (components/progress.css)
    #   :aria - hash of ARIA attributes (e.g. { label: "Downloading" })
    #   Other options are passed to the container div.
    #
    # Usage:
    #   ui_progress_bar(50)
    #   ui_progress_bar(50, :success)
    #   ui_progress_bar(50, :warning, label: "Loading…")
    #   ui_progress_bar(50, variant: :error, size: :lg)
    #   ui_progress_bar(65, bar_class: "progress-projected")
    def ui_progress_bar(percentage, variant_or_options = {}, options = {})
      if variant_or_options.is_a?(Symbol)
        variant = variant_or_options
        options = options.dup
      else
        variant = nil
        options = variant_or_options.is_a?(Hash) ? variant_or_options.dup : {}
      end

      percentage = percentage.to_i.clamp(0, 100)

      label = options.delete(:label)
      # Default size to :lg if label is present, otherwise :md
      default_size = label ? :lg : :md
      size = options.delete(:size) || default_size

      variant ||= options.delete(:variant) || :primary
      aria_options = options.delete(:aria) || {}
      bar_custom_class = options.delete(:bar_class)
      container_custom_class = options.delete(:class)

      # Determine height class
      height_class = SIZE_CLASSES[size.to_sym] || SIZE_CLASSES[default_size]

      # Prepare container classes
      container_classes = "#{PROGRESS_CONTAINER_BASE} #{height_class} #{container_custom_class}".squish

      # Prepare bar classes
      variant_class = VARIANT_BG_CLASSES[variant.to_sym] || VARIANT_BG_CLASSES[:primary]
      bar_classes = "#{PROGRESS_BAR_BASE} #{height_class} #{variant_class} #{bar_custom_class}".squish

      # Label text styles
      label_text = nil
      if label
        label_text = (label == true) ? "#{percentage}%" : label
      end

      # ARIA attributes. role is NOT one of them: Rails prefixes every key in an
      # aria: hash with "aria-", and aria-role is not an attribute, so leaving
      # it here emitted a bar with no progressbar semantics -- which in turn
      # made aria-label unnameable (role=generic prohibits an author name) and
      # aria-valuenow/min/max inert. It is passed as its own attribute below.
      default_aria = {
        valuenow: percentage,
        valuemin: 0,
        valuemax: 100,
        label: (label.is_a?(String) ? label : "#{percentage}%")
      }
      aria_attributes = default_aria.merge(aria_options.except(:role))

      label_class = VARIANT_FG_CLASSES[variant.to_sym] || VARIANT_FG_CLASSES[:primary]
      label_html = label_text ? content_tag(:span, label_text, class: "text-xs #{label_class} font-medium leading-none pe-2") : nil

      content_tag :div, options.merge(class: container_classes) do
        content_tag(:div, label_html, class: bar_classes, style: "width: #{percentage}%",
                                      role: "progressbar", aria: aria_attributes)
      end
    end
  end
end
