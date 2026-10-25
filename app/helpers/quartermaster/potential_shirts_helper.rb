# frozen_string_literal: true

module Quartermaster::PotentialShirtsHelper
  # Shirt-kind labels come from ShirtTotals so a chip and its order lines can
  # only ever call the same shirt the same thing.
  FILTER_CHIP_LABELS = ShirtTotals::KINDS.to_h { |kind| [kind[:param], kind[:name]] }
                                         .merge(earned: "Earned", missing: "Missing a size")
                                         .freeze

  # Chip and clear URLs must carry the year: this page is year-scoped, and a
  # URL without it would silently snap the report back to the current year.
  def potential_shirts_filter_chips(filter_params, year)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:potential_shirts_chip_value)) do |remaining|
      quartermaster_potential_shirts_path(**remaining, year:)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def potential_shirts_chip_value(key, value)
    case key
    when :earned then potential_shirts_earned_labels.fetch(value, value)
    when :missing then "Yes"
    else value
    end
  end

  def potential_shirts_earned_options
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      potential_shirts_earned_labels.map { |value, label| [label, value] }
  end

  # One choice per title actually held, with how many people hold it, in the
  # same run order the order lines print. A carried-over filter for a title
  # no one holds this year is appended rather than dropped: the select must
  # not read "All" while the filter is still narrowing the roster.
  def potential_shirts_title_options(kind, selected)
    options = kind.lines.map { |line| ["#{line.title} (#{line.earned + line.pending})", line.title] }

    if selected != UiComponents::FilterBarHelper::ALL_FILTER &&
       options.none? { |_label, value| value == selected }
      options << ["#{selected} (0)", selected]
    end

    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] + options
  end

  # A roster shirt cell: the full title, prefixed with a "Not earned" badge
  # while the person is short of that shirt's threshold. The badge carries the
  # words, not just the colour.
  def potential_shirts_shirt_cell(row, kind)
    title = shirt_size_label(row.person, kind.reader)
    return title if row.public_send(PotentialShirtsReport::EARNED_FLAG.fetch(kind.param))

    safe_join([ui_badge("Not earned", :error, size: "xs"), title], " ")
  end

  private

  # Built at call time, not module load: a helper naming a controller constant
  # while the module loads deadlocks both autoloads (controllers include every
  # helper, so the reference runs mid-cycle).
  def potential_shirts_earned_labels
    { Quartermaster::PotentialShirtsController::EARNED_T_SHIRT => "T-shirt",
      Quartermaster::PotentialShirtsController::EARNED_LONG_SLEEVE => "Long sleeve",
      Quartermaster::PotentialShirtsController::EARNED_NONE => "Nothing yet" }
  end
end
