# frozen_string_literal: true

# Every method here is prefixed. Rails helper names share one namespace across
# the whole app, so a bare `flag_cell` would answer for every other page too.
module Scheduling::SandmanQualifiedHelper
  # The page's controller, asked for by name inside a method rather than held in
  # a constant here. Naming it while this file is being loaded starts a second
  # autoload before the first has finished, and the pair deadlock.
  def sandman_qualified_controller = Scheduling::SandmanQualifiedController

  # What each way of narrowing the list is called, in the select and on its chip.
  def sandman_qualified_show_labels
    controller_class = sandman_qualified_controller

    { controller_class::SHOW_QUALIFIED => "Qualified",
      controller_class::SHOW_UNQUALIFIED => "Not qualified",
      controller_class::SHOW_SIGNED_UP => "Signed up",
      controller_class::SHOW_SIGNED_UP_QUALIFIED => "Signed up and qualified",
      controller_class::SHOW_SIGNED_UP_UNQUALIFIED => "Signed up but not qualified",
      controller_class::SHOW_MISSING_TRAINING => "Missing training",
      controller_class::SHOW_MISSING_AFFIDAVIT => "Missing affidavit",
      controller_class::SHOW_MISSING_EXPERIENCE => "Missing experience" }
  end

  # Only the ways of narrowing that the report is actually measuring. Offering
  # a check the Clubhouse has switched off would be a choice that can only
  # return everybody.
  def sandman_qualified_show_options(report)
    controller_class = sandman_qualified_controller
    dropped = []
    dropped << controller_class::SHOW_MISSING_AFFIDAVIT unless report.affidavit_required?
    dropped << controller_class::SHOW_MISSING_EXPERIENCE unless report.experience_required?

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      sandman_qualified_show_labels.except(*dropped).map { |value, label| [label, value] }
  end

  def sandman_qualified_chips(filter_params, year)
    filter_chips(filter_params, { show: "Showing" },
                 value_label: ->(_key, value) { sandman_qualified_show_labels[value] }) do |remaining, _key|
      scheduling_sandman_qualified_path(**remaining, year:)
    end
  end

  # The scoreboard above the table: one box per requirement, plus the whole
  # roster at one end and the verdict at the other.
  #
  # A requirement box counts the people who have met it and links to the ones
  # who have not, because the shortfall is the list somebody has to act on.
  # With no one left to chase there is nothing to open, so the box carries no
  # link rather than promising an empty page.
  def sandman_qualified_scoreboard(report, year)
    controller_class = sandman_qualified_controller
    total = report.total
    qualified = report.qualified_count
    signed_up = report.signed_up_count

    [sandman_qualified_box("Sandmen", total, nil, year,
                           aria: "Show all #{total} sandmen"),
     sandman_qualified_requirement_box("Trained", report.trained_count, total,
                                       controller_class::SHOW_MISSING_TRAINING, year),
     # Only the checks the Clubhouse is asking for get a box. One counting a
     # shortfall no one has to close would send the reader chasing signatures
     # the app never blocks anyone over.
     (if report.affidavit_required?
        sandman_qualified_requirement_box("Affidavit", report.affidavit_count, total,
                                          controller_class::SHOW_MISSING_AFFIDAVIT, year)
      end),
     (if report.experience_required?
        sandman_qualified_requirement_box("Experience", report.experience_count, total,
                                          controller_class::SHOW_MISSING_EXPERIENCE, year)
      end),
     sandman_qualified_box("Signed Up", signed_up, controller_class::SHOW_SIGNED_UP, year,
                           aria: "Show the #{signed_up} signed up"),
     # The one box that changes colour, because it is the report's answer rather
     # than one of the questions behind it. It opens the people who are ready
     # while counting the ones who are not, so the reader can reach the roster
     # the page is ultimately for.
     sandman_qualified_box("Qualified", qualified, controller_class::SHOW_QUALIFIED, year,
                           variant: (:success if qualified.positive?),
                           short: total - qualified, short_label: "not ready",
                           aria: "Show the #{qualified} qualified")].compact
  end

  # The scoreboard stays one row on desktop however many boxes it holds, which
  # varies with the checks in force. Spelled as whole class names, because the
  # stylesheet is built from the names it can find written down.
  def sandman_qualified_scoreboard_columns(count)
    { 4 => "lg:grid-cols-4", 5 => "lg:grid-cols-5", 6 => "lg:grid-cols-6" }
      .fetch(count, "lg:grid-cols-6")
  end

  # Renders one scoreboard box, as a link when it has somewhere to go. The ring
  # marks the box whose filter is the one currently applied.
  def sandman_qualified_scoreboard_box(box, current_filter)
    selected = box[:filter] == current_filter
    classes = class_names("h-full", "ring-2 ring-primary" => selected)
    stat = ui_stat_box(box[:value].to_s, sandman_qualified_box_label(box),
                       variant: box[:variant], class: classes)

    return stat unless box[:url]

    ui_stat_link(box[:url], aria_label: box[:aria],
                 class: "transition-shadow duration-200 hover:ring-2 hover:ring-primary") { stat }
  end

  # Yes or no, told apart by the icon's shape as well as its colour, and spelled
  # out for anyone listening to the page rather than looking at it.
  def sandman_qualified_flag(value)
    if value
      safe_join([fa_icon("circle-check", :solid, class: "icon-success", aria: { hidden: true }),
                 tag.span("Yes", class: "sr-only")])
    else
      safe_join([fa_icon("circle-xmark", :solid, class: "text-stone-subtle", aria: { hidden: true }),
                 tag.span("No", class: "sr-only")])
    end
  end

  # The verdict for one person. What is missing is named when it is a single
  # thing and counted when it is more, since the columns beside it already spell
  # out which ones.
  def sandman_qualified_verdict(row)
    return ui_badge("Qualified", :success, class: "whitespace-nowrap") if row.qualified?

    missing = row.missing
    label = missing.one? ? "Missing #{missing.first}" : "Missing #{missing.size}"

    ui_badge(label, :warning, class: "whitespace-nowrap",
             title: "Missing #{missing.to_sentence}")
  end

  private

  # One box. `opens` is how many people the link would land on, and the box only
  # carries a link when that is more than no one -- a box promising a page with
  # nothing on it is worse than one that simply does not respond. It defaults to
  # the box's own number, which is what everything but a requirement opens.
  def sandman_qualified_box(label, value, filter, year,
                            aria:, opens: value, variant: nil, short: nil,
                            short_label: "missing")
    { label:, value:, filter:, short:, short_label:, aria:,
      variant: variant || :secondary,
      url: (scheduling_sandman_qualified_path(show: filter, year:) if opens.positive?) }
  end

  # A requirement: it counts the people who have met it and opens the ones who
  # have not, because the shortfall is the list somebody has to act on.
  def sandman_qualified_requirement_box(label, met, total, filter, year)
    short = total - met

    sandman_qualified_box(label, met, filter, year, short:, opens: short,
                          aria: "Show the #{short} missing #{label.downcase}")
  end

  # The label under a box's number, with the shortfall beneath it when there is
  # one. At nought there is nothing left to chase, so the line is left off
  # rather than printing a nought on every box.
  def sandman_qualified_box_label(box)
    short = box[:short].to_i
    return box[:label] unless short.positive?

    safe_join([box[:label],
               tag.div("#{short} #{box[:short_label]}",
                       class: "text-warning font-medium")])
  end
end
