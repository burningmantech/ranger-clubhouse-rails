# frozen_string_literal: true

module UiComponents
  # Markup kit for the checkbox-select-all Stimulus controller: the scope
  # wrapper, the master toggle, and per-row checkboxes. Submit buttons opt in
  # separately with data: { checkbox_select_all_target: "submit" }.
  module BulkSelectHelper
    # The box itself is AppFormBuilder::CHECKBOX_CLASSES -- this module held a
    # verbatim second copy of that string, which is how the two could drift.
    CELL_LABEL_CLASSES = "inline-flex items-center justify-center min-h-9 min-w-9 cursor-pointer"

    # Scope wrapper: everything inside shares one select-all group.
    def bulk_select(**options, &block)
      options[:data] = { controller: "checkbox-select-all" }.merge(options[:data] || {})
      content_tag(:div, capture(&block), options)
    end

    # Master toggle. With label: renders the visible-text bar form, plus a
    # live "N selected" count unless count: false. With aria_label: the
    # compact form for a table heading cell. It starts ticked when selected:
    # rows do, as every page that pre-ticks rows ticks all that select-all would.
    def bulk_select_all(label: nil, aria_label: nil, selected: 0, checked: selected.positive?, count: true,
                        name: "select_all")
      html = { class: AppFormBuilder::CHECKBOX_CLASSES,
               data: { checkbox_select_all_target: "toggle",
                       action: "change->checkbox-select-all#toggleAll" } }
      html[:aria] = { label: aria_label } if aria_label
      box = check_box_tag(name, "1", checked, html)

      return content_tag(:label, box, class: CELL_LABEL_CLASSES) unless label

      labeled = content_tag(:label, box + tag.span(label), class: "flex items-center gap-2 min-h-9")
      content_tag(:div, labeled + (count ? bulk_select_count(selected:) : "".html_safe),
                  class: "flex flex-wrap items-center gap-4 my-2")
    end

    # Live "N selected" text in checkbox_select_all_controller.js#countLabel's
    # exact words, kept current by the controller. A page whose rows start
    # ticked passes selected: with how many.
    def bulk_select_count(selected: 0, **options)
      options[:class] ||= "text-stone-muted"
      tag.span("#{selected} selected", **options, aria: { live: "polite" },
               data: { checkbox_select_all_target: "count" })
    end

    # The position picker's first count, in position_picker_controller.js#countLabel's
    # exact words. Counts the boxes the page ticks, not the ids asked for.
    def position_picker_count_label(positions, selected_ids)
      "#{(selected_ids & positions.map(&:id)).size} of #{positions.size} selected"
    end

    # A row checkbox, wrapped to the 36px touch floor. Rows with
    # skip_select_all: true are left unchecked by "select all" but stay
    # individually selectable.
    def bulk_select_checkbox(name, value, checked: false, id: nil, aria_label: nil, skip_select_all: false)
      data = { checkbox_select_all_target: "checkbox",
               action: "change->checkbox-select-all#refresh" }
      data[:skip_select_all] = true if skip_select_all
      html = { class: AppFormBuilder::CHECKBOX_CLASSES, data: }
      html[:id] = id if id
      html[:aria] = { label: aria_label } if aria_label
      content_tag(:label, check_box_tag(name, value, checked, html), class: CELL_LABEL_CLASSES)
    end
  end
end
