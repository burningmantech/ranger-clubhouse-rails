# frozen_string_literal: true

module UiComponents
  # Accent Card Helper
  # Creates a card with a prominent left border for visual hierarchy
  # Used for dashboard steps, qualifications, schedule items, etc.
  #
  # Usage:
  #   <%= ui_accent_card "Task Title", variant: :success, icon: "check", badge: badge_html do %>
  #     Card content here
  #   <% end %>
  #
  module UiAccentCardHelper
    include ActionView::Helpers::TagHelper
    include ActionView::Context

    # Border color classes for each variant
    BORDER_VARIANTS = {
      error: "border-error/30",
      info: "border-info",
      primary: "border-primary/30",
      secondary: "border-base-300",
      success: "border-success/30",
      warning: "border-warning/30"
    }.freeze

    # Background color classes for each variant
    BG_VARIANTS = {
      error: "bg-error/10",
      info: "bg-info/10",
      primary: "bg-primary/10",
      secondary: "bg-base-200",
      success: "bg-success/10",
      warning: "bg-warning/10"
    }.freeze

    # Heading levels a title can take. Never :h1 -- the page title is the hero's.
    HEADING_LEVELS = %i[h2 h3 h4].freeze

    # A title takes its level's size, so a card inside a ui_section never outweighs the
    # section's own title: :h2 matches it, everything else (h3, h4, the div) is body size.
    TITLE_STYLES = { h2: "heading-section" }.freeze

    # Renders an accent card with left border
    #
    # @param title [String] Card title (optional)
    # @param variant [Symbol] Color variant (:success, :warning, :error, :info, :primary, :secondary)
    # @param icon [String, nil] FontAwesome icon name (optional)
    # @param icon_type [Symbol] Icon type (:solid, :regular) - default :solid
    # @param badge [String, nil] Badge HTML to display (optional)
    # @param heading_level [Symbol, nil] Renders the title as this heading (:h2, :h3 or :h4)
    #   instead of a div; :h3 and :h4 look the same as the div, :h2 is a step larger at lg
    #   (TITLE_STYLES). Use it when the title labels the card's content,
    #   one level below the nearest heading; leave it off for a notice, tip or banner.
    # @param options [Hash] Additional HTML options
    #   - :id - HTML id attribute
    #   - :class - Additional CSS classes
    #   - :aria - ARIA attributes hash
    #   - :data - Data attributes hash
    # @yield Content block for card body
    #
    def ui_accent_card(title = nil, variant: :primary, icon: nil, icon_type: :solid, badge: nil,
                       heading_level: nil, options: {}, &block)
      if heading_level && HEADING_LEVELS.exclude?(heading_level)
        raise ArgumentError, "ui_accent_card unknown heading_level: #{heading_level.inspect}"
      end

      variant = variant.to_sym
      border_class = BORDER_VARIANTS[variant] || BORDER_VARIANTS[:primary]
      bg_class = BG_VARIANTS[variant] || BG_VARIANTS[:primary]

      # Build card classes
      card_classes = [
        "rounded-lg",
        "border-l-4",
        border_class,
        bg_class,
        "px-4 py-2",
        "transition-all",
        "duration-200",
        "hover:shadow-sm",
        options[:class]
      ].compact.join(" ")

      # Build HTML options
      html_options = {
        class: card_classes
      }
      html_options[:id] = options[:id] if options[:id]
      html_options[:aria] = options[:aria] if options[:aria]
      html_options[:data] = options[:data] if options[:data]

      # Use article tag for semantic HTML
      content_tag(:article, html_options) do
        safe_join([
          render_card_header(title, icon, icon_type, badge, heading_level),
          render_card_body(&block)
        ].compact)
      end
    end

    private

    def render_card_header(title, icon, icon_type, badge, heading_level)
      return nil unless title || badge

      content_tag(:div, class: "flex flex-col lg:flex-row lg:items-center gap-2") do
        safe_join([
          render_title_with_icon(title, icon, icon_type, heading_level),
          render_badge(badge)
        ].compact)
      end
    end

    def render_title_with_icon(title, icon, icon_type, heading_level)
      return nil unless title

      title_style = TITLE_STYLES.fetch(heading_level, "heading-title")
      content_tag(heading_level || :div, class: "flex-1 #{title_style} flex items-center gap-2 text-heading") do
        if icon
          safe_join([
            content_tag(:span, fa_icon(icon, icon_type), class: "shrink-0"),
            content_tag(:span, title)
          ])
        else
          title
        end
      end
    end

    def render_badge(badge)
      return nil unless badge

      content_tag(:div, badge.html_safe, class: "shrink-0")
    end

    def render_card_body(&block)
      return nil unless block_given?

      content_tag(:div, capture(&block), class: "mt-2")
    end
  end
end
