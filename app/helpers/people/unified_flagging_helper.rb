# frozen_string_literal: true

# What /people/unified-flagging adds to the pipeline pages' helpers
# (UnifiedFlaggingHelper, IntakeHelper): the wording of its third group --
# anyone the teams wrote about is listed here, not only potential Alphas --
# its two year-exact filters, and the jump list.
module People::UnifiedFlaggingHelper
  # The value a select offers for "any" -- any rank, notes from any team --
  # beside its per-value choices. Not the bar's ALL_FILTER, which means the
  # filter is off.
  ANY_FILTER = "any"

  # The shared groups, with the third retitled: on the pipeline pages it holds
  # the potential Alphas whose latest ranks are calm; here it holds everyone
  # listed who carries no current mark, whatever their status. What the
  # controller's unified_flagging_group_meta answers.
  GROUP_META = UnifiedFlaggingHelper::GROUP_META.merge(
    other: UnifiedFlaggingHelper::GROUP_META[:other].merge(title: "Everyone Else")
  ).freeze

  # A rank recorded in the selected year by any team, worded as the rank
  # chips word it.
  RANK_FILTER_LABELS = { ANY_FILTER => "Any ranking" }.merge(
    IntakeHelper::RANK_BADGE.to_h { |rank, info| [rank.to_s, info[:label].delete_prefix("Rank ")] }
  ).freeze

  # The team that wrote a note in the selected year. Training is a team here:
  # a trainer's note lists a person as any other team's does.
  NOTES_FILTER_LABELS = { ANY_FILTER => "Any team" }
                          .merge(IntakeHelper::TEAM_META.transform_values { |meta| meta[:label] }).freeze

  # What dropdown_scroll_list reads off each entry.
  ScrollItem = Struct.new(:id, :title)

  def people_unified_flagging_rank_options
    filter_select_options(RANK_FILTER_LABELS)
  end

  def people_unified_flagging_notes_options
    filter_select_options(NOTES_FILTER_LABELS)
  end

  # The shared chips, with this page's two filters named and their values
  # worded as the selects word them.
  def people_unified_flagging_filter_chips(filter_params, year)
    unified_flagging_filter_chips(filter_params, year,
                                  labels: { rank: "Ranking", notes: "Notes" },
                                  value_labels: { rank: RANK_FILTER_LABELS, notes: NOTES_FILTER_LABELS })
  end

  # One jump target per line shown, in page order, which is by callsign: the
  # reader picks a letter, then a name, and lands on that line, the `person-N`
  # id every list row carries. A blank callsign is dropped rather than listed:
  # dropdown_scroll_list buckets by the title's first letter.
  def people_unified_flagging_scroll_items(summaries)
    summaries.map { |summary| summary[:person] }
             .reject { |person| person.callsign.blank? }
             .map { |person| ScrollItem.new("person-#{person.id}", person.callsign) }
  end
end
