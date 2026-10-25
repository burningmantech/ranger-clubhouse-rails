# frozen_string_literal: true

# Manage a person's asset checkout history and current-year asset activity.
# The barcode checkout/check-in/attachment flow lives in
# AssetManagementConcern (shared with the HQ window interface); this
# controller keeps the person-page-only pieces: year navigation, asset
# authorization, per-asset history, and admin record deletion.
class Person::AssetsController < ApplicationController
  layout "person"

  include PersonConcern
  include AssetManagementConcern

  before_action :setup_year

  authorize_ability :manage_assets,
                    roles: [Role::ADMIN, Role::EVENT_MANAGEMENT, Role::EVENT_MANAGEMENT_ON_PLAYA],
                    deny_to: :assets_manager_deny_path,
                    message: "You are not authorized to manage assets."

  before_action :set_person_asset, only: %i[destroy history]

  authorize_ability :admin_assets,
                    roles: [], admin: true,
                    only: %i[destroy update_authorization],
                    deny_to: :assets_deny_path,
                    message: :admin_permission_error

  require_current_year_for only: %i[create update_authorization],
                           deny_to: :assets_deny_path,
                           message: :current_year_error

  # The person routes dispatch the shared checkout/check-in/attachment
  # actions under their original REST names.
  alias_method :create, :asset_checkout
  alias_method :check_in, :asset_check_in
  alias_method :change_attachment, :asset_change_attachment
  alias_method :update_attachment, :asset_update_attachment

  def index
    load_index_data
  end

  def update_authorization
    @person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)

    if @person_event.update(person_event_params)
      redirect_index(success: "Asset authorization updated.")
    else
      render_index(status: :unprocessable_entity)
    end
  end

  def history
    @history = PersonAsset.retrieve_history(@person_asset.asset_id)
    # update (not append) so a re-opened dialog replaces the previous one
    # instead of stacking.
    render turbo_stream: turbo_stream.update("modal", partial: "history", locals: { history: @history })
  end

  def destroy
    @person_asset.destroy!
    redirect_index(success: "Asset checkout record deleted.")
  end

  private

  # AssetManagementConcern contract
  def assets_person = @person

  def assets_return_path = person_assets_path(@person, year: @year)

  def assets_checkout_path = person_assets_path(@person, year: @year)

  def assets_check_in_path(person_asset)
    check_in_person_asset_path(@person, person_asset, year: @year)
  end

  def assets_change_attachment_path(person_asset)
    change_attachment_person_asset_path(@person, person_asset, year: @year)
  end

  def assets_update_attachment_path(person_asset)
    update_attachment_person_asset_path(@person, person_asset, year: @year)
  end

  def load_index_data
    @years = available_years
    @person_assets = PersonAsset.find_for_query(person_id: @person.id, year: @year)
    @checkout_form = AssetCheckoutForm.new
    @attachments = AssetAttachment.find_all
    if @person_event.nil?
      @person_event = PersonEvent.first_or_new_for_person_year(@person.id, @year)
    end
  end

  def render_index(status:)
    load_index_data
    render :index, status:
  end

  def set_person_asset
    @person_asset = PersonAsset.includes(PersonAsset::RELATIONSHIPS)
                               .where(person_id: @person.id)
                               .find(params[:id])
  end

  def person_event_params
    params.expect(person_event: [:asset_authorized])
  end

  def assets_manager_deny_path
    person_path(@person)
  end

  def assets_deny_path
    person_assets_path(@person, year: @year)
  end

  def admin_permission_error
    case action_name
    when "destroy"
      "Admin permission required to delete asset records."
    when "update_authorization"
      "Admin permission required to update asset authorization."
    else
      "Admin permission required."
    end
  end

  def current_year_error
    case action_name
    when "create"
      "Checkouts are only allowed for the current year."
    when "update_authorization"
      "Asset authorization may only be changed for the current year."
    else
      "Updates are only allowed for the current year."
    end
  end

  def available_years
    years = PersonAsset.where(person_id: @person.id)
                       .distinct
                       .pluck(Arel.sql("YEAR(checked_out)"))
                       .compact

    years_with_current(years)
  end

  def redirect_index(**flash_hash)
    redirect_to person_assets_path(@person, year: @year), **flash_hash
  end
end
