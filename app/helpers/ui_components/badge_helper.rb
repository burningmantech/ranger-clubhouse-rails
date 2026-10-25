# frozen_string_literal: true

# DaisyUI Badge Helper
# See: https://daisyui.com/components/badge/
#
module UiComponents
  module BadgeHelper
    # Base badge class
    BADGE_BASE = "badge"

    # Map variant symbols to DaisyUI class names
    BADGE_VARIANTS = {
      primary: "badge-primary badge-soft",
      secondary: "badge-secondary badge-soft",
      error: "badge-error badge-soft",
      success: "badge-success badge-soft",
      warning: "badge-warning badge-soft"
    }.freeze

    # Whole class names, never "text-#{size}": Tailwind only compiles a class it
    # can read as written.
    BADGE_SIZES = { "xs" => "text-xs", "sm" => "text-sm", "base" => "text-base" }.freeze

    # The tints icons.css defines. A primary or secondary badge's icon has none
    # and takes the badge's own colour.
    BADGE_ICON_TINTS = { success: "icon-success", warning: "icon-warning", error: "icon-error",
                         info: "icon-info" }.freeze

    def ui_badge(*args, **options, &block)
      # Parse arguments based on calling convention
      if block_given?
        # Block form: ui_badge(:variant, options) { block }
        raise ArgumentError, "ui_badge with block expects 1 argument (variant), got #{args.size}" unless args.size == 1
        variant = args.first
        text = nil # Will be captured from block later
      else
        # Standard form: ui_badge(title, :variant, options)
        raise ArgumentError, "ui_badge expects 2 arguments (text, variant), got #{args.size}" unless args.size == 2
        text, variant = args
      end

      icon = options.delete(:icon)
      icon_type = options.delete(:icon_type) || :solid

      variant_class = BADGE_VARIANTS[variant.to_sym] || BADGE_VARIANTS[:secondary]
      size_class = BADGE_SIZES.fetch((options.delete(:size) || "xs").to_s)
      options[:class] = "#{options[:class]} #{BADGE_BASE} #{variant_class} #{size_class}".squish

      # Add inline-flex items-center gap-1.5 when icon is present
      if icon
        options[:class] = "#{options[:class]} inline-flex items-center gap-2".squish
      end

      context = @template || self

      # Capture block content if block was given
      text = context.capture(&block) if block_given?

      content = if icon
        icon_class = BADGE_ICON_TINTS.fetch(variant.to_sym, nil)
        context.safe_join([
          context.fa_icon(icon, icon_type, class: icon_class),
          text
        ])
                else
        text
                end

      context.content_tag(:span, content, options)
    end
  end
end
