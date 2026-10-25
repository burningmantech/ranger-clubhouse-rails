# frozen_string_literal: true

# The year's checkout ledger: one row per time an asset left the cage, who took
# it, who handed it over, and whether it came back. The sibling Assets
# Outstanding page answers "what is still gone"; this one answers "what
# happened", including everything already returned.
class AssetManagement::AssetHistoryController < ApplicationController
  include AssetYearScopeConcern
  include CsvExportConcern

  layout "asset_management"

  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # Handhelds are excluded by default, matching upstream. They are checked out
  # and back every shift -- ~2,100 rows a year against ~160 for everything else
  # -- and are chased on the HQ screens rather than reconciled here. Picking
  # Radio in the Type filter opts back in.
  DEFAULT_EXCLUDED_TYPE = Asset::TYPE_RADIO

  OUTCOME_RETURNED = "returned"
  OUTCOME_OUTSTANDING = "outstanding"

  PAGE_SIZE = 100

  # Upstream: ADMIN or EDIT_ASSETS (AssetPolicy::before) or EVENT_MANAGEMENT
  # (AssetPolicy::index), named here exactly, as on the two sibling pages.
  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  def index
    load_report

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows, filename: csv_filename) }
    end
  end

  private

  def load_report
    @available_years = Asset.distinct.order(year: :desc).pluck(:year)
    @year = resolve_selected_year(@available_years, params[:year])

    # Two loads rather than one: the Type filter changes which assets are
    # fetched (picking Radio widens the query rather than narrowing a result),
    # so the stats and the filter's own options need their own unfiltered
    # default-scope pass to describe.
    @rows = @year ? checkout_rows(default_scope_assets) : []
    # Assigned before @filter_params rather than lazily: the Type select needs
    # the list whether or not a type was requested, and requested_type returns
    # early without asking for it when the param is absent.
    @selectable_types = selectable_types
    @filter_params = { type: requested_type, outcome: requested_outcome }
    @filtered_rows = filtered_rows

    load_stats
    paginate_rows

    @hidden_radio_checkouts = hidden_radio_checkouts
  end

  # Only asked when the page has nothing to show: the empty state has to tell a
  # quiet year apart from one whose activity is entirely the handheld radios the
  # default scope hides.
  def hidden_radio_checkouts
    return 0 unless @year && @filtered_rows.empty?

    PersonAsset.joins(:asset)
               .where(asset: { year: @year, type: DEFAULT_EXCLUDED_TYPE })
               .count
  end

  # The default scope: everything the page describes when no filter is applied.
  def default_scope_assets
    Asset.find_for_query(year: @year, exclude: DEFAULT_EXCLUDED_TYPE, include_history: true)
  end

  # find_for_query natural-sorts by barcode and orders asset_history by
  # checked_out, so flattening preserves barcode-then-time order with no
  # further sort. Assets that never went out contribute nothing, which is the
  # point of a report named "history".
  def checkout_rows(assets)
    assets.flat_map { |asset| asset.asset_history.map { |history| [asset, history] } }
  end

  # The newest year that actually recorded a checkout. The first asset created
  # for next year's event otherwise becomes years.first and opens the ledger on
  # a year where nothing has happened yet.
  def default_year(years)
    checkout_years(years).max || years.first
  end

  # Scoped exactly like the default ledger, radio exclusion included: counting
  # radio checkouts here would default the page onto a year whose only activity
  # it refuses to render. NULL-safe for the same reason Asset.apply_exclude_filter
  # is -- `type != 'radio'` alone drops the Laravel-shared table's NULL-typed rows.
  def checkout_years(years)
    type = Asset.arel_table[:type]

    PersonAsset.joins(:asset)
               .where(asset: { year: years })
               .where(type.not_eq(DEFAULT_EXCLUDED_TYPE).or(type.eq(nil)))
               .distinct
               .pluck("asset.year")
  end

  # "all" here means "everything except handheld radios" -- the default scope --
  # so an absent param and the sentinel agree, and a chip that removes the
  # filter lands back on the default. A type no asset in the year carries would
  # filter the ledger to nothing while a chip promised otherwise, so anything
  # unrecognized reads as "all". blank? first: with no filter applied `type` is
  # nil, and a NULL-typed asset would otherwise match it.
  def requested_type
    type = params[:type].presence
    return ALL_FILTER if type.blank?

    @selectable_types.include?(type) ? type : ALL_FILTER
  end

  # The types the year actually holds, radios included -- the whole point of the
  # filter is that Radio is reachable even though the default scope omits it.
  def selectable_types
    @year ? Asset.where(year: @year).distinct.pluck(:type).compact : []
  end

  def requested_outcome
    outcome = params[:outcome].presence
    [OUTCOME_RETURNED, OUTCOME_OUTSTANDING].include?(outcome) ? outcome : ALL_FILTER
  end

  # Type is not an in-memory narrowing: selecting Radio has to widen the query
  # past the default exclusion, so it re-fetches. Outcome narrows what is
  # already loaded.
  def filtered_rows
    rows = if @filter_params[:type] == ALL_FILTER
             @rows
           else
             checkout_rows(Asset.find_for_query(year: @year, type: @filter_params[:type],
                                                include_history: true))
           end

    case @filter_params[:outcome]
    when OUTCOME_RETURNED then rows.select { |_asset, history| history.checked_in.present? }
    when OUTCOME_OUTSTANDING then rows.select { |_asset, history| history.checked_in.nil? }
    else rows
    end
  end

  # Stats describe the filtered ledger, not the default scope: with Radio
  # selected the table shows radios, and a headline counting only non-radios
  # would contradict every row under it.
  def load_stats
    @checkout_count = @filtered_rows.size
    @asset_count = @filtered_rows.map { |asset, _history| asset.id }.uniq.size
    @holder_count = @filtered_rows.filter_map { |_asset, history| history.person_id }.uniq.size
    @unreturned_count = @filtered_rows.count { |_asset, history| history.checked_in.nil? }
  end

  # Pagy has no array backend in v43 and the barcode order comes from
  # Asset.natural_sort in Ruby (G-0104 and G-104 sort differently lexically),
  # so the page is sliced here rather than in SQL.
  def paginate_rows
    @total_pages = [(@filtered_rows.size / PAGE_SIZE.to_f).ceil, 1].max
    @page = params[:page].to_s.presence&.to_i || 1
    @page = 1 if @page < 1
    @page = @total_pages if @page > @total_pages
    @page_rows = @filtered_rows[(@page - 1) * PAGE_SIZE, PAGE_SIZE] || []
  end

  # The filters travel in the filename: exporting Radio and then Gear otherwise
  # hands the reader two files with the same name.
  def csv_filename
    type = @filter_params[:type]
    outcome = @filter_params[:outcome]
    parts = [@year, (type unless type == ALL_FILTER), (outcome unless outcome == ALL_FILTER),
             "asset-history.csv"]

    parts.compact.join("-")
  end

  # The whole filtered ledger, not the visible page -- an export that stopped at
  # 100 rows would silently under-report the year. Upstream's column list
  # omitted the attachment and the duration despite loading both, and emitted
  # only one of the two people on each row; both are finished here.
  def csv_rows
    rows = [["Barcode", "Type", "Description", "Assignment", "Callsign", "Attachment",
             "Checked Out", "Checked Out By", "Checked In", "Checked In By", "Duration (seconds)"]]

    @filtered_rows.each do |asset, history|
      rows << [
        asset.barcode,
        helpers.asset_type_label(asset.type),
        asset.description,
        helpers.asset_duration_label(asset),
        helpers.person_display_name(history.person, history.person_id, blank: nil),
        history.attachment&.description,
        history.checked_out&.iso8601,
        helpers.person_display_name(history.check_out_person, history.check_out_person_id,
                                    blank: nil),
        history.checked_in&.iso8601,
        helpers.person_display_name(history.check_in_person, history.check_in_person_id,
                                    blank: nil),
        # Blank rather than a span measured to "now" -- see
        # asset_history_duration; an open checkout has no elapsed time to state.
        (history.duration if history.checked_in.present?)
      ]
    end

    rows
  end
end
