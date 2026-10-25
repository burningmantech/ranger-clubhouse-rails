# frozen_string_literal: true

# Filter chips, sortable headings, and cell formatting for the BMID management
# roster (/bmid/manage). Every label here is a port of the Ember vc/bmid
# templates, so the ticketing crew reads the same words they always have.
module Bmid::ManageHelper
  # What the badge holder is being fed. "Any Eats" is upstream's name for "all
  # eats OR event week only", not "any meal at all"; the name is kept so the
  # page agrees with the roster people already know.
  #
  # Upstream offered these and showers as one "Wants" select, so the two could
  # never be asked together -- "who eats all week AND showers?" took two passes
  # and a comparison by eye.
  MEALS_OPTIONS = [
    ["All Eat", "all_eat"],
    ["Event Week Eat", "event_week"],
    ["Any Eats", "any_eat"]
  ].freeze

  SHOWERS_OPTIONS = [
    ["Yes", "yes"],
    ["No", "no"]
  ].freeze

  QUALIFIED_OPTIONS = [
    ["Meets qualifications", "qualified"],
    ["Does not meet qualifications", "unqualified"]
  ].freeze

  # The five statuses Edit Mode offers. The two ready-to-reprint statuses are
  # still accepted on write -- a badge already carrying one keeps it -- but they
  # are not choices here (upstream parity: reprints are decided elsewhere).
  EDIT_STATUS_OPTIONS = [
    ["Prep", Bmid::IN_PREP],
    ["Do Not Print", Bmid::DO_NOT_PRINT],
    ["Ready To Print", Bmid::READY_TO_PRINT],
    ["Issues", Bmid::ISSUES],
    ["Submitted", Bmid::SUBMITTED]
  ].freeze

  EDIT_STATUS_VALUES = EDIT_STATUS_OPTIONS.map(&:last).freeze

  # The chip and select labels, keyed by the value that travels in the URL.
  MEALS_LABELS = MEALS_OPTIONS.to_h { |label, value| [value, label] }.freeze
  SHOWERS_LABELS = SHOWERS_OPTIONS.to_h { |label, value| [value, label] }.freeze
  QUALIFIED_LABELS = QUALIFIED_OPTIONS.to_h { |label, value| [value, label] }.freeze
  CATEGORY_LABELS = BmidManagement::FILTER_OPTIONS.to_h { |label, value| [value, label] }.freeze

  # The person page's status wording, keyed for lookup so the two pages cannot
  # drift apart.
  STATUS_LABELS = BmidHelper::BMID_STATUS_OPTIONS.to_h { |label, value| [value, label] }.freeze

  # Badge colour per status. The three reprint-family statuses read the same as
  # Ready To Print because they all end up at the printer.
  STATUS_VARIANTS = {
    Bmid::IN_PREP => :secondary,
    Bmid::READY_TO_PRINT => :success,
    Bmid::READY_TO_REPRINT_CHANGE => :success,
    Bmid::READY_TO_REPRINT_LOST => :success,
    Bmid::ISSUES => :error,
    Bmid::DO_NOT_PRINT => :warning,
    Bmid::SUBMITTED => :primary
  }.freeze

  # Upstream MEALS_SHORT_LABELS.
  MEALS_SHORT_LABELS = { pre: "Pre", event: "Event", post: "Post" }.freeze

  ASCENDING = "asc"
  DESCENDING = "desc"

  # The links sit in the table header, so the ring's gap is the header's base-200.
  SORT_LINK_CLASSES = "no-decoration inline-flex min-h-9 items-center gap-2 text-body " \
                      "hover:text-heading transition-colors duration-200 " \
                      "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary " \
                      "focus-visible:ring-offset-2 focus-visible:ring-offset-base-200"

  # The tint a row wears in Edit Mode while it is holding unsaved edits. It is
  # named here, in a file Tailwind scans, and handed to the Stimulus controller
  # as a class attribute -- a class assembled in JavaScript would never be
  # compiled.
  DIRTY_ROW_CLASS = "bg-warning/10"

  # --- filter bar -----------------------------------------------------------

  # One chip per active filter in the panel. The year is not a chip -- it is
  # chosen in the hero panel, not here.
  #
  # The category is, once it is not the default. It is the panel's first and
  # widest control, so a page that drew no chip at all for it read as a filter
  # bar that had simply stopped working; and its × has somewhere to go, back to
  # the default category. Dropping it from base means the chip URLs can leave it
  # out, which is what "remove the category" has to mean.
  #
  # @param active [Hash] the active secondary filters, symbol-keyed
  # @param base [Hash] the params every link carries (year, category, sort)
  def bmid_manage_filter_chips(active, base)
    labels = { filter: "Category", title: "Title", team: "Team", meals: "Meals",
               showers: "Showers", qualified: "Print qualification", q: "Search" }

    category = base[:filter]
    active = { filter: category, **active } unless category == BmidManagement::DEFAULT_FILTER

    filter_chips(active, labels, value_label: BMID_CHIP_VALUE) do |remaining|
      bmid_manage_path(base.except(:filter).merge(remaining))
    end
  end

  # Chip values that are codes in the URL and words on the page.
  BMID_CHIP_VALUE = lambda do |key, value|
    case key
    when :filter then CATEGORY_LABELS.fetch(value, value)
    when :meals then MEALS_LABELS.fetch(value, value)
    when :showers then SHOWERS_LABELS.fetch(value, value)
    when :qualified then QUALIFIED_LABELS.fetch(value, value)
    else value
    end
  end

  # One secondary-filter select.
  #
  # A category can carry none of a thing -- no titles, no teams, no one fed,
  # no one washed -- and then the select's only choice is "All". Left enabled it
  # is a control that looks like the others and cannot narrow anything, so it is
  # disabled and says why instead. The controller drops the matching filter for
  # the same reason, so a disabled select can never be hiding an active one.
  #
  # @param form [AppFormBuilder]
  # @param choices [Array] the values on offer, empty when the category has none
  # @param empty_note [String] what to say in that case
  def bmid_filter_select(form, attribute, label, choices, selected, empty_note)
    offered = choices.any?

    # disabled rides in the html_options hash, not the options one: AppFormBuilder
    # forwards a named few of its own keys and passes the rest to Rails' select,
    # where :disabled means "grey out these option values" instead.
    form.select attribute,
                [UiComponents::FilterBarHelper::ALL_FILTER_OPTION, *choices],
                { label:, selected:, help_text: (empty_note unless offered),
                  width: "w-full", wrapper_class: "flex-1" },
                offered ? {} : { disabled: true }
  end

  # --- sortable headings ----------------------------------------------------

  # A sortable column heading, rendered straight into the table builder.
  #
  # @param table [TableHelper::UiTableBuilder]
  # @param state [Hash] { sort:, dir:, params: } from the controller
  # The sortable columns shared by the read table and the Edit Mode grid, in
  # display order after Callsign (whose neighbors differ between the two).
  SORT_COLUMNS = [
    ["Status", "status"],
    ["Title 1", "title1"],
    ["Title 2", "title2"],
    ["Title 3", "title3"],
    ["MVR", "mvr", { title: "Motor vehicle record on file" }],
    ["Showers", "showers"],
    ["Meals", "meals"],
    ["SAP", "sap"],
    ["Team", "team"],
    ["Notes", "notes"]
  ].freeze

  def bmid_sort_headings(table, state)
    safe_join(SORT_COLUMNS.map do |label, column, options|
      bmid_sort_heading(table, label, column, state, **(options || {}))
    end)
  end

  def bmid_sort_heading(table, label, column, state, **options)
    table.heading(**options, aria: { sort: bmid_sort_aria(column, state) }) do
      bmid_sort_link(label, column, state)
    end
  end

  # Clicking a column that is not the active sort sorts it ascending; clicking
  # the active one flips the direction. The caret only ever appears on the
  # active column, so an arrow always means "this is what you are reading".
  def bmid_sort_link(label, column, state)
    active = state[:sort] == column
    next_dir = (active && state[:dir] == ASCENDING) ? DESCENDING : ASCENDING
    url = bmid_manage_path(state[:params].merge(sort: column, dir: next_dir))
    direction = (next_dir == ASCENDING) ? "ascending" : "descending"

    link_to url, class: SORT_LINK_CLASSES, aria: { label: "Sort by #{label}, #{direction}" } do
      safe_join([
        tag.span(label),
        (fa_icon(state[:dir] == ASCENDING ? "caret-up" : "caret-down", :solid) if active)
      ].compact)
    end
  end

  def bmid_sort_aria(column, state)
    return "none" unless state[:sort] == column

    state[:dir] == ASCENDING ? "ascending" : "descending"
  end

  # --- row and cell identity ------------------------------------------------

  # Rows and provision cells are keyed by person, not by badge id: a badge is
  # synthesized until its first save and has no id to key on.
  def bmid_row_dom_id(bmid) = "bmid-row-#{bmid.person_id}"

  def bmid_showers_cell_id(bmid) = "bmid-showers-cell-#{bmid.person_id}"

  def bmid_meals_cell_id(bmid) = "bmid-meals-cell-#{bmid.person_id}"

  # --- the current view -----------------------------------------------------

  # Everything that decides what the roster is showing: the year and the
  # category, the five secondary filters, the sort, and which of the two
  # layouts is on screen. A page opened from a row round-trips the whole set --
  # the link in, the form's action, the Cancel link, and the redirect after a
  # save -- so an admin lands back on the roster they were reading rather than
  # on its default view.
  #
  # This is the same key set Bmid::ManageController assembles as @index_params
  # (base_params + active_secondary_filters), which is what the roster hands to
  # its own Edit links. The two are pinned together by
  # "the per-row edit link carries every param the view is made of".
  VIEW_PARAMS = %i[year filter title team meals showers qualified q sort dir mode].freeze

  # The current view, read straight from the request. Used by the pages the
  # roster opens, which have no @index_params of their own -- they were handed
  # one and have to hand it back.
  #
  # Deliberately not re-derived and not re-validated: Bmid::ManageController
  # sanitizes every one of these on arrival -- an unknown category becomes the
  # default, an unoffered title becomes no filter, an unknown sort column
  # becomes callsign -- so handing them straight back cannot get anything past
  # it, and a second set of rules here could only disagree with the first.
  #
  # bmid_provision_context below is the narrower, validated pair the provision
  # dialogs need: they redirect on their own when Turbo is not doing the work,
  # so their fallback target has to be a place the roster would go by itself.
  #
  # @param overrides [Hash] merged last, e.g. anchor: for the row to return to
  def bmid_view_params(overrides = {})
    params.permit(*VIEW_PARAMS).to_h.symbolize_keys.compact_blank.merge(overrides)
  end

  # --- the modal frame ------------------------------------------------------

  # Wraps a dialog in the page's one "modal" turbo-frame -- but only when the
  # request came from that frame.
  #
  # The application layout already emits <turbo-frame id="modal">, so a dialog
  # that always brought its own would answer a plain GET with two elements
  # carrying the same id: invalid, and getElementById resolves the wrong one.
  # And a plain GET is not hypothetical -- the cell actions are real links, so
  # "open in new tab" and a middle-click both make one.
  def bmid_modal_frame(&block)
    return capture(&block) unless turbo_frame_request?

    turbo_frame_tag("modal", &block)
  end

  # --- provision cells ------------------------------------------------------

  # What the two provision-derived cells are called, in the words their buttons,
  # dialogs, and screen-reader labels use. The add labels match the person's own
  # provisions page, so the same button says the same thing on both.
  PROVISION_CELL_WORDS = {
    Provision::WET_SPOT => { noun: "shower access", add: "Add Shower Pass" },
    Provision::MEALS => { noun: "meals", add: "Add Meal Pass" }
  }.freeze

  def bmid_provision_noun(type) = PROVISION_CELL_WORDS.fetch(type).fetch(:noun)

  def bmid_provision_add_label(type) = PROVISION_CELL_WORDS.fetch(type).fetch(:add)

  # The button in a meals or showers cell. It opens the page's one modal frame
  # instead of leaving the grid, so an admin never loses the badge edits they
  # have in progress -- and because it is a link, not a field, opening it cannot
  # mark the row as changed.
  #
  # A person may hold more than one usable provision of a type -- an earned pass
  # and an allocated one, or an earned pass that was banked and came back into
  # play because they hold an allocated one -- and the cell's label is the union
  # of all of them. So the button opens the list of them rather than any one
  # record: picking the first would edit the wrong pass as often as the right
  # one, and would leave a second pass impossible to add from this page.
  #
  # A person holding none has nothing to list, so that button goes straight to
  # the form it would otherwise take two clicks to reach.
  def bmid_provision_cell_action(bmid, type, provisions)
    noun = bmid_provision_noun(type)
    callsign = bmid.person&.callsign
    context = bmid_provision_context.merge(person_id: bmid.person_id, type:)

    if provisions.present?
      label = "Manage #{noun} for #{callsign}"
      url = bmid_provisions_path(context)
      icon = "pen"
    else
      label = "Add #{noun} for #{callsign}"
      url = new_bmid_provision_path(context)
      icon = "plus"
    end

    # The icon rides in as the label rather than through the :icon option,
    # which builds the <i> from a fixed hash and so cannot carry the
    # aria-hidden its sr-only twin below depends on. The column is narrow, so
    # the words are read out rather than shown, and the tooltip repeats them
    # for a mouse. Spacing is .btn's own gap; nothing here spells a margin.
    face = safe_join([fa_icon(icon, :solid, "aria-hidden": "true"),
                      tag.span(label, class: "sr-only"),
                      "Manage"
                     ])

    button_link(face, :secondary, url, title: label, size: "sm", data: { turbo_frame: "modal" })
  end

  # The cells appear on two pages, and a dialog opened from one has to fall back
  # to the one it came from. Only the badge editor needs saying: the roster is
  # where a dialog goes when nothing marks it otherwise.
  BADGE_ORIGIN = "badge"

  # Which page the dialog belongs to, for the redirect it falls back to when
  # Turbo is not doing the work. Read straight from the request, the same way
  # both controllers read it, rather than threaded through the page: the page
  # and the turbo_stream that redraws a single cell come from two different
  # requests, and each already carries the year and the category.
  #
  # The origin is set by the badge editor and echoed by every later step of the
  # dialog, including the cells it redraws -- by then the request belongs to
  # Bmid::ProvisionsController, which only knows where it came from because the
  # param rode along.
  def bmid_provision_context
    filter = params[:filter].presence

    context = { year: params[:year].presence&.to_i || current_year,
                filter: BmidManagement::FILTERS.include?(filter) ? filter : BmidManagement::DEFAULT_FILTER }
    context[:from] = BADGE_ORIGIN if bmid_badge_origin?
    context
  end

  def bmid_badge_origin?
    controller_name == "badges" || params[:from] == BADGE_ORIGIN
  end

  # --- edit mode ------------------------------------------------------------

  # The statuses the Edit Mode select offers for one badge: the standard five,
  # plus the badge's own status when it is one of the two reprint statuses the
  # grid does not offer. A select that cannot show the current value would make
  # saving an untouched row silently change its status -- the same rule
  # admission_date_options follows for an out-of-range access date.
  def bmid_edit_status_options(bmid)
    return EDIT_STATUS_OPTIONS if EDIT_STATUS_VALUES.include?(bmid.status)

    EDIT_STATUS_OPTIONS + [[STATUS_LABELS.fetch(bmid.status, bmid.status), bmid.status]]
  end

  # The Edit Mode change counter. The server renders the first value and
  # bulk_edit_controller#countLabel repeats these exact words from then on, so a
  # page that comes back holding rows that would not save is never briefly
  # labelled as having no changes.
  def bmid_dirty_count_label(count)
    case count
    when 0 then "No rows changed"
    when 1 then "1 row changed"
    else "#{count} rows changed"
    end
  end

  # One row's validation failures. Each message is a sentence that names its
  # field (config/locales/en.yml).
  def bmid_row_error_sentence(bmid)
    bmid.errors.full_messages.join(" ")
  end

  # Why the SAP date cannot be edited on this row, or nil when it can. A past
  # year is checked first: the pass on that row is the one the person holds for
  # the NEXT event, so it is the reason that matters even when the pass is also
  # missing or already submitted.
  def bmid_sap_disabled_badge(bmid)
    if !bmid.current_event_year?
      ui_badge("Previous year", :secondary, size: "sm")
    elsif bmid.sap.nil?
      ui_badge("SAP missing", :warning, size: "sm")
    elsif bmid.sap_submitted?
      ui_badge("SAP submitted", :secondary, size: "sm")
    end
  end

  # --- cells ----------------------------------------------------------------

  def bmid_status_badge(bmid)
    ui_badge(STATUS_LABELS.fetch(bmid.status, bmid.status),
             STATUS_VARIANTS.fetch(bmid.status, :secondary),
             size: "sm")
  end

  # Upstream buildMealsLabel with the short labels. Also the sort key for the
  # Meals column and the Meals cell of the CSV, so all three agree.
  def bmid_meals_short_label(bmid)
    meals = bmid.meals_granted
    return "none" if meals.nil?
    return "All Eats" if meals.pre && meals.event && meals.post

    periods = []
    periods << MEALS_SHORT_LABELS[:pre] if meals.pre
    periods << MEALS_SHORT_LABELS[:event] if meals.event
    periods << MEALS_SHORT_LABELS[:post] if meals.post

    periods.empty? ? "none" : periods.join(" & ")
  end

  # The SAP column: a badge when the person holds no setup access pass at all,
  # otherwise upstream's short admission date.
  def bmid_sap_cell(bmid)
    return ui_badge("No SAP", :warning, size: "sm") if bmid.sap.nil?

    bmid_sap_label(bmid)
  end

  def bmid_sap_label(bmid)
    return "any" if bmid.access_any_time
    return "(no date)" if bmid.access_date.blank?

    wday_month_day_format(bmid.access_date)
  end

  # Row emphasis is never colour alone: whatever puts an accent on the row also
  # puts an icon in the flag column. A missing photo outranks a missing
  # qualification (upstream parity), and the transparent border keeps every
  # other row's columns from shifting.
  def bmid_row_accent_class(bmid)
    if !bmid.has_approved_photo
      "border-l-4 border-error"
    elsif bmid.not_qualified_to_print? && bmid.status == Bmid::IN_PREP
      "border-l-4 border-warning"
    else
      "border-l-4 border-transparent"
    end
  end

  # The two flag icons, each carrying the same sentence as the legend below the
  # table header.
  def bmid_flag_icons(bmid)
    flags = []

    unless bmid.has_approved_photo
      flags << fa_icon("eye", :solid, class: "icon-error",
                                      title: "No approved photo on file.")
    end

    if bmid.not_qualified_to_print?
      flags << fa_icon("circle-exclamation", :solid, class: "icon-warning",
                                             title: "No ticket or SAP claimed, and no In-Person Training sign-up.")
    end

    return nil if flags.empty?

    safe_join([tag.span(safe_join(flags, " "), class: "inline-flex items-center gap-1"),
               tag.span(bmid_flag_text(bmid), class: "sr-only")])
  end

  private

  def bmid_flag_text(bmid)
    parts = []
    parts << "No approved photo." unless bmid.has_approved_photo
    parts << "Does not meet the printing qualifications." if bmid.not_qualified_to_print?
    parts.join(" ")
  end
end
