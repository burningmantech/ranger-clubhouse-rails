# frozen_string_literal: true

# Assets still checked out for a year -- an open person_asset row with no
# check-in. Read-only chase list: ops runs it during and after the event to see
# what has not come back and who has it.
class AssetManagement::AssetsOutstandingController < ApplicationController
  include AssetYearScopeConcern
  include CsvExportConcern

  layout "asset_management"

  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  # Upstream: ADMIN or EDIT_ASSETS (AssetPolicy::before) or EVENT_MANAGEMENT
  # (AssetPolicy::index), named here exactly.
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

  # Years come from the asset records themselves, matching the Asset Inventory
  # sibling: every year holding inventory is browsable. (2020 and 2021 have no
  # asset rows at all, so the pandemic skips itself.)
  def load_report
    @available_years = Asset.distinct.order(year: :desc).pluck(:year)
    @year = resolve_selected_year(@available_years, params[:year])
    @assets = @year ? Asset.find_for_query(year: @year, checked_out: true) : []

    # One query, then filter in memory: a year holds a few dozen outstanding
    # assets at most, and the stats and filter options need the unfiltered set.
    @filter_params = { type: requested_type }
    @filtered_assets = filtered_assets

    # Handhelds only, matching what "Radio" means everywhere else in this
    # namespace -- desktop radios, vehicle radios and chargers are their own
    # types in the filter and are not what anyone is chasing.
    @radio_count = @assets.count { |asset| asset.type == Asset::TYPE_RADIO }
    @holder_count = @assets.filter_map { |asset| asset.checked_out&.person_id }.uniq.size
  end

  # The newest year that actually holds something outstanding. The first asset
  # created for next year's event otherwise becomes years.first and opens this
  # chase list on a year with nothing out, while last year's radios are still
  # gone.
  def default_year(years)
    outstanding_years(years).max || years.first
  end

  def outstanding_years(years)
    PersonAsset.where(checked_in: nil)
               .joins(:asset)
               .where(asset: { year: years })
               .distinct
               .pluck("asset.year")
  end

  # A type nothing is outstanding in would filter the table down to nothing and
  # leave a chip promising otherwise, so anything unrecognized reads as "all".
  # blank? first: with no filter applied `type` is nil, and a NULL-typed asset
  # would otherwise match it and narrow the default page to just those rows.
  def requested_type
    type = params[:type].presence
    return ALL_FILTER if type.blank?

    @assets.any? { |asset| asset.type == type } ? type : ALL_FILTER
  end

  def filtered_assets
    type = @filter_params[:type]
    return @assets if type == ALL_FILTER

    @assets.select { |asset| asset.type == type }
  end

  # The filter travels in the filename: exporting Radio and then Gear otherwise
  # hands the reader two files with the same name.
  def csv_filename
    type = @filter_params[:type]
    parts = [@year, (type unless type == ALL_FILTER), "assets-outstanding.csv"]

    parts.compact.join("-")
  end

  # Upstream's export builds a Permanent/Temporary value its column list never
  # emits; the Assignment column here is that dead code finished.
  def csv_rows
    rows = [["Barcode", "Callsign", "Type", "Description", "Attachment", "Assignment",
             "Checked Out", "Checked Out By"]]

    @filtered_assets.each do |asset|
      checkout = asset.checked_out
      rows << [
        asset.barcode,
        helpers.person_display_name(checkout&.person, checkout&.person_id, blank: nil),
        helpers.asset_type_label(asset.type),
        asset.description,
        checkout&.attachment&.description,
        helpers.asset_duration_label(asset),
        checkout&.checked_out&.iso8601,
        helpers.person_display_name(checkout&.check_out_person, checkout&.check_out_person_id,
                                    blank: nil)
      ]
    end

    rows
  end
end
