# frozen_string_literal: true

module UiComponents
  module UiHeroPanelHelper
    include UiProgressBarHelper

    class HeroPanelBuilder
      # CSS class constants for maintainability
      HEADING_CLASSES = {
        h1: "text-2xl font-semibold",
        h2: "text-xl font-semibold"
      }.freeze

      # The outlined tile, shared by every scheme that does not carry a hue of
      # its own: flame and award are drawn entirely in hero-panel.css. Whole
      # class names either side of the interpolation, so Tailwind still reads
      # each one as written.
      TILE_BASE = "rounded-lg px-3 py-2 ring-1 ring-signature-edge"
      LABEL_BASE = "tracking-wide text-base text-center"
      VALUE_BASE = "font-semibold text-base text-center"

      # No caller passes :warning or :pending today -- the two live stat badges
      # are :flame and :award -- but both are documented options, so they keep
      # their tint rather than being quietly dropped.
      AMBER_TILE = {
        tile: "#{TILE_BASE} bg-hero-tile",
        label: "#{LABEL_BASE} icon-warning",
        value: "#{VALUE_BASE} text-hero-tile-content"
      }.freeze

      STAT_BADGE_COLORS = {
        warning: AMBER_TILE,
        pending: AMBER_TILE,
        # Tenure, acknowledged in its own hue -- see components/hero-panel.css.
        flame: {
          tile: "hero-stat hero-stat-flame",
          label: "hero-stat-label",
          value: "hero-stat-value"
        },
        award: {
          tile: "hero-stat hero-stat-award",
          label: "hero-stat-label",
          value: "hero-stat-value"
        },
        default: {
          tile: "#{TILE_BASE} bg-base-100/70",
          label: "#{LABEL_BASE} text-stone-subtle",
          value: "#{VALUE_BASE} text-heading"
        }
      }.freeze

      attr_reader :template, :icon, :id, :heading_level, :heading_class, :back_to_link

      def initialize(template, icon:, id:, heading_level:)
        @template = template
        @icon = icon
        @id = id
        @heading_level = heading_level
        @heading_class = HEADING_CLASSES[heading_level]
        @title_content = nil
        @description_content = nil
        @stats_content = nil
        @progress_content = nil
        @progress_status_content = nil
        @year_selector_data = nil # Store year/years data for separate desktop/mobile rendering
        @back_to_link = nil
      end

      def title(options = {}, &block)
        @title_content = template.tag.span(template.fa_icon(icon, :solid, size: "lg"), class: "icon-warning") +
          template.tag.public_send(heading_level, template.capture(&block),
                                   id: id,
                                   class: "#{heading_class} text-heading #{options[:class]}")
      end

      def back_to(&block)
        @back_to_link = template.capture(&block)
      end

      def description(options = {}, &block)
        options[:class] = "leading-relaxed #{options[:class]}".squish
        @description_content = template.tag.div(template.capture(&block), **options)
      end

      def hero_stats(options = {}, &block)
        @stats_content = template.tag.div(
          template.capture(&block),
          class: options[:class] || "flex flex-wrap gap-3",
          role: options[:role] || "list",
          aria: { label: "#{template.strip_tags(id.to_s)} statistics" }
        )
      end

      # icon: optional FontAwesome name rendered beside the label. Decorative --
      # the tile is already read out as "<label> <value>" by the listitem role.
      def stat_badge(label, value, color: :default, icon: nil)
        colors = STAT_BADGE_COLORS[color]
        label_content = icon ? template.safe_join([template.fa_icon(icon, :solid), label], " ") : label

        template.tag.div(role: "listitem", class: colors[:tile]) do
          template.tag.div(label_content, class: colors[:label]) +
            template.tag.div(value, class: colors[:value])
        end
      end

      def progress(completed:, total:, start_label: nil, end_label: nil, aria_label: nil)
        @progress_content = template.tag.div(class: "mt-4") do
          template.render_progress_bar(completed:, total:, start_label:, end_label:, aria_label:)
        end
      end

      def progress_status(&block)
        @progress_status_content = template.render_progress_status(&block)
      end

      def year_selector(year:, years: nil, **options)
        @year_selector_data = { year: year, years: years }.merge(options.compact)
      end

      def render
        template.tag.div(class: "flex flex-col w-full") do
          safe_join([
                      render_mobile_back_link,
                      render_main_layout
                    ].compact)
        end
      end

      private

      def render_mobile_back_link
        return unless @back_to_link

        template.tag.div(@back_to_link, class: "mb-2 lg:hidden")
      end

      def render_main_layout
        # Desktop: Two-column layout when stats present, single column otherwise
        # Mobile: Always single column stack
        if @stats_content
          render_two_column_layout
        else
          render_single_column_layout
        end
      end

      # A back link keeps the title row spanning the panel, with the link on its
      # far right. Without one the title joins the left column, so the stats sit
      # beside the title and description.
      def render_two_column_layout
        title_row = render_title_row
        safe_join([
                    (title_row if @back_to_link),
                    template.tag.div(class: "flex flex-col lg:flex-row lg:gap-6 lg:items-start") do
                      # Left column: Title (no back link), description, year selector (mobile only), progress
                      template.tag.div(class: "flex-1 min-w-0") do
                        safe_join([
                                    (title_row unless @back_to_link),
                                    @description_content,
                                    render_mobile_year_selector,
                                    @progress_content,
                                    @progress_status_content,
                                    render_mobile_stats
                                  ].compact)
                      end +
                        # Right column: Stats (desktop only, stacks below on mobile)
                        template.tag.div(class: "hidden lg:block shrink-0") do
                          @stats_content
                        end
                    end
                  ].compact)
      end

      def render_single_column_layout
        safe_join([
                    render_title_row,
                    @description_content,
                    render_mobile_year_selector,
                    @progress_content,
                    @progress_status_content
                  ].compact)
      end

      # A title alone gets no bottom margin: the gap below it is for the
      # description or stats that follow, and without them it is dead space.
      def title_margin
        "mb-1" if @description_content || @stats_content
      end

      def render_title_row
        return unless @title_content

        title = template.tag.div(@title_content, class: ["flex items-center gap-2", title_margin])
        # Simple case: just title, no back link or year selector
        return title unless @back_to_link || @year_selector_data

        template.tag.div(class: ["flex justify-between items-center gap-6", title_margin]) do
          safe_join([
                      # Title on left
                      title,
                      # Year selector in middle (desktop only, compact)
                      render_desktop_year_selector,
                      # Back link on far right (desktop only)
                      @back_to_link ? template.tag.div(@back_to_link, class: "hidden lg:block shrink-0") : nil
                    ].compact)
        end
      end

      def render_mobile_stats
        return unless @stats_content

        template.tag.div(@stats_content, class: "lg:hidden mt-4")
      end

      def render_desktop_year_selector
        return unless @year_selector_data

        options = @year_selector_data.except(:year).compact
        template.tag.div(class: "hidden lg:block shrink-0") do
          template.year_selector_compact(@year_selector_data[:year], options)
        end
      end

      def render_mobile_year_selector
        return unless @year_selector_data

        options = @year_selector_data.except(:year).compact
        template.tag.div(class: "lg:hidden mt-4") do
          template.year_selector(@year_selector_data[:year], options)
        end
      end

      def safe_join(array)
        template.safe_join(array)
      end
    end

    # Simple panels can pass title/description as strings and back_to as
    # :dashboard, a [label, path] pair, or an already-rendered link; the
    # block and its slots remain for anything richer (stats, progress,
    # year selector).
    def hero_panel(icon:, id: nil, heading_level: :h2, title: nil, description: nil, back_to: nil, &block)
      id ||= "hero-panel-#{SecureRandom.hex(4)}"

      content_tag :section, class: "me-hero-panel", aria: { labelledby: id } do
        builder = HeroPanelBuilder.new(self, icon:, id:, heading_level:)
        builder.title { title } if title
        builder.description { description } if description
        if back_to == :dashboard
          builder.back_to { back_to_dashboard }
        elsif back_to.is_a?(Array)
          label, url = *back_to
          builder.back_to { back_to(label, url) }
        elsif back_to
          builder.back_to { back_to }
        end
        capture(builder, &block) if block
        builder.render
      end
    end
  end
end
