# frozen_string_literal: true

module Training::AllNotesHelper
  FILTER_CHIP_LABELS = { standing: "Standing", notes: "Showing" }.freeze

  # Where a person stands with the ART. Veteran is the settled majority, so it
  # reads as plain context; mentee is the group being actively evaluated;
  # prospective is the one worth a second look.
  STANDING_VARIANTS = {
    Training::TraineeNotesReport::STANDING_VETERAN => :secondary,
    Training::TraineeNotesReport::STANDING_MENTEE => :primary,
    Training::TraineeNotesReport::STANDING_PROSPECTIVE => :warning
  }.freeze

  def all_notes_standing_badge(standing)
    ui_badge standing, STANDING_VARIANTS.fetch(standing, :secondary)
  end

  # The app already has one rank chip (IntakeHelper#intake_rank_badge), and it
  # already renders this very column -- trainee_status.rank -- on the person and
  # VC unified-flagging pages. It is reused rather than restated so a rank means
  # the same thing, and carries the same icon, everywhere.
  #
  # Its "No Rank" badge is swapped for a dash here: 63 of 2026's 234 rows carry
  # no rank, and a badge on each of them is louder than the fact deserves in a
  # dense table.
  # nowrap: "Rank 1/Green" breaks mid-pill in a column this narrow.
  def all_notes_rank_badge(rank)
    return tag.span("—", class: "text-stone-muted") unless rank

    tag.span(intake_rank_badge(rank), class: "whitespace-nowrap")
  end

  # Standing choices carry their counts so the reader can see the shape of the
  # list before narrowing it. A standing no one holds is left out -- a choice
  # that can only return nothing is noise.
  def all_notes_standing_options(standing_counts)
    [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
      Training::TraineeNotesReport::STANDINGS.filter_map do |standing|
        count = standing_counts.fetch(standing, 0)
        ["#{standing.capitalize} (#{count})", standing] if count.positive?
      end
  end

  def all_notes_filter_chips(filter_params, slug, year)
    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS,
                 value_label: method(:all_notes_chip_value)) do |remaining|
      training_all_notes_path(slug, **remaining, year:)
    end
  end

  # Chips echo the words the page uses, not the raw param value.
  def all_notes_chip_value(key, value)
    case key
    when :standing then value.capitalize
    when :notes then "people with notes"
    else value
    end
  end
end
