# frozen_string_literal: true

module UiComponents
  # Standard table filter bar: a slim always-visible row — a "Filters"
  # disclosure button with an active-count badge, one removable chip per
  # applied filter, a clear-all link, and a result count — plus a collapsed
  # panel holding the page's existing filter form (batch Apply semantics).
  # Chips are plain GET links whose URLs drop that one filter.
  module FilterBarHelper
    CHIP_CLASSES = "no-decoration inline-flex min-h-9 items-center gap-2 rounded-full " \
      "border border-line px-3 text-sm text-body transition-colors " \
      "duration-200 hover:bg-default-strong focus-visible:outline-none focus-visible:ring-2 " \
      "focus-visible:ring-primary focus-visible:ring-offset-2"
    PANEL_CLASSES = "mt-2 rounded-base border border-line p-4"

    # Marks a filter as inactive: it draws no chip and is dropped from URLs.
    # Every filtered page spells the sentinel from here, so there is one place
    # to grep and one place to change.
    ALL_FILTER = "all"

    # The "show everything" choice offered by filter selects.
    ALL_FILTER_OPTION = ["All", ALL_FILTER].freeze

    # chips:     [{ label: "Status: Active", url: "..." }, ...]
    # clear_url: target for "Clear all filters"; rendered only while chips exist
    # count:     result summary shown at the end of the bar ("Showing 9 of 27 slots")
    # url:       when given, the panel opens the standard filter GET form itself
    #            — ui_form(model, url, scope:, method: :get, local: true,
    #            no_error_summary: true) — and yields the form builder to the
    #            block, which still owns its fields and Apply submit. Without
    #            url: the block provides the whole panel, form included.
    # open:      starts the panel expanded instead of the usual collapsed-by-
    #            default state. Every existing call site leaves this at its
    #            default false, so today's behavior is unchanged; a page whose
    #            criteria matter more before a search has run (nothing to show
    #            yet) can open with the panel already in view.
    # toggle_label: text on the disclosure button, before the active-count
    #            badge. Every existing call site leaves this at its default
    #            "Filters"; a page whose form is broader than simple filtering
    #            can call it something else.
    # toggle_icon: icon on the disclosure button. Defaults to the funnel every
    #            existing call site shows; a page whose panel is a search form
    #            rather than a filter can pick an icon that says so.
    # actions:   markup for the far end of the row -- the page's Export CSV
    #            button_link, or an Array of them. The export belongs to the
    #            list the bar narrows, so it rides the bar rather than sitting
    #            in a button_row of its own. Blank entries render nothing, so a
    #            page keeps its own visibility rule inline:
    #            actions: (export_csv_link(url) if @rows.any?). Build the
    #            button with `export_csv_link`, which carries the icon and the
    #            36px floor so no call site has to remember them.
    def filter_bar(chips: [], clear_url: nil, count: nil, id: "filter-bar",
                   url: nil, model: nil, scope: nil, open: false, toggle_label: "Filters",
                   toggle_icon: "filter", actions: nil, &block)
      raise ArgumentError, "filter_bar requires a block with the filter form" unless block

      panel_id = "#{id}-panel"

      tag.div(id:, class: "mb-4") do
        safe_join([
                    filter_bar_row(chips, clear_url, count, panel_id, open, toggle_label,
                                   toggle_icon, actions),
                    filter_bar_panel(panel_id, url, model, scope, open, &block)
                  ])
      end
    end

    # Builds the chips array for filter_bar from a {key => value} hash of
    # active filters: one chip per entry, labeled "#{labels[key]}: #{value}".
    # The block receives the remaining filters (that entry dropped) plus the
    # dropped key and returns the chip's URL. value_label: maps (key, value)
    # to a display value when the raw one isn't presentable.
    def filter_chips(active, labels, value_label: nil, &url)
      active.map do |key, value|
        display = value_label ? value_label.call(key, value) : value
        { label: "#{labels[key]}: #{display}", url: url.call(active.except(key), key) }
      end
    end

    # The filters worth putting in a URL: the entries actually narrowing the
    # list. A filter is inactive when it reads "all" or was never chosen at all,
    # and both cases are dropped so chips and export links stay clean.
    #
    # module_function so controllers can call
    # UiComponents::FilterBarHelper.active_filters while helpers and views call
    # it bare, the way they already call filter_chips.
    def active_filters(filters)
      filters.reject { |_key, value| value.blank? || value == ALL_FILTER }
    end

    module_function :active_filters

    # Normalizes a filter value to the "all" sentinel unless it names one of the
    # values the page actually applies. Anything else -- a stale bookmark, a
    # typo, a nested hash -- would otherwise narrow nothing while still drawing
    # a chip claiming it did, and a hash would crash the chip's URL builder. A
    # non-String value simply fails the lookup and lands on the sentinel, so no
    # type check is needed ahead of it.
    #
    # module_function for the same reason as active_filters: every filtered page
    # calls it from its controller, before any view exists.
    def known_filter(value, allowed)
      allowed.include?(value) ? value : ALL_FILTER
    end

    module_function :known_filter

    # Options for a status select, built from a {status => count} hash: only the
    # statuses the list actually holds, commonest first, each carrying its count.
    # Offering the rest would be choices that can only return nothing.
    #
    # matching: a second {status => count} hash for the LABELS, when the page's
    # other filters mean a choice would deliver fewer people than the list
    # holds. A select navigates, so its counts have to promise the roster the
    # choice delivers. Ordering still comes from status_counts, so the options
    # do not reshuffle as the other filters change.
    def filter_status_options(status_counts, matching: nil)
      labels = matching || status_counts

      [ALL_FILTER_OPTION] +
        status_counts.sort_by { |status, count| [-count, status] }
                     .map { |status, _count|
                       ["#{status} (#{labels.fetch(status, 0)})", status]
                     }
    end

    module_function :filter_status_options

    # Options for a select over a fixed set of values, from the same
    # {value => label} hash the page's chips label those values with, so an
    # option and the chip it sets read alike: "All" first, then each value.
    def filter_select_options(labels)
      [ALL_FILTER_OPTION, *labels.map { |value, label| [label, value] }]
    end

    module_function :filter_select_options

    # The tri-state sign-up select. Lives here rather than on either page so the
    # options a page offers and the values SignedUpFilterConcern accepts cannot
    # drift apart.
    def filter_signed_up_options
      [ALL_FILTER_OPTION,
       ["Yes", SignedUpFilterConcern::SIGNED_UP_YES],
       ["No", SignedUpFilterConcern::SIGNED_UP_NO]]
    end

    module_function :filter_signed_up_options

    # Builds a filter URL from a route helper name and a filter hash. Inactive
    # filters are dropped, except that every key in always: is emitted as the
    # "all" sentinel rather than omitted.
    #
    # always: is for a page that arrives pre-filtered -- one whose default is
    # something narrower than "all". Omitting such a filter does not mean "off",
    # it means "back to the default", so a chip's remove link or clear-all that
    # simply dropped it would silently re-apply the filter it claimed to remove.
    # Naming the keys here keeps that from being each page's problem to remember.
    def filter_url(route_helper, filters, always: [])
      params = active_filters(filters)
      Array(always).each { |key| params[key] ||= ALL_FILTER }
      public_send(route_helper, **params)
    end

    private

    def filter_bar_row(chips, clear_url, count, panel_id, open, toggle_label, toggle_icon, actions)
      tag.div(class: "flex flex-wrap items-center gap-2") do
        parts = [filter_bar_toggle(chips.size, panel_id, open, toggle_label, toggle_icon)]
        parts.concat(chips.map { |chip| filter_bar_chip(chip) })
        if clear_url && chips.any?
          parts << button_link("Clear All Filters", :ghost, clear_url)
        end
        parts << tag.span(count, class: "ms-2 text-lg text-stone-muted") if count
        parts << filter_bar_actions(actions)
        safe_join(parts.compact)
      end
    end

    # The row's trailing actions, right-aligned by ms-auto. The row already
    # wraps, so on a phone they drop to their own line rather than crushing the
    # chips. compact_blank, so a page can pass a conditional straight through
    # and a bar with nothing to show grows no empty div.
    def filter_bar_actions(actions)
      actions = Array.wrap(actions).compact_blank
      return if actions.empty?

      tag.div(safe_join(actions), class: "ms-auto flex flex-wrap items-center gap-2")
    end

    def filter_bar_toggle(active_count, panel_id, open, toggle_label, toggle_icon)
      label = safe_join([
                          toggle_label,
                          (ui_badge(active_count.to_s, :primary) if active_count.positive?)
                        ].compact)

      button_action label, :secondary, controller: "toggle",
                    icon: toggle_icon, icon_type: :solid,
                    aria: { controls: panel_id, expanded: open ? "true" : "false" },
                    data: { toggle_dom_id_value: panel_id }
    end

    def filter_bar_chip(chip)
      link_to chip[:url], class: CHIP_CLASSES,
              aria: { label: "Remove filter: #{chip[:label]}" } do
        safe_join([tag.span(chip[:label]), fa_icon("xmark", :solid)])
      end
    end

    def filter_bar_panel(panel_id, url, model, scope, open, &block)
      content = if url
                  ui_form(model, url, scope:, method: :get, local: true,
                          no_error_summary: true) do |f|
                    capture(f, &block)
                  end
                else
                  capture(&block)
                end

      panel_classes = class_names(PANEL_CLASSES, ("hidden" unless open))

      tag.div(content, id: panel_id, class: panel_classes,
              aria: { hidden: open ? "false" : "true" })
    end
  end
end
