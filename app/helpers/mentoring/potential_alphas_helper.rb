# frozen_string_literal: true

# Section registry for /mentoring/potential-alphas. The rank chips, filter
# options and note pills it renders are the shared pipeline ones and stay in
# UnifiedFlaggingHelper; only the sectioning is this page's own.
module Mentoring::PotentialAlphasHelper
  # "With issues" means a Personnel flag or a current rank 3/4 or bonk -- the
  # two severity groups, as opposed to Intake's :other. Named once so the
  # sections, their badges and the stat boxes can never disagree about who
  # counts.
  ISSUE_GROUPS = %i[personnel flagged].freeze
  CLEAR_GROUPS = %i[other].freeze

  # Each cohort declares its own labels; SECTIONS composes them below, so a
  # title is written once and the stat box above the sections reuses it.
  COHORTS = {
    prospective: {
      title: "Prospectives", icon: "user-group",
      empty: "No one currently holds Prospective status.",
      issue_title: "Prospectives with Issues",
      issue_empty: "No Prospective has a flag or a rank of 3 or 4.",
      clear_title: "Prospectives Without Issues",
      clear_empty: "Every Prospective has something raised against them."
    },
    alpha: {
      title: "Current Alphas", icon: "seedling",
      empty: "No one has been made an Alpha yet.",
      issue_title: "Alphas with Issues",
      issue_empty: "No Alpha has a flag or a rank of 3 or 4.",
      clear_title: "Alphas Without Issues",
      clear_empty: "Every Alpha has something raised against them."
    }
  }.freeze

  # Four sections: each cohort split by whether anything has been raised
  # against the person, so the people needing a decision are never mixed in
  # with the people who don't.
  #
  # The with-issues sections keep the severity subheadings -- a Personnel flag
  # quarantines someone and a rank 3/4 does not, and that difference decides
  # what a mentor does next. The without-issues sections have nothing to
  # subdivide, so they render flat.
  SECTIONS = COHORTS.flat_map do |cohort, meta|
    [
      { cohort:, groups: ISSUE_GROUPS, title: meta[:issue_title], empty: meta[:issue_empty],
        icon: "triangle-exclamation", badge_color: :warning },
      { cohort:, groups: CLEAR_GROUPS, title: meta[:clear_title], empty: meta[:clear_empty],
        icon: "circle-check", badge_color: :secondary }
    ]
  end.freeze

  # Why this section is empty, in the order the reasons override each other:
  # the filters hid everyone, no one holds the status at all, or the cohort is
  # simply all on one side of the split.
  def potential_alpha_empty_message(section, filtering:, cohort_total:)
    return "No #{section[:title].downcase} matched those filters." if filtering
    return COHORTS.dig(section[:cohort], :empty) if cohort_total.zero?

    section[:empty]
  end
end
