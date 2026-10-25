# frozen_string_literal: true

# Naming and formatting for the Shift Lead Report.
#
# Helper names are one global namespace in Rails, so everything here is
# shift_lead_-prefixed.
module Scheduling::ShiftLeadHelper
  # The filter and sort tokens live here, with their labels, rather than on the
  # controller: a helper constant naming a controller constant is resolved at
  # load time, and a helper/controller pair naming each other that way deadlocks
  # both autoloads. The controller reads these inside methods, at request time.

  # Years is a floor rather than a band -- "who has at least this much
  # experience" is the question a shift lead actually asks. 1+ is not the no-op
  # it looks like: it drops the Rangers with no prior years at all.
  YEARS_LABELS = {
    "1" => "1 or more years",
    "2" => "2 or more years",
    "5" => "5 or more years",
    "10" => "10 or more years"
  }.freeze

  # One control for both vehicle columns, because they answer one question --
  # may this Ranger take a rig out. Two selects could not offer "blacklisted"
  # without saying it twice.
  VEHICLE_GTR = "gtr"
  VEHICLE_VEH = "veh"
  VEHICLE_BOTH = "both"
  VEHICLE_BLACKLISTED = "blacklisted"

  VEHICLE_LABELS = {
    VEHICLE_GTR => "Signed the vehicle protocol (GTR)",
    VEHICLE_VEH => "Has org insurance (VEH)",
    VEHICLE_BOTH => "Has both GTR and VEH",
    VEHICLE_BLACKLISTED => "Vehicle blacklisted"
  }.freeze

  SORT_DEFAULT = "default"
  SORT_GENDER = "gender"
  SORT_YEARS = "years"
  SORT_CALLSIGN = "callsign"

  # No "All" entry: every roster is ordered somehow. The default is the report's
  # own order, which upstream defines and this page does not second-guess.
  SORT_LABELS = {
    SORT_DEFAULT => "Position (default)",
    SORT_GENDER => "Gender",
    SORT_YEARS => "Years rangered",
    SORT_CALLSIGN => "Callsign"
  }.freeze

  # One sort per roster, so the reader can put the dirt roster in callsign order
  # while command staff stays in position order.
  ROSTER_SECTIONS = [:dirt, :command, :special].freeze

  FILTER_CHIP_LABELS = {
    years: "Years",
    position: "Position",
    gender: "Gender",
    vehicle: "Vehicle",
    start_time: "Shift Start"
  }.freeze

  # Which rosters the page shows.
  #
  # Filtering by position collapses the page to the one roster that position
  # belongs to. A position lives on exactly one roster, so the other two could
  # only ever read "0 of N — no one matches the current filters": two panels of
  # noise on either side of the one answer that was asked for.
  #
  # The roster is chosen by where the position lives in the UNFILTERED report,
  # not by which list still has rows. A position filter combined with a gender
  # filter can empty every list, and the reader still needs to see which roster
  # they were asking about rather than a page with no rosters on it at all.
  def shift_lead_visible_rosters(rosters, filter_params)
    position = filter_params[:position]
    return rosters if position == UiComponents::FilterBarHelper::ALL_FILTER

    rosters.select { |roster|
      roster[:all].any? { |ranger| ranger.position_full_title == position }
    }
  end

  # --- filter chrome --------------------------------------------------------

  # What the page is reporting on, plus every sort: the parts of the query
  # string that are not filters and must survive a chip being removed, a filter
  # being applied, or a sort being changed. Without these a chip's remove link
  # would drop the reader back on the empty picker.
  # A sort left in the report's own order is left out of the URL entirely --
  # it is the default, so naming it says nothing and puts three dead parameters
  # on every chip, every clear-all link and the Print button.
  # `mode` is resolved from @on_duty_mode rather than echoed from params: the
  # raw value is whatever the query string said, and `?mode[x]=1` hands us an
  # ActionController::Parameters that survives `.presence` and then raises
  # UnfilteredParameters the moment a route helper calls to_query on it -- a 500
  # on every URL this builds. The sibling slot_id parameter is hardened the same
  # way in the controller.
  def shift_lead_context_params(filter_params)
    sorts = filter_params.slice(*shift_lead_sort_keys).reject { |_key, value| value == SORT_DEFAULT }
    mode = Scheduling::ShiftLeadController::ON_DUTY_MODE if @on_duty_mode

    { year: @year, mode: mode, slot_id: @slot&.id }.merge(sorts).compact
  end

  # Everything the page is currently showing: what it reports on, how each
  # roster is ordered, and what is narrowing it. Every link and form that must
  # survive a navigation builds from this one place -- a control that assembles
  # its own URL silently drops whichever half it forgot.
  def shift_lead_all_params(filter_params)
    return { year: @year, slot_id: @slot&.id }.compact if filter_params.blank?

    shift_lead_context_params(filter_params)
      .merge(UiComponents::FilterBarHelper.active_filters(filter_params.except(*shift_lead_sort_keys)))
  end

  # The same values as hidden fields, for the forms that submit a bare GET.
  #
  # id: nil on every one of them -- this page carries four GET forms (the shift
  # picker, the filter panel and a sort control per roster) and a hidden field
  # defaults its id from its name, so without this the year field alone would
  # appear four times under one id and Turbo's morph could silently drop it.
  def shift_lead_carried_fields(values, except: [])
    safe_join(values.except(*except).map { |name, value|
      hidden_field_tag(name, value, id: nil)
    })
  end

  def shift_lead_filter_chips(filter_params)
    active = UiComponents::FilterBarHelper.active_filters(filter_params.except(*shift_lead_sort_keys))
    context = shift_lead_context_params(filter_params)

    filter_chips(active, FILTER_CHIP_LABELS,
                 value_label: ->(key, value) { shift_lead_filter_value_label(key, value) }) do |remaining, _key|
      scheduling_shift_lead_path(**context, **remaining)
    end
  end

  # The chip says what was chosen, not the token that was submitted.
  def shift_lead_filter_value_label(key, value)
    case key
    when :years then YEARS_LABELS.fetch(value, value)
    when :vehicle then VEHICLE_LABELS.fetch(value, value)
    else value
    end
  end

  # The filter bar's count slot. "of N" appears only while something is being
  # narrowed, so an unfiltered page does not say "102 of 102".
  #
  # The empty shift is checked before the empty result: a shift no one signed up
  # for is not a filter miss, and blaming the filters sends the reader hunting
  # for one to clear that was never set. The rosters below draw the same
  # distinction on `total.positive?`.
  def shift_lead_summary_count(shown:, total:)
    return (@on_duty_mode ? "No one is on duty right now" : "No one has signed up for this shift") if total.zero?
    return "No one matches the current filters" if shown.zero?
    return pluralize(shown, "person") if shown == total

    "Showing #{shown} of #{pluralize(total, "person")}"
  end

  # Prefixed like everything else here: helper names are one global namespace,
  # and a bare `sort_keys` would be visible to every view in the app.
  def shift_lead_sort_keys = ROSTER_SECTIONS.map { |section| :"sort_#{section}" }

  # The chips beside a callsign. Upstream tints a whole cell instead, which says
  # the same thing in colour alone -- unreadable in greyscale, to a colour-blind
  # reader, or through a screen reader -- and, being one cell, can only ever
  # show the first of the two.
  def shift_lead_chips(ranger)
    chips = []
    chips << ui_badge("GD", :success, title: "Qualified Green Dot") if ranger.green_dot
    chips << ui_badge("TS", :secondary, title: "Troubleshooter") if ranger.troubleshooter

    safe_join(chips, " ")
  end

  # The clock time a roster prints. Slot times are already stored as local wall
  # clock, so nothing converts them.
  def shift_lead_time(time) = time&.strftime(DateTimeHelper::HOUR_MINS)

  # The GTR? and Veh? columns. Both answer the same question -- may this Ranger
  # take a rig out -- so they share a spelling, and a blacklisted person reads
  # -BL- in both whatever they have signed.
  def shift_lead_vehicle_cell(status, label)
    case status
    when :blacklisted then tag.span("-BL-", class: "font-bold text-error")
    when :yes then label
    else "-"
    end
  end

  # The phone roster's answer to the GTR? and Veh? columns.
  #
  # Both badges are always rendered, present or not: a chip shown only when the
  # answer is yes asks the reader to read meaning into a missing chip, which is
  # the absence-only failure the GD/TS chips were introduced to fix.
  #
  # The yes/no is carried by the badge's own TEXT, not by its icon: fa_icon sets
  # aria-hidden on every icon it renders, and a title: on a span that already
  # has text is not announced in browse mode -- so a bare "GTR" on both branches
  # reads identically to a screen reader, leaving the distinction to colour
  # alone. Below the lg breakpoint this block is the only rendering of the
  # roster, so there is no table cell saying "-" to fall back on.
  def shift_lead_vehicle_badge(status, label)
    case status
    when :blacklisted then ui_badge("#{label} -BL-", :error, icon: "ban", title: "Vehicle blacklisted")
    when :yes then ui_badge(label, :success, icon: "check")
    else ui_badge("No #{label}", :secondary, icon: "xmark")
    end
  end

  # The clock window one roster row covers, in the phone card and on paper where
  # there is no room for a column each. The arrows mean what they mean in the
  # table: a shift reaching past the day it is listed under.
  def shift_lead_window(ranger)
    return "#{shift_lead_time(ranger.on_duty)} (#{hour_minute_format(ranger.duration)})" if ranger.on_duty

    "#{"<" if ranger.begins_day_before}#{shift_lead_time(ranger.begins)} - " \
      "#{shift_lead_time(ranger.ends)}#{">" if ranger.ends_day_after}"
  end

  # The six headline numbers, in the order the shift lead reads them. Shared by
  # the status band and the print sheet so the two cannot drift apart.
  #
  # The dirt roster is Dirt, Pre/Post, Shiny Penny AND the Green Dot lines, so
  # the dirt and Green Dot counts overlap and a reader who adds them
  # double-counts. The page says so in its About This Report card -- upstream
  # says it in a sentence for the same reason -- and not as "Dirt Rangers,
  # including" on the first tile: that label wrapped onto a third line and every
  # tile grew to match it. The print sheet does not say it.
  def shift_lead_headline_numbers(report)
    [
      [report.dirt.size, "Dirt Rangers", :secondary],
      [report.green_dot_total, "Green Dots", report.green_dot_total.positive? ? :success : :secondary],
      [report.green_dot_females, "Female Green Dots", report.green_dot_females.positive? ? :success : :secondary],
      [report.command.size, "Command Staff", :secondary],
      [report.special.size, "Special Teams", :secondary],
      [report.below_min.size, "Below Minimum", report.fully_staffed? ? :success : :warning]
    ]
  end

  # What the report is reporting on, said in one line above the rosters.
  def shift_lead_mode_summary(report)
    if report.on_duty?
      return safe_join([tag.span("ON DUTY", class: "font-bold text-error"), " as of ",
                        full_datetime_format(report.shift_start)])
    end

    safe_join([tag.span("SCHEDULED", class: "font-bold text-success"), " for ",
               full_datetime_format(report.shift_start)])
  end

  # The last two roster columns, which are the one place the two flavours of the
  # report differ.
  def shift_lead_roster_headings(on_duty) = on_duty ? ["On Duty", "Duration"] : ["Shift Start", "Shift Ends"]

  # Sign-ups are counted per roster, so a roster's own heading says how many --
  # and, while a filter is narrowing it, how many of how many. NONE is reserved
  # for a roster that is genuinely empty; a roster filtered down to no one says
  # "0 of 35" instead, because those two want different things done about them.
  def shift_lead_roster_count(rangers, on_duty, total: nil)
    total ||= rangers.size
    return "none" if total.zero?

    shown = (rangers.size == total) ? pluralize(rangers.size, "person") : "#{rangers.size} of #{total}"

    "#{shown} #{on_duty ? "on duty" : "scheduled"}"
  end
end
