# frozen_string_literal: true

# Provides helpers for rendering DaisyUI-styled HTML tables. By default
# (`responsive: true`) the helper applies a `.responsive-table` class so that
# below the lg-equivalent breakpoint each row collapses into a labeled card
# (driven by `data-label` attributes), while desktop keeps the native
# `<table>` layout so columns auto-size to their widest content.
# `responsive: false` keeps a plain table at every width.
# See: https://daisyui.com/components/table/
module TableHelper
  CONTAINER_CLASSES = "table-container"
  TABLE_BASE = "text-body"
  HEADER_CLASSES = "table-header"
  # A header that stays put while the rows scroll, for `t.header class:` on a
  # table whose container_class bounds its height and scrolls it (People Search,
  # Salesforce Query): a sticky thead pins to the nearest scrolling ancestor, so
  # the pane is what it sticks to. Both are lg-only because below the fold a responsive table is
  # labeled cards, and a nested scrollport on a phone is worse than the page's
  # own. Heading cells paint their own background -- a th is transparent, and
  # rows scrolling under a pinned header show straight through it.
  PINNED_HEADER_CLASSES = "lg:sticky lg:top-0 lg:z-20 [&_th]:bg-base-200"
  ROW_BASE = "table-row-base table-row-hover"
  ROW_STRIPED = "table-row-striped table-row-hover"
  HEADING_CLASSES = "table-heading"
  ROW_HEADER_CLASSES = "table-row-header"
  CELL_CLASSES = "table-cell-td"
  RESPONSIVE_TABLE_CLASS = "responsive-table"
  # Whole class names for size: and a row's align:, so Tailwind can read each one.
  TEXT_SIZES = { "sm" => "text-sm", "base" => "text-base" }.freeze
  ROW_ALIGNMENTS = { top: "align-top", middle: "align-middle" }.freeze

  # A detail row starts closed. Plain `hidden` is enough because tables.css
  # raises the specificity of `.responsive-table tr.hidden` above the
  # `display: block` its stacked-card layout sets -- toggle_controller adds and
  # removes `hidden!` alongside `hidden`, but nothing here has to.
  DETAIL_ROW_CLASSES = "table-detail-row hidden"
  DETAIL_CELL_CLASSES = "table-detail-cell"

  # Row states that are not severities, so they do not belong in
  # SeverityStyleHelper -- that table pairs a tint with the matching emphasis
  # for the figure that earned it, and neither of these has a figure.
  #
  # :success is deliberately not there for a second reason. Pages that grade
  # coverage call a well-covered row :success meaning "nothing to point at",
  # and putting it in the shared severity table would tint every healthy row
  # green. Here the word means what a post-action table means by it: this row
  # is the one the request just finished with. A page whose :success means
  # "fine" has to stop before `state:` -- see Scheduling::ShiftSignupsHelper.
  #
  # base-300 for a total because base-200 is already the stripe colour, and a
  # sum tinted the same as every even row is not marked at all. The "!" is
  # load-bearing throughout for the reason SeverityStyleHelper gives:
  # `odd:`/`even:` is :nth-child and outranks a plain background utility.
  ROW_STATES = {
    success: "!bg-success/10",
    total: "!bg-base-300 font-semibold"
  }.freeze

  # Renders a DaisyUI-styled table.
  #
  # @param full_width [Boolean] whether the table should span full width (default: false)
  # @param striped [Boolean] whether to use alternating row backgrounds (default: true)
  # @param container_class [String, nil] extra classes for the scroll container
  #   itself, not the <table>. The container is the table's scrollport, so a
  #   page that bounds its height or pins its header has to reach it -- and
  #   without this it would have to reach in past the component with a
  #   descendant selector.
  # @param responsive [Boolean] when true (the default), adds `.responsive-table`
  #   so the table collapses to labeled mobile cards below the lg breakpoint
  #   while preserving native `<table>` auto-sizing on desktop. Cell `data-label`
  #   attributes are auto-derived from the heading text and surfaced via CSS
  #   `::before`. Pass false for a grid read sideways, or a print sheet.
  # @param caption [String, nil] screen-reader caption for the table
  # @param options [Hash] additional HTML attributes for the table element
  # @yield [UiTableBuilder] builder object for constructing table structure
  #
  # @example Basic table, folding into labeled cards below lg
  #   <%= ui_table do |t| %>
  #     <%= t.header do %>
  #       <%= t.heading "Name" %>
  #       <%= t.heading "Value", right: true %>
  #     <% end %>
  #     <%= t.body do %>
  #       <%= t.row do %>
  #         <%= t.cell "Item" %>
  #         <%= t.cell "100", right: true %>
  #       <% end %>
  #     <% end %>
  #   <% end %>
  #
  # @example Plain table at every width
  #   <%= ui_table responsive: false, striped: true do |t| %>
  #     <%= t.header do %>
  #       <%= t.heading "Type" %>
  #       <%= t.heading "Actions", width: "1%" %>
  #     <% end %>
  #     ...
  #   <% end %>
  def ui_table(
    *legacy_args,
    full_width: false,
    striped: true,
    responsive: true,
    caption: nil,
    container_class: nil,
    size: "base",
    **options,
    &block
  )
    raise ArgumentError, "ui_table requires a block" unless block

    full_width, striped, responsive, caption, container_class, options = table_options(
      legacy_args,
      {
        full_width:,
        striped:,
        responsive:,
        caption:,
        container_class:,
        options:
      }
    )

    render_table(
      full_width:,
      striped:,
      responsive:,
      caption:,
      container_class:,
      options:,
      size:,
      &block
    )
  end

  # Renders table rows on their own, with no surrounding <table> -- for
  # turbo_stream replacements that swap a single <tr> inside a table already on
  # the page.
  #
  # headings must be the live table's heading labels, in order, because the
  # responsive mobile `data-label` attributes are matched to them by cell
  # index. Render the row through a shared partial so the page and the stream
  # cannot drift.
  #
  # @param headings [Array<String>] the table's heading labels, in column order
  # @param striped [Boolean] must match the table's own striped setting
  # @param responsive [Boolean] must match the table's own responsive setting (default: true)
  # @yield [UiTableBuilder] builder yielding t.row / t.cell as inside ui_table
  def ui_table_rows(headings:, striped: true, responsive: true, &block)
    raise ArgumentError, "ui_table_rows requires a block" unless block

    capture(UiTableBuilder.new(self, striped:, responsive:, headings:), &block)
  end

  private

  def table_options(legacy_args, defaults)
    option_keys = %i[full_width striped responsive caption container_class]
    legacy_options = legacy_table_options(legacy_args)
    helper_options = defaults.merge(legacy_options.slice(*option_keys))
    html_options = legacy_options.except(*option_keys).merge(defaults[:options])

    [*helper_options.values_at(*option_keys), html_options]
  end

  # table-layout: auto, so the browser sizes each column to its widest content.
  def table_layout_class(size:)
    "#{TEXT_SIZES.fetch(size.to_s)} table-auto"
  end

  def legacy_table_options(legacy_args)
    if legacy_args.length > 1
      raise ArgumentError, "ui_table accepts at most one positional options hash"
    end

    legacy_options = legacy_args.first
    return {} if legacy_options.nil?

    unless legacy_options.is_a?(Hash)
      raise ArgumentError, "ui_table positional argument must be an options hash"
    end

    legacy_options.dup
  end

  def render_table(full_width:, striped:, responsive:, caption:, options:, size:, container_class: nil, &block)
    # max-w-full: a fit-width box grows to its content's narrowest layout, so an
    # address or a nowrap cell wider than a phone pushed the whole page
    # sideways. Capped, the container's own overflow-x-auto scrolls instead.
    container_width = full_width ? "w-full" : "w-fit max-w-full"
    container_classes = class_names(CONTAINER_CLASSES, container_width, container_class)
    table_classes = class_names(
      TABLE_BASE,
      table_layout_class(size:),
      ("w-full" if full_width),
      (RESPONSIVE_TABLE_CLASS if responsive),
      options[:class]
    )

    builder = UiTableBuilder.new(self, striped:, responsive:)

    tag.div(class: container_classes) do
      tag.table(**options.merge(class: table_classes)) do
        safe_join(
          [
            (tag.caption(caption, class: "sr-only") if caption.present?),
            capture(builder, &block)
          ].compact
        )
      end
    end
  end

  # Builder class for constructing table structure.
  # Provides methods for header, body, rows, and cells.
  class UiTableBuilder
    attr_reader :template, :striped, :responsive

    # headings is normally collected by #header; ui_table_rows passes them in
    # because a standalone row has no thead to learn them from.
    def initialize(template, striped: false, responsive: false, headings: [])
      @template = template
      @striped = striped
      @responsive = responsive
      @headings = headings.map { |heading| mobile_label(heading) }
      @cell_index = 0
      @capturing_header = false
    end

    # Renders the table header section (thead).
    #
    # @param options [Hash] additional HTML attributes for the thead element
    # @yield block containing heading cells
    def header(**options, &block)
      @capturing_header = true
      options[:class] = class_names(HEADER_CLASSES, options[:class])

      template.tag.thead(**options) do
        template.tag.tr do
          template.capture(self, &block)
        end
      end
    ensure
      @capturing_header = false
    end

    # Renders a header cell (th in thead).
    #
    # @param value [String, nil] the cell content (ignored if block given)
    # @param right [Boolean] right-align the content
    # @param center [Boolean] center-align the content
    # @param width [String, nil] explicit column width (e.g. "200px", "1%")
    # @param options [Hash] additional HTML attributes
    # @yield optional block for complex cell content
    def heading(value = nil, right: false, center: false, width: nil, **options, &block)
      align_class = alignment_class(right:, center:)
      content = block_given? ? template.capture(&block) : normalize_value(value)

      record_heading_label(content) if @capturing_header

      options[:class] = class_names(HEADING_CLASSES, align_class, options[:class])
      append_style(options, "width: #{width}") if width.present?

      template.tag.th(**options.merge(scope: "col")) { content }
    end

    # Renders the table body section (tbody).
    #
    # @param options [Hash] additional HTML attributes for the tbody element
    # @yield block containing row elements
    def body(**options, &block)
      template.tag.tbody(**options) do
        template.capture(self, &block)
      end
    end

    # Renders a table row (tr in tbody).
    #
    # Cells top-align by default (tables.css sets it on the tbody), so
    # `align: :top` is redundant -- pass `:middle` or `:bottom` only to opt a
    # row out, which is worth doing when a row's tallest cell is a control that
    # centres its own label inside the 36px touch floor.
    #
    # `state:` is how a row says what it is. Before it existed every report
    # spelled its own tint, and eleven of them had arrived at four different
    # spellings of two meanings -- `!bg-error/10`, a bare `bg-error/10` that
    # only survives because its table happens not to be striped, a page-local
    # helper, and a `font-semibold bg-base-200` totals row whose tint loses to
    # the stripe on every odd row. Each one carried its own comment
    # rediscovering why the "!" is needed. Naming the state instead of the
    # paint is what stops that: the tint is decided once, here.
    #
    # A tint is never the only signal -- the tinted row also has to say why in
    # words, a badge, or an icon. Colour alone fails a colourblind reader and a
    # sunlit screen, and both are ordinary conditions for this product.
    #
    # @param align [Symbol, nil] vertical alignment for the row's cells
    # @param state [Symbol, nil] `:error` or `:warning` for a row needing
    #   attention, `:success` for one the request just finished with, `:total`
    #   for a sum. nil, and any state with no styling of its own, paints
    #   nothing -- which is what a plain row wants.
    # @param options [Hash] additional HTML attributes
    # @yield block containing cell elements
    def row(state: nil, **options, &block)
      row_class = striped ? ROW_STRIPED : ROW_BASE
      options[:class] = class_names(row_class, row_state_class(state), options[:class])
      alignment = options.delete(:align)
      if alignment.present?
        options[:class] += " #{ROW_ALIGNMENTS.fetch(alignment.to_sym)}"
      end

      @cell_index = 0

      template.tag.tr(**options) do
        template.capture(self, &block)
      end
    end

    # Renders a full-width row that opens beneath its summary row, for the
    # "expand to see why" pattern. Closed until a toggle_controller button
    # flips it -- pair it with a control carrying
    # `data: { toggle_dom_id_value: id }` and `aria: { controls: id }`.
    #
    # This builds its own <td> rather than going through #cell, which is what
    # keeps it out of the responsive label scheme: labels are matched to
    # headings by cell index, and a cell spanning every column would otherwise
    # inherit the FIRST heading's label and read "Callsign: Teams..." on mobile.
    #
    # @param id [String] DOM id the toggle points at
    # @param colspan [Integer, nil] defaults to the table's own heading count,
    #   so adding or removing a column cannot leave the row under-spanning
    # @param label [String, nil] whose detail this is. Below the lg breakpoint
    #   every row becomes its own card, so without this the opened detail reads
    #   as a card belonging to no one. Shown on mobile only -- on desktop the
    #   row it sits under is answer enough.
    # @yield block containing the detail content
    def detail_row(id:, colspan: nil, label: nil, **options, &block)
      raise ArgumentError, "detail_row requires a block" unless block

      options[:class] = class_names(DETAIL_ROW_CLASSES, options[:class])
      options[:aria] = { hidden: "true" }.merge(options[:aria] || {})
      content = template.capture(&block)

      template.tag.tr(**options.merge(id:)) do
        template.tag.td(template.safe_join([detail_label(label), content].compact),
                        colspan: colspan || heading_count, class: DETAIL_CELL_CLASSES)
      end
    end

    # The control that opens a #detail_row, carrying the pairing that row
    # demands: the toggle target, the expanded state, and the 36px touch floor.
    #
    # Spelled by hand at each call site, the two halves drift -- the first
    # callers to do so already disagreed about whether the accessible name
    # carries the button's own visible label. It has to: a name that does not
    # contain the visible text cannot be spoken by a voice-control user (WCAG
    # 2.5.3 Label in Name), so `describing:` is appended to the label rather
    # than replacing it.
    #
    # No toggle_label_value: toggle_controller swaps the button's innerHTML
    # when one is set, which would destroy the chevron on the first click.
    # aria-expanded carries the state instead.
    #
    # h-auto: .btn is a fixed height, so a label that wraps -- a long mail
    # subject on a phone, the vehicle paperwork chips -- would draw over the
    # row below. Unfixed, min-h-9 is the floor it was meant to be, and py-1.5
    # keeps wrapped lines off the button's edges.
    #
    # @param label [String, ActiveSupport::SafeBuffer] the visible label
    # @param id [String] DOM id of the detail_row this opens
    # @param describing [String, nil] what the detail holds, appended to the
    #   visible label to form the accessible name
    # @param name [String, nil] the whole accessible name, for a label built
    #   from markup that cannot be read into one
    # @param options [Hash] additional attributes for the button
    def detail_row_toggle(label, id:, describing: nil, name: nil, **options)
      accessible_name = name || [label, describing].compact.join(" — ").presence
      options[:class] = class_names("min-h-9 h-auto py-1.5", options[:class])
      options[:aria] = { controls: id, expanded: "false", label: accessible_name }
                       .compact.merge(options[:aria] || {})
      options[:data] = { toggle_dom_id_value: id }.merge(options[:data] || {})

      template.button_action(
        template.safe_join([label, template.fa_icon("chevron-down", :solid, class: "text-xs")], " "),
        :ghost, controller: "toggle", **options
      )
    end

    # Renders a row header cell (th in tbody).
    #
    # @param value [String, nil] the cell content (ignored if block given)
    # @param options [Hash] additional HTML attributes
    # @yield optional block for complex cell content
    def row_header(value = nil, **options, &block)
      content = block_given? ? template.capture(&block) : normalize_value(value)
      options[:class] = class_names(ROW_HEADER_CLASSES, options[:class])
      apply_data_label(options)

      template.tag.th(**options.merge(scope: "row")) { content }
    end

    # Renders a data cell (td).
    #
    # @param value [String, Numeric, nil] the cell content (ignored if block given)
    # @param right [Boolean] right-align the content
    # @param center [Boolean] center-align the content
    # @param options [Hash] additional HTML attributes
    # @yield optional block for complex cell content
    def cell(value = nil, right: false, center: false, **options, &block)
      align_class = alignment_class(right:, center:)
      content = block_given? ? template.capture(&block) : normalize_value(value)
      options[:class] = class_names(CELL_CLASSES, align_class, options[:class])
      apply_data_label(options)

      template.tag.td(content, **options)
    end

    private

    # Severity tints come from SeverityStyleHelper rather than being restated,
    # so a red row is red the same way whether a page reaches it through
    # `state:` or calls severity_style directly for the figure that earned it.
    def row_state_class(state)
      return if state.nil?

      ROW_STATES[state] || template.severity_style(state, :row)
    end

    def record_heading_label(content)
      @headings << mobile_label(content)
    end

    # Headings are recorded for every table, not just responsive ones, so
    # #detail_row can default its colspan. A heading that is blank still holds
    # a column, so count entries rather than compacting.
    def heading_count = [@headings.size, 1].max

    def detail_label(label)
      return if label.blank?

      template.tag.div(label, class: "lg:hidden font-semibold text-heading mb-1")
    end

    # Labels are matched to headings by cell index, so a cell covering several
    # columns has to consume all of them. Without that, every cell after it in
    # the row wears the label of a column to its left.
    #
    # A spanning cell also gets no label of its own. A cell reaching across the
    # whole table is the "no matching records" line, or the error under the row
    # that failed, and naming it after the first column reads on a phone as
    # "Timestamp: Position: #63" -- three of those are on the Action Log's
    # first page. #detail_row escapes this by building its own <td>; a caller
    # reaching for colspan directly cannot, so it is settled here instead.
    # An explicit `data: { label: }` still wins, since this returns before it
    # would have touched the caller's hash.
    def apply_data_label(options)
      heading_index = @cell_index
      span = [options[:colspan].to_i, 1].max
      @cell_index += span
      return unless responsive
      return if span > 1

      label_value = @headings[heading_index]
      data = options[:data]&.dup || {}
      data[:label] = label_value if !data.key?(:label) && label_value.present?
      options[:data] = data unless data.empty?
    end

    def alignment_class(right:, center:)
      if right
        "text-end"
      elsif center
        "text-center"
      else
        "text-left"
      end
    end

    def normalize_value(value)
      value.is_a?(Numeric) ? value.to_s : value
    end

    def mobile_label(content)
      return if content.nil?

      # strip_tags escapes as it sanitizes, so a heading of "Teams & positions"
      # comes back as "Teams &amp; positions" -- and tag() escapes it again on
      # the way into data-label, which the reader then sees literally. Undo the
      # sanitizer's escaping and let tag() do it exactly once.
      CGI.unescapeHTML(template.strip_tags(content.to_s)).squish.presence
    end

    def append_style(options, style)
      options[:style] = [style, options[:style]].compact.join("; ")
    end

    def class_names(*args)
      template.class_names(*args)
    end
  end
end
