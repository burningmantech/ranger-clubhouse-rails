# frozen_string_literal: true

# Everyone the intake teams touched during a year -- a note, a rank, a raised
# Personnel flag, or a bonk -- whatever their status. Ember has no such page:
# /vc/unified-flagging reads the year's Prospectives and Alphas carrying an
# adverse mark, so a Personnel note on a twenty-year Ranger, or a trainer's note
# on a returning one, reaches no page but the person's own. This one lists them
# all, for an Admin, with the ranks, flags and notes beside each name.
#
# UnifiedFlaggingConcern carries the review pane; this class supplies the roster
# (Intake.retrieve_recorded_for_year), two year-exact filters, the export, and
# says no to writing: it is a report, and notes are filed from the person page
# or from VC's copy, so no origin token is needed either.
class People::UnifiedFlaggingController < ApplicationController
  include UnifiedFlaggingConcern
  include CsvExportConcern

  layout "people"

  # Trainer notes reach further back than the intake teams': In-Person
  # Training's copy of the pipeline starts at 2008, the VC copy at 2010. Also
  # the selector's first year.
  self.year_floor = 2008

  before_action :setup_year

  authorize_role [Role::ADMIN], message: "Admin role required to view unified flagging."

  ANY_FILTER = People::UnifiedFlaggingHelper::ANY_FILTER

  # The list and the export read the same rows in the same order: the roster
  # comes by callsign, one list rather than the pipeline pages' severity
  # sections, which opened the page on the flagged few with the hundreds
  # under "Everyone else" out of sight below them.
  def index
    summaries = unified_flagging_index_summaries(section_filter: true)

    respond_to do |format|
      format.html { review_page(summaries) }
      format.csv { send_csv(csv_rows(summaries), filename: "#{@year}-unified-flagging.csv") }
    end
  end

  private

  # The page, or only its review pane when a line asked for that. Both read
  # the selection; the export reads neither, so it loads no one's history.
  def review_page(summaries)
    review_selection(summaries)
    return render_review_pane if review_pane_request?

    @rows = summaries
    # Counted before filtering, as the shared index does: a tile's count must
    # not drop to zero the moment another tile is chosen.
    @group_counts = unified_flagging_summaries.map { |summary| summary[:group] }.tally
  end

  # Memoized because #index reads it twice -- once through the filters, once
  # for the unfiltered tile counts. A line's pane request reads only the
  # person it names; the filters still run on them, so one they hide still
  # selects nothing.
  def unified_flagging_summaries
    @unified_flagging_summaries ||= Intake.retrieve_recorded_for_year(@year, person_ids: pane_person_ids)
  end

  def pane_person_ids
    [params[:person].to_s.to_i] if review_pane_request?
  end

  # The shared groups, with the third worded for this roster.
  def unified_flagging_group_meta
    People::UnifiedFlaggingHelper::GROUP_META
  end

  # The two dimensions this page adds. known_filter is a module_function; the
  # controller does not include the helper, so it is called qualified, as the
  # concern does.
  def unified_flagging_filter_params
    super.merge(
      rank: UiComponents::FilterBarHelper.known_filter(params[:rank],
                                                       People::UnifiedFlaggingHelper::RANK_FILTER_LABELS.keys),
      notes: UiComponents::FilterBarHelper.known_filter(params[:notes],
                                                        People::UnifiedFlaggingHelper::NOTES_FILTER_LABELS.keys)
    )
  end

  # Both select on the selected year's facts -- what lists the person -- and
  # not on the latest-to-date ranks the lines show, which is what
  # /mentoring/potential-alphas filters by: this page's question is what
  # happened in the year.
  def apply_unified_flagging_filters(summaries)
    rank, notes = @filter_params.values_at(:rank, :notes)

    super.select { |summary| rank_recorded?(summary, rank) && notes_written?(summary, notes) }
  end

  def rank_recorded?(summary, rank)
    return true if rank == ALL_FILTER

    ranks = summary[:year_ranks].values.flatten
    rank == ANY_FILTER ? ranks.any? : ranks.include?(rank.to_i)
  end

  def notes_written?(summary, team)
    return true if team == ALL_FILTER

    teams = summary[:year_notes].map { |entry| entry[:team] }
    team == ANY_FILTER ? teams.any? : teams.include?(team)
  end

  # One row per person shown, in page order, with the selected year's facts
  # only -- the lines and the pane read the latest-to-date ones, which the
  # person page carries too. A rank cell holds every rank the team gave that
  # year (a retake year's Training gives two), and the Training cell is blank
  # for whoever training does not concern.
  def csv_rows(summaries)
    summaries.each_with_object([csv_header]) do |summary, rows|
      person = summary[:person]
      ranks = summary[:year_ranks]
      rows << [person.callsign, "#{person.first_name} #{person.last_name}", person.status,
               csv_yes_no(summary[:personnel_issue]),
               *Intake::TEAM_ORDER.map { |team| ranks[team]&.join(", ") },
               summary[:year_bonk], summary[:training_status],
               helpers.intake_notes_text(summary[:year_notes])]
    end
  end

  # The rank columns are named and ordered from the same list the cells are.
  def csv_header
    ["Callsign", "Name", "Status", "Personnel Flag",
     *Intake::TEAM_ORDER.map { |team| "#{helpers.intake_team_chip_label(team)} Rank" },
     "Bonk", "Training", "Notes From"]
  end

  def unified_flagging_path(**params)
    people_unified_flagging_path(**params)
  end

  # A report: the pane shows each history with no Add, Edit or Delete, and
  # nothing here can open a note form, so no origin token is needed either.
  def unified_flagging_read_only?
    true
  end

  def unified_flagging_origin
    {}
  end
end
