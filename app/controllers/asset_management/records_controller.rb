# frozen_string_literal: true

class AssetManagement::RecordsController < ApplicationController
  include AssetYearScopeConcern
  include CsvExportConcern

  layout "asset_management"

  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    only: %i[index type show],
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  authorize_ability :edit_assets,
                    roles: [Role::EDIT_ASSETS],
                    only: %i[new create edit update destroy],
                    deny_to: :editor_denied_path,
                    message: "You are not authorized to manage assets."

  before_action :set_asset, only: %i[show edit update destroy]

  UNTYPED = AssetManagement::RecordsHelper::UNTYPED

  def index
    load_years
    load_type_counts

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows(year_assets), filename: csv_filename) }
    end
  end

  def type
    load_years
    @type = params[:type] == UNTYPED ? nil : params[:type]
    # Named positively: the report siblings ride their own params through
    # current_index_params to rebuild their Back links, and this page has no chip
    # label for any of them -- one left in would draw a chip labelled
    # ": returned". Slicing the keys ASSET_FILTER_CHIP_LABELS can name makes that
    # true by construction, so a new sibling's params can never leak in here.
    @filter_params = current_index_params.slice(*AssetManagement::RecordsHelper::ASSET_FILTER_CHIP_LABELS.keys)
    @index_params = @filter_params.merge(year: @year, type: params[:type]).compact_blank
    @filter_option_assets = assets_for_type
    @total_count = @filter_option_assets.size
    @expired_count = @filter_option_assets.count(&:has_expired?)
    @assets = @filter_params.any? ? assets_for_type(@filter_params) : @filter_option_assets

    respond_to do |format|
      format.html
      format.csv { send_csv(csv_rows(@assets), filename: csv_filename) }
    end
  end

  def show
    @asset_history = PersonAsset.retrieve_history(@asset.id)
    @current_checkout = @asset.checked_out
    @return_index_params = current_index_params(year: @asset.year)
    @back_to = back_to_origin(@return_index_params)
  end

  def new
    @asset = AssetManagement::Records::CreateForm.new(type: params[:type].presence || Asset::TYPE_RADIO)
    @return_index_params = current_index_params
    @cancel_path = type_records_path(@return_index_params)
    @cancel_label = type_records_label(@return_index_params[:type])
  end

  def create
    @asset = AssetManagement::Records::CreateForm.new(create_asset_params.merge(year: Current.year))
    @return_index_params = current_index_params
    @cancel_path = type_records_path(@return_index_params)
    @cancel_label = type_records_label(@return_index_params[:type])

    if @asset.save
      redirect_to type_records_path(type: @asset.type, year: Current.year),
                  success: create_success_message(@asset)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @return_index_params = current_index_params(year: @asset.year)
    @cancel_path = type_records_path(@return_index_params)
    @cancel_label = type_records_label(@return_index_params[:type])
  end

  def update
    @return_index_params = current_index_params(year: @asset.year)
    @cancel_path = type_records_path(@return_index_params)
    @cancel_label = type_records_label(@return_index_params[:type])

    if @asset.update(update_asset_params)
      redirect_to asset_management_record_path(@asset, @return_index_params), success: "Asset updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    return_params = current_index_params(year: @asset.year).merge(type: @asset.type)
    @asset.destroy!

    redirect_to type_records_path(return_params), success: "Asset deleted."
  end

  private

  # Two-tier deny for editors: an editor-denied user who can still READ goes back to the
  # inventory; otherwise home.
  def editor_denied_path
    return me_root_path unless can?(:read_assets)

    asset_management_records_path(year: params[:year].presence || Asset.where(id: params[:id]).pick(:year) || Current.year)
  end

  # Which page the reader arrived from. Both report siblings drill into this
  # page for an asset's detail, and neither one's filter is expressible here, so
  # send them back where they were instead of to the inventory. Each branch
  # slices the keys its own route understands rather than subtracting the ones
  # it does not: a key added to current_index_params for one report would
  # otherwise leak into the other's URL.
  def back_to_origin(return_params)
    case return_params[:origin]
    when "outstanding"
      ["Assets outstanding",
       asset_management_assets_outstanding_path(return_params.slice(:year, :type))]
    when "history"
      ["Asset history",
       asset_management_asset_history_path(return_params.slice(:year, :type, :outcome, :page))]
    when "search"
      ["Asset search",
       asset_management_search_path(return_params.slice(:year, :barcode))]
    when "radio-assets"
      ["Radio assets",
       asset_management_radio_assets_path(
         return_params.slice(:year, :duration, :description, :view, :page)
       )]
    else
      [type_records_label(return_params[:type]), type_records_path(return_params)]
    end
  end

  # The records list an asset belongs to: its own type page, or the types index
  # when the reader never picked a type. Sliced rather than subtracted for the
  # same reason as #type's filters: this route understands the year, the type and
  # this page's own filters, and nothing a report sibling sends through.
  def type_records_path(link_params)
    link_params = link_params
                  .slice(:year, :type, *AssetManagement::RecordsHelper::ASSET_FILTER_CHIP_LABELS.keys)
                  .compact_blank
    type = link_params.delete(:type)
    return asset_management_records_path(link_params) if type.blank?

    asset_management_records_type_path(type, link_params)
  end

  def type_records_label(type)
    type.blank? ? "Asset inventory" : "#{helpers.asset_type_label(type)} assets"
  end

  def load_years
    @available_years = Asset.distinct.order(year: :desc).pluck(:year)
    @year = resolve_selected_year(@available_years, params[:year])
  end

  def load_type_counts
    @type_counts = @year ? Asset.where(year: @year).group(:type).count : {}
    @expired_counts = @year ? Asset.where(year: @year, expires_on: ..Current.today).group(:type).count : {}
    @types = @type_counts.keys.sort_by { |type| AssetManagement::RecordsHelper::ASSET_TYPE_SORT.fetch(type, Float::INFINITY) }
    @total_records = @type_counts.values.sum
  end

  def year_assets
    @year ? Asset.find_for_query(year: @year) : []
  end

  # find_for_query skips a blank type, so the untyped bucket is narrowed here.
  def assets_for_type(query = {})
    return [] unless @year

    assets = Asset.find_for_query(query.merge(year: @year, type: @type))
    @type.nil? ? assets.select { |asset| asset.type.blank? } : assets
  end

  def current_index_params(year: nil)
    # :outcome belongs to the Asset History report, :duration / :view to
    # Radio Assets, and :barcode to Asset Search -- none to this page. They ride
    # through, with :page, so each report's Back link returns the reader to the
    # exact view they left.
    # back_to_origin and type_records_path each drop the keys their own route
    # does not understand.
    params.permit(:year, :type, :description, :group_name, :entity_assignment, :order_number,
                  :expire, :origin, :outcome, :duration, :view, :page, :barcode)
          .to_h
          .symbolize_keys
          .compact_blank
          .tap do |values|
      values[:year] = year if year.present?
    end
  end

  def set_asset
    @asset = Asset.includes(checked_out: [:person, :check_out_person, :attachment]).find(params[:id])
  end

  def create_asset_params
    params.expect(asset: [:type,
                          :barcode,
                          :description,
                          :entity_assignment,
                          :perm_assign,
                          :group_name,
                          :expires_on,
                          :order_number,
                          :notes,
                          :copies])
  end

  def update_asset_params
    params.expect(asset: [:type,
                          :barcode,
                          :description,
                          :entity_assignment,
                          :perm_assign,
                          :group_name,
                          :expires_on,
                          :order_number,
                          :notes])
  end

  def create_success_message(form)
    if form.created_count == 1
      "Asset created."
    else
      "#{form.created_count} assets created."
    end
  end

  def csv_filename
    return "assets.csv" if @year.blank?
    return "#{@year}-#{params[:type]}-assets.csv" if params[:type].present?

    "#{@year}-assets.csv"
  end

  def csv_rows(assets)
    rows = [
      [
        "Barcode",
        "Type",
        "Description",
        "Assignment",
        "Asset Group",
        "Entity Assignment",
        "Year",
        "Expires On",
        "Has Expired",
        "Created At",
        "Notes"
      ]
    ]

    assets.each do |asset|
      rows << [
        asset.barcode,
        helpers.asset_type_label(asset.type),
        asset.description,
        helpers.asset_duration_label(asset),
        asset.group_name,
        asset.entity_assignment,
        asset.year,
        asset.expires_on&.iso8601,
        asset.has_expired? ? "Yes" : "No",
        asset.created_at&.iso8601,
        asset.notes
      ]
    end

    rows
  end
end
