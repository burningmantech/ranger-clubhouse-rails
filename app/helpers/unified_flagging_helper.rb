# frozen_string_literal: true

# Presentation constants, filter-bar options and chips for the unified flagging
# pipeline pages (/vc and In-Person Training). The controllers share
# UnifiedFlaggingConcern; the URL each chip rebuilds comes from that concern's
# unified_flagging_path hook, so this file stays namespace-free.
module UnifiedFlaggingHelper
  # One entry per Intake group, in render order, and what
  # UnifiedFlaggingConcern#unified_flagging_group_meta answers unless a page
  # words its groups differently. stat_variant must be a
  # UiStatBoxHelper::STAT_VARIANTS key and badge_color a ui_section one --
  # ui_section raises without a badge_color, and an unknown stat variant falls
  # back to :secondary.
  GROUP_META = {
    personnel: { title: "Personnel Flag Raised", icon: "flag", badge_color: :error, stat_variant: :warning },
    flagged: { title: "Rank 3/4 or Bonk", icon: "bell", badge_color: :warning, stat_variant: :warning },
    other: { title: "Other Potential Alphas", icon: "user-group", badge_color: :secondary, stat_variant: :secondary }
  }.freeze

  FILTER_CHIP_LABELS = {
    q: "Search",
    training: "Training",
    section: "Section",
    flagged: "Flagged by"
  }.freeze

  # The element a row's Details button shows and hides. One home for the id
  # because three files depend on it agreeing: the button's toggle target, the
  # table row /mentoring/convert-prospectives wraps it in, and _detail_frame
  # inside it.
  def uf_detail_id(person)
    "uf-detail-#{person.id}"
  end

  TRAINING_FILTER_LABELS = {
    "trained" => "Trained",
    "not passed" => "Not passed",
    "pending" => "Pending",
    "none" => "No sign-up"
  }.freeze

  # Values the "Flagged by" filter offers, which only
  # /mentoring/potential-alphas renders -- the other two pipeline pages never
  # put `flagged` in their filter params, so this simply goes unused there.
  #
  # The teams and their labels come from IntakeHelper::TEAM_META so a renamed
  # or added team reaches the filter on its own. Two entries can't: Personnel
  # reads "Personnel flag" because the filter selects on the raised flag rather
  # than on that team having filed anything, and "bonk" is a mentor verdict, not
  # a team at all.
  FLAGGED_FILTER_OVERRIDES = { "personnel" => "Personnel flag" }.freeze
  FLAGGED_FILTER_EXTRAS = { "bonk" => "Bonked" }.freeze

  def flagged_filter_labels
    IntakeHelper::TEAM_META.keys
                           .index_with { |team| FLAGGED_FILTER_OVERRIDES[team] || intake_team_label(team) }
                           .merge(FLAGGED_FILTER_EXTRAS)
  end

  # The ?section= tokens the stat tiles and the Section select send --
  # Intake's display groups -- labelled with the page's group titles, so a
  # chip, an option and a heading read the same.
  def unified_flagging_section_labels
    unified_flagging_group_meta.to_h { |group, meta| [group.to_s, meta[:title]] }
  end

  def unified_flagging_training_filter_options
    filter_select_options(TRAINING_FILTER_LABELS)
  end

  def unified_flagging_flagged_filter_options
    filter_select_options(flagged_filter_labels)
  end

  def unified_flagging_section_filter_options
    filter_select_options(unified_flagging_section_labels)
  end

  # One chip per active filter; each chip's URL drops that filter and keeps the
  # rest -- plus the year where the page has one, since that is page state
  # rather than a filter and must survive every chip. The mentoring page passes
  # no year: it reports on current standing and has no year to preserve. A
  # page with filters of its own passes their chip labels (`labels:`) and the
  # words for their values (`value_labels:`).
  def unified_flagging_filter_chips(filter_params, year = nil, labels: {}, value_labels: {})
    values = { training: TRAINING_FILTER_LABELS, flagged: flagged_filter_labels,
               section: unified_flagging_section_labels, **value_labels }
    display = ->(key, value) { values.fetch(key, {}).fetch(value, value) }

    filter_chips(active_filters(filter_params), FILTER_CHIP_LABELS.merge(labels), value_label: display) do |remaining|
      unified_flagging_path(**remaining, year:)
    end
  end
end
