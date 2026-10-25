# frozen_string_literal: true

# Prospectives and Alphas -- and, on one page, anyone the intake teams wrote
# about -- with the ranks, flags and notes left by the five intake teams.
# Seven pages share it:
#   /vc/unified-flagging                      -- writable, year-scoped
#   /training/in-person/unified-flagging      -- read-only (trainingNotesOnly),
#                                                carried by #unified_flagging_read_only?
#   /mentoring/potential-alphas               -- writable, current standing, its
#                                                own #index (it splits by cohort first)
#   /mentoring/alpha-status                   -- read-only, its own #index
#   /mentoring/post-season-summary            -- writable, year-scoped, its own #index
#   /mentoring/convert-prospectives           -- writable, current standing, and
#                                                the loosest consumer: it uses
#                                                the detail frame and the note
#                                                controls, but renders its own
#                                                table, so it supplies no
#                                                #unified_flagging_path
#   /people/unified-flagging                  -- read-only, year-scoped, anyone
#                                                with something recorded that
#                                                year; its own #index
# The first four were one Ember <UnifiedFlagging> component upstream.
#
# The review pane loads one person's history through #index itself (see
# #review_pane_request?); #detail renders it into the Convert Prospectives
# table's lazily-loaded frame.
#
# Templates live in app/views/common/unified_flagging/ and are rendered by
# path from here rather than through per-controller stubs -- #index and #detail
# are read-only GETs owned entirely by this concern, so there is no
# `render :index` re-render path that would need the controller's own view
# prefixes (QualificationsConcern and WorkHistoryConcern take the same shape).
# A controller that supplies its own #index renders its own template and calls
# #unified_flagging_index_summaries for the filtering and counts.
#
# An including controller must supply:
#   unified_flagging_path(**params)         -- the index URL
#   unified_flagging_read_only?                 -- true hides every note control
#   unified_flagging_origin                     -- note-CRUD return token, or {}
#   unified_flagging_detail_path(person, **params) -- one person's #detail URL,
#                                                  only on a page that renders
#                                                  _detail_frame
#
# The year selector's earliest year is the controller's year_floor, which
# setup_year also holds ?year= to.
#
# and may override (each documented at its definition below -- change their
# signatures with every consumer in hand):
#   unified_flagging_summaries                  -- the roster; default is the year's pipeline
#   unified_flagging_filter_params              -- add a filter dimension (call super)
#   apply_unified_flagging_filters              -- apply it (call super)
#   unified_flagging_group_meta                 -- the groups' titles; default UnifiedFlaggingHelper::GROUP_META
module UnifiedFlaggingConcern
  extend ActiveSupport::Concern

  # The filter-bar convention: "all" means the filter is inactive. Aliased from
  # the helper that owns the sentinel so callers read short.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  included do
    helper_method :unified_flagging_path, :unified_flagging_detail_path,
                  :unified_flagging_read_only?, :unified_flagging_origin,
                  :unified_flagging_writable_teams, :unified_flagging_group_meta
  end

  def index
    summaries = unified_flagging_index_summaries(section_filter: true)
    review_selection(summaries)
    return render_review_pane if review_pane_request?

    @groups = summaries.group_by { |summary| summary[:group] }
    # Counted before filtering: the stat tiles describe the pipeline and are
    # also the controls that narrow it, so one tile's count must not drop to
    # zero the moment another tile is chosen.
    @group_counts = unified_flagging_summaries.map { |summary| summary[:group] }.tally

    render "common/unified_flagging/index"
  end

  def detail
    @person = Person.find(params[:person_id])
    @history = Intake.history_for_person(@person, @year)

    render "common/unified_flagging/detail", layout: false
  end

  private

  # The filter-and-count half of an index action, shared by the pages that
  # group the result differently: this concern's own #index groups by severity,
  # while /mentoring/potential-alphas splits by cohort first. Sets
  # @filter_params, @filtering, @total, @shown and @personnel_flagged; returns
  # the surviving summaries.
  #
  # `section_filter` reads ?section= as Intake's display group, which only the
  # shared #index offers, through its stat tiles and its Section select. It is
  # read AND applied here, under that one switch, never in the overridable
  # #apply_unified_flagging_filters: Post Season Summary keeps a `section` facet
  # of its own (its Mentors' verdict) in the same key, and applying Intake's
  # groups there too hid people its own tile counted.
  def unified_flagging_index_summaries(section_filter: false)
    @filter_params = unified_flagging_filter_params
    if section_filter
      @filter_params[:section] = UiComponents::FilterBarHelper.known_filter(params[:section],
                                                                            unified_flagging_group_meta.keys.map(&:to_s))
    end
    @filtering = UiComponents::FilterBarHelper.active_filters(@filter_params).any?

    roster = unified_flagging_summaries
    @total = roster.size

    summaries = apply_unified_flagging_filters(roster)
    if section_filter && @filter_params[:section] != ALL_FILTER
      summaries = summaries.select { |summary| summary[:group].to_s == @filter_params[:section] }
    end
    @shown = summaries.size
    # One warning for the page names whoever on it carries a raised Personnel
    # flag; their lines keep a red tint and the lead chip, and the review pane
    # repeats the warning beside the note controls. Read off the rows
    # shown, so a filter that hides a flagged person hides the warning about
    # them too, and a search that finds them brings it back.
    @personnel_flagged = summaries.select { |summary| summary[:personnel_issue] }
                                  .map { |summary| summary[:person].callsign }
    summaries
  end

  # The person the review pane shows: ?person= when it names a row on screen.
  # Only the rows shown, so a stale link, a hand-typed id, or a person the
  # filters hide selects nothing and the pane shows its empty state. to_s on
  # the param, because ?person[]=1 arrives as an Array.
  def review_selection(summaries)
    @selected = summaries.find { |summary| summary[:person].id.to_s == params[:person].to_s }
    return unless @selected

    @selected_id = @selected[:person].id
    @history = Intake.history_for_person(@selected[:person], @year)
  end

  # A line's link loads the review pane's own frame (Turbo-Frame: uf-pane).
  # Nothing outside the pane changes for that, so the response is the pane
  # alone -- no list, no tiles, no layout -- rather than the whole page for
  # Turbo to throw away. A page with extras for its pane passes them in.
  # Only for HTML: an export URL that arrives with the header gets its file.
  def review_pane_request?
    request.format.html? && turbo_frame_request_id == "uf-pane"
  end

  def render_review_pane(**extras)
    render partial: "common/unified_flagging/review_pane",
           locals: { summary: @selected, history: @history, year: @year, **extras }
  end

  # The roster this page reports on, memoized because #index reads it twice --
  # once through the filter, once for the unfiltered tile counts. Overridden by
  # the mentoring pages, which report on a different roster and memoize it
  # the same way.
  def unified_flagging_summaries
    @unified_flagging_summaries ||= Intake.retrieve_all_for_year(@year)
  end

  # known_filter, as ?section= gets: a stale or mistyped ?training= reads as
  # every cohort rather than none, and a hand-made nested value never reaches
  # the chips' and lines' URLs, which raised on it.
  def unified_flagging_filter_params
    filters = { q: params[:q].to_s.strip }
    if unified_flagging_training_filter?
      filters[:training] = UiComponents::FilterBarHelper.known_filter(params[:training],
                                                                      UnifiedFlaggingHelper::TRAINING_FILTER_LABELS.keys)
    end
    filters
  end

  # Whether this page offers the training filter. A page that answers false
  # neither reads ?training= nor applies it -- the post-season page opts out
  # because whether someone made it to training is a pre-season question. An
  # opt-out hook rather than each consumer pinning `training: ALL_FILTER`,
  # which silently filters out EVERY row the moment an override forgets it.
  def unified_flagging_training_filter?
    true
  end

  # Filtering runs over the already-loaded summaries: the roster query is a
  # fixed cost either way, and the alternative is threading predicates through
  # five joined sources for a list this size.
  def apply_unified_flagging_filters(summaries)
    query = @filter_params[:q].downcase
    # The `|| ALL_FILTER` backstops a page that opted out of the filter (no
    # :training key at all) so a missing key reads as inactive, never as
    # "matches nothing".
    training = @filter_params[:training] || ALL_FILTER

    summaries.select do |summary|
      (query.blank? || unified_flagging_matches_query?(summary[:person], query)) &&
        (training == ALL_FILTER || summary[:training_status] == training)
    end
  end

  # Old handles are searched too -- looking someone up by the name you last
  # knew them under is the whole point of keeping FKAs.
  def unified_flagging_matches_query?(person, query)
    return true if [person.callsign, person.first_name, person.last_name]
                   .any? { |value| value.to_s.downcase.include?(query) }

    person.person_fka.any? { |fka| fka.fka.to_s.downcase.include?(query) }
  end

  # The display groups' titles, icons and colours, keyed by Intake's groups,
  # for the stat tiles, the Section select and its chips. A page that words a
  # group differently answers its own map with the same keys: ?section= takes
  # Intake's groups whatever the titles say.
  def unified_flagging_group_meta
    UnifiedFlaggingHelper::GROUP_META
  end

  # Which teams this viewer may file notes for on this page. Read-only pages
  # answer "none" regardless of role, which is what removes the Add/Edit/Delete
  # controls -- Person::IntakeNotesController re-checks server-side anyway.
  def unified_flagging_writable_teams
    return [] if unified_flagging_read_only?

    Intake::TEAM_TYPES.select { |team_key| helpers.can_write_intake_notes?(team_key) }
  end
end
