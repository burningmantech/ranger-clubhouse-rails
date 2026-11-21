# frozen_string_literal: true

# The controls of the TRS Formats grid (ticketing/trs_formats/_column_row) and
# of the picker a column's source is chosen from (_source_picker).
#
# Each control of a row says where it stands, and carries the pattern
# form_rows_controller.js rewrites that from after a row is moved, inserted or
# deleted in the page: {n} for the row's number, {i} for its index.
module Ticketing::TrsFormatsHelper
  # The month whose days the picker offers for a credential's or a pass's
  # access date. All of them, whatever TAS_SAPDateRange allows this year: the
  # vendor's template decides which dates have a column.
  PICKER_MONTH = 8

  # One heading's worth of the picker's choices; title is nil for the lone
  # Not Used choice, which stands above the headings.
  SourceGroup = Data.define(:title, :choices)

  # One choice: the key a format stores, what the button shows (a day number is
  # enough under a heading that names the rest), and the whole name, which the
  # row's button takes and a screen reader is given.
  SourceChoice = Data.define(:key, :text, :label)

  # The attributes that name a control by its row. index: nil is the blank row
  # in the grid's <template>: it has no place yet, so it carries the patterns
  # alone and the controller numbers it when it is inserted.
  #
  # @param index [Integer, nil] the row's place, from 0
  # @param label [String, nil] the aria-label pattern, e.g. "CSV header of column {n}"
  # @param id [String, nil] the id pattern, e.g. "trs-column-{i}-source"
  # @return [Hash] aria:, id: and data: for a tag helper
  def trs_column_naming(index, label: nil, id: nil)
    { aria: { label: (label.sub("{n}", (index + 1).to_s) if label && index) },
      id: (id.sub("{i}", index.to_s) if id && index),
      data: { form_rows_label: label, form_rows_id: id }.compact }
  end

  # One of a row's icon buttons. hidden: draws an arrow an end row cannot use
  # invisible rather than leaving it out, because which row is first or last
  # changes in the page. tab_stop: marks the one button of the row's toolbar
  # that Tab lands on; the arrow keys reach the others.
  def trs_column_button(action, index, icon:, title:, label:, hidden: false, tab_stop: false)
    button_action "", :secondary, class: class_names("btn-square", invisible: hidden),
                  icon:, icon_type: :solid, title:, tabindex: (tab_stop ? 0 : -1),
                  **trs_column_naming(index, label:).deep_merge(data: { action: "form-rows##{action}" })
  end

  # What fills a column: the key in a hidden field, which is what the form
  # posts, and a button that names it and opens the picker
  # (source_picker_controller.js). The number in the button's spoken name is
  # one form-rows keeps up to date; "Not Used" is drawn muted.
  def trs_column_source(index, source)
    name = safe_join(["Source of column ", tag.span((index + 1 if index), data: { form_rows_number: true }), ": "])
    # ms-auto, not a gap: it sends the chevron to the button's far edge, as on a select.
    face = safe_join([tag.span(name, class: "sr-only"),
                      tag.span(TrsExport.source_label(source), class: class_names("truncate", "text-stone-muted": source.blank?),
                                                               data: { source_picker_target: "label" }),
                      fa_icon("chevron-down", :solid, class: "ms-auto")])

    # Below lg the button is a share of its cell, capped at its desktop width: a fixed width
    # would hold a folded row wider than a small phone. The cell is grown to the line by
    # _column_row, or that share would be of a cell only as wide as the button's name.
    tag.div(data: { source_picker_target: "field" }) do
      safe_join([hidden_field_tag("trs_format[row_sources][]", source.presence,
                                  **trs_column_naming(index, id: "trs-column-{i}-source")),
                 button_action(face, :secondary, class: "w-72 max-lg:w-full max-lg:max-w-72",
                                                 aria: { haspopup: "dialog" },
                                                 data: { action: "source-picker#open" })])
    end
  end

  # Everything the picker offers, in the order it is drawn: Not Used, the row's
  # own fields, the items counted, then a credential's and a pass's access
  # dates, any time first and then every day of PICKER_MONTH.
  #
  # A date in another month that the format already holds is given a choice of
  # its own after those ("Jul 31"), so the picker can show it as the current
  # one and it can be chosen again after a slip. A new one cannot be added here.
  #
  # @param stored [Array<String>] the sources the format's columns hold
  # @return [Array<SourceGroup>]
  def trs_source_groups(stored = [])
    plain = ->(labels) { labels.map { |key, label| SourceChoice.new(key:, text: label, label:) } }
    month = Date::MONTHNAMES[PICKER_MONTH]
    in_month = "#{Date::ABBR_MONTHNAMES[PICKER_MONTH]} "

    dated = TrsExport::DATED_LABELS.map do |base, kind|
      keys = ["#{base}_anytime"] + (1..Time.days_in_month(PICKER_MONTH)).map { |day| format("%s_%02d%02d", base, PICKER_MONTH, day) }
      elsewhere = stored.select { |key| key.start_with?("#{base}_") && TrsExport.source?(key) } - keys
      choices = (keys + elsewhere.sort).map do |key|
        label = TrsExport.source_label(key)
        # "Any time", the day alone in the picker's month, "Jul 31" in another.
        SourceChoice.new(key:, text: label.split(" · ").last.delete_prefix(in_month), label:)
      end
      SourceGroup.new(title: "#{kind.pluralize}, by Access Date in #{month}", choices:)
    end

    [SourceGroup.new(title: nil, choices: [SourceChoice.new(key: "", text: "Not Used: Export This Column Empty",
                                                            label: TrsExport::NOT_USED)]),
     SourceGroup.new(title: "Person", choices: plain.call(TrsExport::ROW_FIELD_LABELS)),
     SourceGroup.new(title: "How Many of an Item", choices: plain.call(TrsExport::REQUEST_LABELS)),
     *dated]
  end
end
