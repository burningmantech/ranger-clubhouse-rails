# frozen_string_literal: true

module UiComponents
  module UiProgressBoxHelper
    include UiProgressCompletedBarHelper

    # The same surface and edge every other card in the app wears -- see
    # UiCardHelper::CARD_BASE and .box-default. The white/gray-800 pair it had
    # could not follow a theme, and gray-800 carried a blue cast the rest of
    # the dark surfaces do not have. It is still not card-standard: that is a
    # 12px radius and no shadow, and this box is 16px with shadow-sm. Whether
    # the difference was ever meant is still open -- U11 unified the cards, not
    # every base-100 panel with a border-line edge.
    SECTION_BASE = "mb-2 px-4 py-2 bg-base-100 rounded-xl border border-line shadow-sm"
    # The badge wears the same outline as the hero panel it sits under, so it
    # takes the same token. It had been spelled at /50 in both themes rather
    # than the signature's /40 and /30 -- a tenth of an alpha on a 1px ring,
    # copied rather than decided. The warm gradient underneath is still raw
    # palette: turning it into a theme-derived mix repaints the badge, which
    # is a separate, visible decision.
    ICON_BADGE_BASE = "flex items-center justify-center w-10 h-10 rounded-full bg-linear-to-br from-amber-100 to-orange-100 dark:from-amber-900/40 dark:to-orange-900/40 ring-1 ring-signature-edge"
    ICON_COLOR = "icon-warning"
    TITLE_CLASS = "heading-section text-heading"
    SUBTITLE_CLASS = "text-sm text-stone-subtle"
    SUBTITLE_EMPHASIS = "font-medium text-stone-emphasis"

    class ProgressBoxBuilder
      attr_reader :template, :id

      def initialize(template, id:)
        @template = template
        @id = id
        @title_opts = nil
        @title_block = nil
        @subtitle_content = nil
        @progress_content = nil
        @status_content = nil
      end

      def title(icon:, icon_style: :solid, &block)
        @title_opts = { icon: icon, icon_style: icon_style }
        @title_block = block
      end

      def subtitle(&block)
        @subtitle_content = template.capture(&block)
      end

      def progress(completed:, total:, start_label: nil, end_label: nil, aria_label: nil)
        @progress_content = template.render_progress_bar(
          completed: completed,
          total: total,
          start_label: start_label,
          end_label: end_label,
          aria_label: aria_label
        )
      end

      def status(&block)
        @status_content = template.render_progress_status(&block)
      end

      def render
        template.content_tag(:section,
                             class: UiProgressBoxHelper::SECTION_BASE,
                             aria: { labelledby: "#{id}-heading" }
        ) do
          template.concat(template.content_tag(:div, class: "flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3 mb-2") do
            template.concat(build_header)
            template.concat(@status_content) if @status_content
          end)

          template.concat(@progress_content) if @progress_content
        end
      end

      private

      def build_header
        return "" unless @title_opts && @title_block

        title_text = template.capture(&@title_block)

        template.content_tag(:div, class: "flex items-center gap-3") do
          template.concat(template.content_tag(:div, class: UiProgressBoxHelper::ICON_BADGE_BASE, aria: { hidden: true }) do
            template.content_tag(:span, template.fa_icon(@title_opts[:icon], @title_opts[:icon_style]), class: UiProgressBoxHelper::ICON_COLOR)
          end)

          template.concat(template.content_tag(:div) do
            template.concat(template.content_tag(:h2, title_text, id: "#{id}-heading", class: UiProgressBoxHelper::TITLE_CLASS))
            template.concat(template.content_tag(:p, @subtitle_content, class: UiProgressBoxHelper::SUBTITLE_CLASS)) if @subtitle_content
          end)
        end
      end
    end

    def ui_progress_box(id: nil, &block)
      builder = ProgressBoxBuilder.new(self, id: id || "progress-box-#{SecureRandom.hex(4)}")
      capture(builder, &block)
      builder.render
    end
  end
end
