# frozen_string_literal: true

module UiComponents
  # One row of an index that drills down into a detail page: a full-width
  # clickable box with a headline on the left and a chevron on the right.
  #
  #   ui_drill_down_row scheduling_slots_position_path(position), position.title,
  #                     meta: pluralize(count, "slot")
  #
  # The headline reads "Title • meta • badge", each segment optional. Pass
  # badges already rendered so each caller keeps its own variant and icon; give
  # them size: "base" so they sit correctly in the text-lg headline. A block adds
  # a second line below the headline (a reason the row is unavailable, say).
  #
  # blocked: true renders a row that cannot be followed — use the block to say
  # why. Note this is the only way to make one: `disabled` on an <a> is inert.
  module UiDrillDownRowHelper
    ROW_BASE = "no-decoration box box-default px-4 py-2 my-2 " \
               "flex justify-between items-center"
    ROW_FOLLOWABLE = "box-hover"
    ROW_BLOCKED = "opacity-70 cursor-not-allowed"
    HEADLINE_BASE = "text-lg font-semibold"
    META_BASE = "text-stone-subtle"
    SEPARATOR_BASE = "my-1"
    CHEVRON_BASE = "text-xl"

    def ui_drill_down_row(url, title, options = {}, &block)
      raise ArgumentError, "ui_drill_down_row requires a title" if title.blank?

      options = options.dup
      meta = options.delete(:meta)
      badges = Array.wrap(options.delete(:badges))
      blocked = options.delete(:blocked)
      icon = options.delete(:icon) || (blocked ? "ban" : "arrow-right")
      options[:class] = class_names(ROW_BASE, blocked ? ROW_BLOCKED : ROW_FOLLOWABLE, options.delete(:class))

      body = safe_join([
                         tag.div(safe_join([drill_down_headline(title, meta, badges),
                                            (capture(&block) if block)].compact)),
                         tag.div(fa_icon(icon, :solid), class: CHEVRON_BASE)
                       ])

      # A row that goes nowhere is not a link. Rendering a div keeps it off the
      # pointer and out of the tab order, which `disabled` on an <a> never did:
      # that attribute is inert, leaving the row clickable and focusable.
      if blocked
        options[:aria] = (options[:aria] || {}).merge(disabled: true)
        return tag.div(body, **options)
      end

      link_to(url, options) { body }
    end

    private

    def drill_down_headline(title, meta, badges)
      parts = [title]
      parts.push(drill_down_separator, tag.span(meta, class: META_BASE)) if meta.present?
      badges.compact.each { |badge| parts.push(drill_down_separator, badge) }

      # Joined with a space: these are inline spans, and without it the bullet
      # separators butt against the text on either side.
      tag.div(safe_join(parts, " "), class: HEADLINE_BASE)
    end

    def drill_down_separator
      tag.span("•", class: SEPARATOR_BASE)
    end
  end
end
