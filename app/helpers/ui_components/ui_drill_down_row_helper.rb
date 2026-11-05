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
  # figures: [[count, label], ...] sets a count that splits as a ledger beside
  # the headline instead of a meta segment: the numerals right-align in a fixed
  # cell so they line up down the list, and a zero recedes so the eye lands on
  # what is still owed. Counts are Integers, labels present, and meta: cannot
  # come along -- one count belongs in the headline.
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
    # The ledger sits beside the headline and drops under it only when the two
    # no longer fit on one line: a wrapping flex row, no breakpoint. The
    # headline keeps a 16rem floor and the figures never shrink.
    LEDGER_ROW = "flex flex-wrap flex-1 min-w-0 items-baseline gap-x-5 pe-5"
    HEADLINE_BESIDE_LEDGER = "grow basis-64 min-w-0"
    LEDGER = "flex shrink-0 items-baseline gap-5 tabular-nums"
    FIGURE_BASE = "inline-flex items-baseline gap-1.5 whitespace-nowrap"
    NUMERAL_BASE = "min-w-9 text-right text-lg"
    NUMERAL_ZERO = "text-stone-subtle"
    FIGURE_LABEL = "text-sm text-stone-subtle"
    CHEVRON_BASE = "text-xl"

    def ui_drill_down_row(url, title, options = {}, &block)
      raise ArgumentError, "ui_drill_down_row requires a title" if title.blank?

      options = options.dup
      meta = options.delete(:meta)
      badges = Array.wrap(options.delete(:badges))
      figures = Array.wrap(options.delete(:figures)).compact
      unless figures.all? { |count, label| count.is_a?(Integer) && label.present? }
        raise ArgumentError, "ui_drill_down_row figures: takes [[count, label], ...] with Integer counts"
      end
      raise ArgumentError, "ui_drill_down_row takes meta: or figures:, not both" if meta.present? && figures.any?

      blocked = options.delete(:blocked)
      icon = options.delete(:icon) || (blocked ? "ban" : "arrow-right")
      options[:class] = class_names(ROW_BASE, blocked ? ROW_BLOCKED : ROW_FOLLOWABLE, options.delete(:class))

      headline = tag.div(safe_join([drill_down_headline(title, meta, badges),
                                    (capture(&block) if block)].compact),
                         class: (HEADLINE_BESIDE_LEDGER if figures.any?))
      headline = tag.div(safe_join([headline, drill_down_figures(figures)]), class: LEDGER_ROW) if figures.any?
      body = safe_join([headline, tag.div(fa_icon(icon, :solid), class: CHEVRON_BASE)])

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

    # Joined with spaces for the same reason as the headline: the spans are
    # inline, and "0 upcoming 3 past" is what a screen reader should hear.
    def drill_down_figures(figures)
      tag.div(class: LEDGER) do
        safe_join(figures.map do |count, label|
          numeral = tag.span(count, class: class_names(NUMERAL_BASE, count.zero? ? NUMERAL_ZERO : "font-semibold"))
          tag.span(safe_join([numeral, tag.span(label, class: FIGURE_LABEL)], " "), class: FIGURE_BASE)
        end, " ")
      end
    end
  end
end
