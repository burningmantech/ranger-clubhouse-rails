# frozen_string_literal: true

# Barcode lookup for a single asset: who has it right now, and everywhere it has
# been. The sibling pages answer questions about the whole year's inventory;
# this one starts from a barcode in someone's hand.
#
# Barcodes are only unique within an event year and are reused between events,
# so a miss in the selected year usually means the wrong year was selected. The
# not-found state names the other years holding the barcode rather than leaving
# the reader to try each one.
class AssetManagement::SearchController < ApplicationController
  include AssetYearScopeConcern

  layout "asset_management"

  # Upstream: ADMIN or EDIT_ASSETS or EVENT_MANAGEMENT, the same set allowed to
  # check an asset back in, so one gate covers both actions.
  authorize_ability :read_assets,
                    roles: [Role::EDIT_ASSETS, Role::EVENT_MANAGEMENT],
                    deny_to: :me_root_path,
                    message: "You are not authorized to view assets."

  def index
    @available_years = Asset.distinct.order(year: :desc).pluck(:year)
    @year = resolve_selected_year(@available_years, params[:year])
    # Only a plain string is a barcode. ?barcode[]= and ?barcode[a]= arrive as an
    # Array or a Hash, and printing one of those back at the reader in the
    # not-found message shows them the inside of the request.
    barcode = params[:barcode]
    @barcode = barcode.is_a?(String) ? barcode.strip.presence : nil

    return if @barcode.nil? || @year.nil?

    # find_for_query preloads the whole history graph, so the table below costs
    # no further queries. At most one asset can match -- barcode is unique
    # within a year.
    @asset = Asset.find_for_query(barcode: @barcode, year: @year, include_history: true).first

    if @asset
      @history = @asset.asset_history
      # Read from the loaded association rather than asking the database again.
      @open_checkout = @history.find { |row| row.checked_in.nil? }
    else
      @other_years = other_years_holding_barcode
    end
  end

  def check_in
    asset = Asset.find(params[:asset_id])
    open_checkout = PersonAsset.find_checked_out_person(asset.id)

    if open_checkout.nil?
      redirect_to lookup_path(asset), error: "Asset #{asset.barcode} is already checked in."
    else
      open_checkout.update!(checked_in: Current.time, check_in_person_id: Current.person_id)
      redirect_to lookup_path(asset), success: "#{asset.barcode} checked in."
    end
  end

  private

  # The same barcode in every other year that has one. Unindexed on barcode
  # alone -- the table is small enough that the scan does not matter.
  def other_years_holding_barcode
    Asset.where(barcode: @barcode).distinct.order(year: :desc).pluck(:year) - [@year]
  end

  # Back to the lookup the reader was already looking at, so the page they land
  # on is the one they acted from, now showing the closed row.
  def lookup_path(asset)
    asset_management_search_path(barcode: asset.barcode, year: asset.year)
  end
end
