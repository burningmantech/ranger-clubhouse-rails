# frozen_string_literal: true

module UiComponents
  # Stat Box Helper
  # Creates a metric display card with icon, value, and label
  # Used for dashboard stats, summary metrics, etc.
  #
  # Usage:
  #   <%= ui_stat_box "95%", "Complete", variant: :success, icon: "check" %>
  #
  module UiStatBoxHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    # Background and border variants for stat boxes
    STAT_VARIANTS = {
      success: { bg: "bg-success/10", border: "border-success/30", text: "text-success", icon: "icon-success" },
      warning: { bg: "bg-warning/10", border: "border-warning/30", text: "text-warning", icon: "icon-warning" },
      error: { bg: "bg-error/10", border: "border-error/30", text: "text-error", icon: "icon-error" },
      secondary: { bg: "bg-base-100", border: "border-line", text: "text-heading", icon: "text-stone-icon" }
    }.freeze

    # Size variants
    STAT_SIZES = {
      sm: { value: "text-lg", label: "text-xs", icon: "text-base" },
      md: { value: "text-xl", label: "text-sm", icon: "text-xl" },
      lg: { value: "text-2xl", label: "text-base", icon: "text-2xl" }
    }.freeze

    # A stat box that is also a link (ui_stat_link)
    STAT_LINK_BASE = "no-decoration block rounded-lg focus-visible:outline-none " \
                     "focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
    STAT_LINK_ACTIVE = "ring-2 ring-primary"

    # Renders a stat display box
    #
    # @param value [String] The main value to display
    # @param label [String] The label text
    # @param variant [Symbol] Color variant (:success, :warning, :error, :secondary)
    # @param icon [String, nil] FontAwesome icon name (optional)
    # @param icon_type [Symbol] Icon type (:solid, :regular) - default :solid
    # @param size [Symbol] Size variant (:sm, :md, :lg) - default :md
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    #   - :aria - ARIA attributes hash
    #
    def ui_stat_box(value, label, variant: :secondary, icon: nil, icon_type: :solid, size: :md, **options)
      variant = variant.to_sym
      size = size.to_sym

      variant_classes = STAT_VARIANTS[variant] || STAT_VARIANTS[:secondary]
      size_classes = STAT_SIZES[size] || STAT_SIZES[:md]

      # Build container classes
      container_classes = [
        variant_classes[:bg],
        "border",
        variant_classes[:border],
        "rounded-lg",
        "p-3",
        "text-center",
        options[:class]
      ].compact.join(" ")


      # Build HTML options
      html_options = { class: container_classes }
      html_options[:aria] = options[:aria] if options[:aria]

      content_tag(:div, html_options) do
        safe_join([
          render_stat_icon(icon, icon_type, variant_classes[:icon], size_classes[:icon]),
          render_stat_value(value, variant_classes[:text], size_classes[:value]),
          render_stat_label(label, variant_classes[:text], size_classes[:label])
        ].compact)
      end
    end

    # Renders a stat box as a link, for a tile that filters or drills into what
    # it counts. The block is the ui_stat_box.
    #
    #   <%= ui_stat_link swag_distribution_url(category: "shirt"),
    #                    aria_label: "12 shirts — show recipients" do %>
    #     <%= ui_stat_box "12", "Shirts" %>
    #   <% end %>
    #
    # no-decoration keeps the global link underline from running through the
    # count and the label. It takes the link style's focus outline with it, so
    # the focus ring stands in for that.
    #
    # @param url [String] Where the tile leads
    # @param aria_label [String] The link's name. It replaces the box's own text
    #   for a screen reader, so it has to carry the count.
    # @param active [Boolean] Rings the tile whose filter is showing. That ring
    #   has no offset and the focus ring does, so the two read apart.
    # @param options [Hash] Additional HTML options
    #   - :class - Additional CSS classes
    #
    def ui_stat_link(url, aria_label:, active: false, **options, &block)
      link_to url, class: class_names(STAT_LINK_BASE, options[:class], STAT_LINK_ACTIVE => active),
                   aria: { label: aria_label }, &block
    end

    private

    def render_stat_icon(icon, icon_type, icon_class, size_class)
      return nil unless icon

      content_tag(:div, class: "#{size_class} #{icon_class} mb-1") do
        fa_icon(icon, icon_type, aria: { hidden: true })
      end
    end

    def render_stat_value(value, text_class, size_class)
      content_tag(:div, value, class: "#{size_class} font-bold #{text_class}")
    end

    def render_stat_label(label, text_class, size_class)
      content_tag(:div, label, class: "#{size_class} #{text_class}")
    end
  end
end
