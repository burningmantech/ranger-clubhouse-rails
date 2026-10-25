# frozen_string_literal: true

# Sections, filter facets and the two row chips for
# /mentoring/post-season-summary. The lead chip, the gray line and the search
# filter it renders are the shared pipeline ones and stay in UnifiedFlaggingHelper;
# only what the Mentors concluded is this page's own.
module Mentoring::PostSeasonSummaryHelper
  ALL_FILTER_OPTION = UiComponents::FilterBarHelper::ALL_FILTER_OPTION

  # This page's additions to the review pane: the Alpha-shift and verdict chips
  # beside the lead chip, and the mentors line. One home, because both the page
  # and the pane's own frame response (UnifiedFlaggingConcern#render_review_pane)
  # render the pane.
  PANE_EXTRAS = {
    extra_chips: "mentoring/post_season_summary/row_extras",
    extra_meta: "mentoring/post_season_summary/row_extras_meta"
  }.freeze

  # Upstream's two sections, in render order. The split is the mentor verdict
  # alone -- see the controller's #section_of for why it is not Intake's
  # severity groups.
  SECTIONS = {
    flagged: { title: "Bonked or Mentor Rank 3/4", icon: "bell", badge_color: :warning,
               empty: "No one bonked or was ranked 3 or 4 by the Mentors." },
    other: { title: "Other Mentees", icon: "user-group", badge_color: :secondary,
             empty: "Everyone in this class bonked or was ranked 3 or 4." }
  }.freeze

  # One entry per select in the filter bar, each `param => { chip label, values }`.
  # The controller iterates the keys to apply them and this file iterates the
  # same keys to render them, so a facet can never be applied but not offered.
  FACETS = {
    # The two sections above, so the "Bonked or ranked 3/4" stat tile has a
    # filter to send; the select offers the same two values.
    section: {
      label: "Section",
      values: SECTIONS.transform_keys(&:to_s).transform_values { |meta| meta[:title] }
    },
    # "Alpha shift", not "Sign-up": the shared row's gray line already says
    # "No training sign-up", so an unqualified "sign-up" here would be ambiguous.
    # "Signed up" includes those who went on to walk, as upstream has it.
    signup: {
      label: "Alpha shift",
      values: { "none" => "No sign-up", "signed-up" => "Signed up", "walked" => "Walked" }
    },
    outcome: {
      label: "Outcome",
      values: {
        PersonMentor::STATUS_BONK => "Bonked",
        PersonMentor::STATUS_SELF_BONK => "Self-bonked",
        "uber-bonk" => "Uber-bonked"
      }
    },
    rank: {
      label: "Mentor rank",
      values: { "none" => "No rank", "1" => "Rank 1", "2" => "Rank 2", "3" => "Rank 3", "4" => "Rank 4" }
    },
    notes: {
      label: "Mentor notes",
      values: { "any" => "Has notes", "none" => "No notes" }
    },
    # No :values entry -- the mentor ids are data, not a fixed set. Options
    # come from the roster via post_season_mentor_filter_options and chip
    # labels from the controller's @mentor_labels hash.
    mentor: { label: "Mentor" }
  }.freeze

  # The concern's search field plus this page's five, so every active filter
  # gets a chip that names it.
  FILTER_CHIP_LABELS = { q: "Search" }.merge(FACETS.transform_values { |facet| facet[:label] }).freeze

  # Why this section is empty. A filter hiding everyone must not be reported as
  # a fact about the class -- "Everyone in this class bonked" is a very
  # different claim from "your filters hid them".
  def post_season_empty_message(section_key, filtering:)
    return "No one matched those filters." if filtering

    SECTIONS.dig(section_key, :empty)
  end

  def post_season_facet_options(facet)
    [ALL_FILTER_OPTION, *FACETS.fetch(facet)[:values].map { |value, label| [label, value] }]
  end

  # `mentor_labels` is the controller's id => callsign hash, already
  # callsign-ordered; f.select wants [label, value] pairs. Named for the shared
  # helper's `unified_flagging_*_filter_options`, which does the same job.
  def post_season_mentor_filter_options(mentor_labels)
    [ALL_FILTER_OPTION, *mentor_labels.map { |id, callsign| [callsign, id] }]
  end

  # Every chip keeps the year: it is page state rather than a filter, so
  # removing "Outcome: Bonked" must not also throw the reader back to this
  # year. URLs go through the concern's unified_flagging_path hook -- the same
  # place the detail frames get theirs -- so a routing change cannot move the
  # frames while the chips keep pointing at the old URL.
  def post_season_filter_chips(filter_params, year, mentor_labels)
    active = active_filters(filter_params)
    display = lambda do |key, value|
      next mentor_labels.fetch(value, value) if key == :mentor

      FACETS.dig(key, :values)&.fetch(value, nil) || value
    end

    filter_chips(active, FILTER_CHIP_LABELS, value_label: display) do |remaining|
      unified_flagging_path(**remaining, year:)
    end
  end

  # The three Alpha-shift states, which together say whether somebody actually
  # showed up for the shift they booked.
  #
  # Upstream's shipped ALPHA_STATES paints "no sign-up" and "signed up, didn't
  # walk" both amber, leaving the two states indistinguishable; its own spec
  # (PLAN-2 section 3) says the first should be red. Fixed here. Each chip
  # carries an icon as well as a color, so the state does not rest on color
  # alone.
  # "No Alpha sign-up" spells out which sign-up it means: the shared row's gray
  # line beside it can read "No training sign-up".
  # `text_class` is the same state as a word on the review list's line, where
  # walking -- the expected outcome -- carries no colour.
  SIGNUP_CHIPS = {
    none: { label: "No Alpha sign-up", variant: :error, icon: "calendar-xmark", text_class: "text-error" },
    booked: { label: "Signed up, did not walk", variant: :warning, icon: "calendar-day", text_class: "text-warning" },
    walked: { label: "Walked a shift", variant: :success, icon: "person-walking" }
  }.freeze

  # The single definition of "walked". Upstream resolved it as signed up AND
  # assigned mentors; here the mentors dominate: an assigned walk IS the
  # walked signal, so a walker whose sign-up row has since gone (a past
  # year's Alpha slots bulk-deleted, a walk-up recorded straight onto the
  # Mentor Assignments worksheet) does not chip error-red "No Alpha sign-up"
  # beside a recorded pass. Deliberately not the live on-duty flag, which
  # says nothing once the season is over. The controller reads it too (for
  # the stat box and the Sign-up filter), so the chip and the count can never
  # disagree.
  def post_season_signup_state(summary)
    return :walked if summary[:mentors].any?

    summary[:signed_up] ? :booked : :none
  end

  def post_season_signup_chip(summary)
    chip = SIGNUP_CHIPS.fetch(post_season_signup_state(summary))

    ui_badge chip[:label], chip[:variant], icon: chip[:icon], icon_type: :solid
  end

  # The same state as a word with an icon, for the review list's one line.
  def post_season_signup_text(summary)
    chip = SIGNUP_CHIPS.fetch(post_season_signup_state(summary))

    tag.span(class: class_names("whitespace-nowrap", chip[:text_class])) do
      safe_join([fa_icon(chip[:icon], :solid, end: 1), chip[:label]])
    end
  end

  # Only the pass is chipped here. A bonk of either kind is already the shared
  # row's lead chip (or on its gray line when a Personnel flag or an uber-bonk
  # outranks it), and "pending" on a finished season
  # means no verdict was ever recorded -- which the sign-up chip beside it
  # explains better than a chip of its own would.
  def post_season_verdict_chip(summary)
    return unless summary[:mentor_status] == PersonMentor::STATUS_PASS

    ui_badge "Passed", :success, icon: "circle-check", icon_type: :solid
  end

  # The four tiles over the class, each with the filter that narrows the class
  # to what it counts; the Mentees tile sends none and so clears them. A tile's
  # URL and its ring both read `filter`, so the two cannot drift apart.
  def post_season_stat_tiles(mentees:, walked:, flagged:, no_signup:)
    [
      { count: mentees, label: "Mentees", icon: "user-group", filter: {} },
      { count: walked, label: "Walked a shift", icon: "person-walking", variant: :success,
        filter: { signup: "walked" } },
      { count: flagged, label: "Bonked or ranked 3/4", icon: "bell",
        variant: flagged.positive? ? :warning : :success, filter: { section: "flagged" } },
      { count: no_signup, label: "No Alpha sign-up", icon: "calendar-xmark",
        variant: no_signup.positive? ? :error : :success, filter: { signup: "none" } }
    ]
  end
end
