# frozen_string_literal: true

# The status changes to consider once an event is over, and the writes that
# carry them out.
#
# The index lists the five proposed changes and how many people each covers.
# A group opens onto its own page: that group's people, a filter bar, an
# export, and the one button that changes them. One page, one change, so the
# button is always beside the only list it can act on.
#
# The page asks about the event now behind us, or the one after it, and offers
# nothing else -- a run against 2011 would be meaningless -- so it carries a
# period rather than the usual year selector.
class People::StatusChangeRecommendationsController < ApplicationController
  include CsvExportConcern

  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to review proposed status changes."

  # Named here so the controller does not have to spell the helper's full path
  # every time it tests or normalises the vintage filter.
  VINTAGE_YES = People::StatusChangeRecommendationsHelper::VINTAGE_YES
  VINTAGE_VALUES = People::StatusChangeRecommendationsHelper::VINTAGE_VALUES

  before_action :setup_period
  before_action :load_group, only: [:show, :convert]

  def index
    @counts = RecommendStatusChangeReport.counts(@year)
    @total = @counts.values.sum
  end

  def show
    load_rows

    respond_to do |format|
      format.html
      # The export is what is on screen, filters and all -- an export that
      # quietly widened back out to the whole group would be the one thing a
      # reader could not tell by looking at it.
      format.csv { send_csv(csv_rows, filename: csv_filename) }
    end
  end

  # Applies the group's change to the checked people, then re-renders the group.
  #
  # Nothing the page rendered is trusted here. The group is rebuilt from this
  # request's own period, and a checked id is kept only where it still appears
  # in it, so a stale page, a doctored form, or a person whose situation has
  # moved on since cannot reach the write.
  def convert
    # A Set, not an Array: the membership test below runs once per person in
    # the group, and nothing caps how many ids a request may carry.
    ids = IdList.parse(params.permit(person_ids: [])[:person_ids]).to_set
    return redirect_to(group_path, alert: "Check at least one person first.") if ids.empty?

    # Read once, before anything is written, and used for two things: who may
    # be changed, and what the filter bar is allowed to offer. Re-deriving the
    # choices afterwards would let a filter silently fall away the moment the
    # change stopped its rows matching -- and a filter that falls away widens
    # the list the next click acts on.
    before = RecommendStatusChangeReport.rows(@group, @year)
    @choices = filter_choices(before)

    eligible = before.select { |row| ids.include?(row.id) }
    if eligible.empty?
      return redirect_to(group_path,
                         alert: "None of the checked people are still proposed for this change.")
    end

    apply(eligible)
    load_rows(keep_ids: @converted_ids)

    # Rendered rather than redirected, for the reason the just-changed people
    # are held on the list: a plain GET cannot re-derive who was converted,
    # because the change is what took them out of the group.
    render :show, status: :unprocessable_entity
  end

  private

  # Runs the change through the shared bulk machinery, which brings the locked
  # account guard, one transaction per person, the status history row, and the
  # commit log entry with it.
  #
  # Callsigns, because that is what the machinery reads -- and they are looked
  # up here, at the last moment, rather than posted by the page. Converting to
  # past prospective replaces the callsign, so a form naming people by callsign
  # would be naming them by the very field the change rewrites.
  def apply(eligible)
    # A record is one callsign on its own line, so a callsign carrying a line
    # break or a comma would be read as two records or as a callsign plus extra
    # fields -- landing on somebody else, or on no one. Nothing stops a callsign
    # holding either character, so those rows are held back and named rather
    # than sent into the batch to fail in a way the reader cannot see.
    unusable, sendable = eligible.partition { |row| row.callsign.to_s.match?(/[,\r\n]/) }

    outcome = if sendable.any?
                BulkUpload::Batch.new(action: @group.action,
                                      records: sendable.map(&:callsign).join("\n"),
                                      reason: RecommendStatusChangeReport::REASON).apply!
              end

    @converted_ids = outcome ? outcome.changed.map { |entry| entry.person.id } : []
    # Read back after the write, not from the entry: converting an applicant
    # replaces their callsign, and the row this banner points at will be showing
    # the new one. Both are named so the two agree.
    @converted = renamings(outcome)
    @unchanged = unchanged_report(eligible, unusable)
  end

  # One line per person who was checked but not changed, saying which. The
  # verdicts the batch reaches -- a callsign that matched no one, two people
  # whose callsigns normalise alike, a write that raised -- are all different
  # problems, and a single count would tell the reader none of them.
  def unchanged_report(eligible, unusable)
    lines = unusable.map { |row| [row.callsign, "callsign holds a comma or a line break"] }
    changed = @converted_ids.to_set
    (eligible.reject { |row| changed.include?(row.id) } - unusable).each do |row|
      lines << [row.callsign, "the Clubhouse could not match this callsign to exactly one person"]
    end
    lines
  end

  # "SmithJane26 (now ShifterS26)" where the change replaced the callsign, the
  # plain callsign where it did not.
  def renamings(outcome)
    return [] unless outcome

    now = Person.where(id: @converted_ids).pluck(:id, :callsign).to_h
    outcome.changed.map do |entry|
      current = now[entry.person.id]
      current == entry.callsign ? entry.callsign : "#{entry.callsign} (now #{current})"
    end
  end

  def load_rows(keep_ids: [])
    @converted ||= []
    @converted_ids ||= []
    @unchanged ||= []

    @all_rows = RecommendStatusChangeReport.rows(@group, @year, keep_ids:)
    # Who is still waiting. The people just changed are held on the list to
    # show what happened, so counting the list itself would keep claiming they
    # were proposed after they had already been dealt with.
    @proposed_count = @all_rows.count { |row| @converted_ids.exclude?(row.id) }
    setup_filters
    @rows = filtered(@all_rows)
  end

  # The choices this group can offer, taken from its own people so a choice can
  # never come back empty. `convert` captures these before it writes, because a
  # choice that disappears takes its filter with it and widens the list.
  def filter_choices(rows)
    { statuses: rows.map(&:status).tally,
      years: rows.filter_map(&:last_year).uniq.sort.reverse }
  end

  # A filter the group does not offer is dropped rather than left to narrow
  # nothing while still drawing a chip claiming it narrowed something.
  def setup_filters
    @choices ||= filter_choices(@all_rows)
    @status_counts = @choices[:statuses]
    @year_values = @choices[:years]

    asked = {}
    asked[:status] = known(params[:status], @status_counts.keys) if @status_counts.size > 1
    asked[:vintage] = known(params[:vintage], VINTAGE_VALUES) if @group.shows_vintage?
    asked[:last_year] = known(params[:last_year], @year_values.map(&:to_s)) if @group.shows_history?

    # active_filters drops the ones not actually narrowing anything, so what
    # counts as "off" is decided in the one place the whole app reads it from.
    @filters = UiComponents::FilterBarHelper.active_filters(asked)
    # What each status choice would actually deliver once the other filters are
    # applied, so a select's counts promise the list the choice leads to.
    @matching_statuses = filtered(@all_rows, except: :status).map(&:status).tally
  end

  def known(value, allowed) = UiComponents::FilterBarHelper.known_filter(value, allowed)

  # Filtering runs in Ruby over rows the page already holds: the largest group
  # is a few hundred people, and a second trip to the database would have to
  # rebuild the same list before it could narrow it.
  #
  # Someone whose change has just landed stays on the list whatever the filters
  # say. The change is usually the very thing that stops them matching -- a
  # status filter drops them the moment their status moves -- and a person
  # named in the result banner has to be findable in the table under it.
  def filtered(rows, except: nil)
    rows.select { |row| @converted_ids.include?(row.id) || matches_filters?(row, except:) }
  end

  def matches_filters?(row, except: nil)
    active = @filters.except(except)
    return false if active[:status] && row.status != active[:status]
    return false if active[:last_year] && row.last_year != active[:last_year].to_i
    return false if active[:vintage] && row.vintage != (active[:vintage] == VINTAGE_YES)

    true
  end

  def setup_period
    @period = RecommendStatusChangeReport.known_period(params[:period])
    @year = RecommendStatusChangeReport.year_for(@period)
    # The two cutoffs the index states in its card, so a reader can check the
    # rules against the rows rather than taking them on trust.
    @inactive_year = RecommendStatusChangeReport.inactive_since(@year)
    @retired_year = RecommendStatusChangeReport.retired_since(@year)
  end

  # An address naming no group has no list to show and no button to offer, so
  # the reader is sent to the one page that can tell them which groups exist.
  def load_group
    @group = RecommendStatusChangeReport.find_group(params[:group])
    return if @group

    redirect_to people_status_change_recommendations_path(helpers.status_change_query(@period)),
                alert: "That is not one of the proposed status changes."
  end

  # Whatever the request arrived carrying, for a redirect that has to land the
  # reader back where they were. Anything bogus is normalised on arrival.
  def carried_params
    params.permit(:period, :status, :vintage, :last_year).to_h.symbolize_keys.compact_blank
  end

  def group_path
    people_status_change_recommendations_group_path(@group.key, carried_params)
  end

  def csv_filename = "#{@year}-#{@group.key}-convert.csv"

  def csv_rows
    headings = ["Callsign", "Current Status"]
    headings << "Proposed Status" if @group.sets_status?
    headings += ["Last Year Rangered", "Years Rangered", "Alpha Year"] if @group.shows_history?
    headings << "Email"
    headings << "Vintage?" if @group.shows_vintage?

    [headings] + @rows.map { |row| csv_row(row) }
  end

  def csv_row(row)
    cells = [row.callsign, row.status]
    cells << @group.target_status if @group.sets_status?
    cells += [row.last_year, row.years, row.alpha_year] if @group.shows_history?
    cells << row.email
    cells << csv_yes_no(row.vintage) if @group.shows_vintage?
    cells
  end
end
