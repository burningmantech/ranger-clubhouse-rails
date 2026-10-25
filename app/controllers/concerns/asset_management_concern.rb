# frozen_string_literal: true

# Barcode-driven asset checkout, check-in, and attachment changes shared by
# the person assets page (Person::AssetsController) and the HQ window
# interface. Ported from port/api/AssetController.php (checkout/checkin);
# the shared templates in app/views/common/assets/ mirror
# port/components/hq-asset-table.hbs and asset-duration-label.hbs.
#
# The checkout guard chain preserves the upstream order and semantics:
#   1. unknown barcode            -> error flash
#   2. already checked out        -> error flash naming the holder and time
#   3. entity-assigned            -> error flash; NEVER checkout-able, force
#                                    does not override
#   4. expired                    -> force interstitial modal; force overrides
#                                    expiry only and records check_out_forced
#   5. success                    -> PersonAsset row stamped with
#                                    check_out_person_id
#
# Terminal outcomes redirect to assets_return_path with a flash. The expired
# interstitial and the change-attachment dialog render turbo-stream modals
# into the "modal" frame. The target row for the member actions comes from
# params[:person_asset_id] or params[:id], always scoped to the subject
# person.
#
# Includers must define (exposed to the shared views as helper methods):
#   assets_person                     - the Person equipment is issued to
#   assets_return_path                - where redirects land
#   assets_checkout_path              - POST target of the barcode checkout form
#   assets_check_in_path(ap)          - PATCH target to check an asset back in
#   assets_change_attachment_path(ap) - GET renders the change-attachment modal
#   assets_update_attachment_path(ap) - PATCH applies the attachment change
module AssetManagementConcern
  extend ActiveSupport::Concern

  included do
    helper_method :assets_person, :assets_return_path, :assets_checkout_path,
                  :assets_check_in_path, :assets_change_attachment_path,
                  :assets_update_attachment_path
  end

  def asset_checkout
    checkout = asset_checkout_params
    barcode = checkout[:barcode].to_s.strip

    asset = Asset.find_by_barcode_year(barcode, Current.year)
    if asset.nil?
      return assets_outcome(:error, %(Barcode "#{barcode}" was not found.))
    end

    if (open_checkout = PersonAsset.find_checked_out_person(asset.id))
      return assets_outcome(:error, still_checked_out_error(asset, open_checkout))
    end

    if asset.entity_assignment.present?
      return assets_outcome(:error, "Asset #{asset.barcode} is assigned to " \
                                    "#{asset.entity_assignment} and cannot be checked out.")
    end

    if asset.has_expired? && checkout[:force] != "1"
      return render_asset_modal("expired_modal",
                                asset:,
                                attachment_id: checkout[:attachment_id].presence)
    end

    PersonAsset.create!(
      person_id: assets_person.id,
      asset_id: asset.id,
      attachment_id: checkout[:attachment_id].presence,
      checked_out: Current.time,
      check_out_person_id: Current.person_id,
      check_out_forced: asset.has_expired?
    )

    assets_outcome(:success, "Checked out #{asset.type} ##{asset.barcode}.", asset:)
  end

  def asset_check_in
    person_asset = locate_person_asset
    if person_asset.checked_in.present?
      return assets_outcome(:error, "Asset is already checked in.")
    end

    person_asset.update!(checked_in: Current.time, check_in_person_id: Current.person_id)
    assets_outcome(:success,
                   "Checked in #{person_asset.asset.type} ##{person_asset.asset.barcode}.",
                   asset: person_asset.asset)
  end

  def asset_change_attachment
    render_asset_modal("change_attachment_modal",
                       person_asset: locate_person_asset,
                       attachments: AssetAttachment.find_all)
  end

  def asset_update_attachment
    person_asset = locate_person_asset
    if person_asset.checked_in.present?
      return assets_outcome(:error, "Cannot change attachment after check in.")
    end

    # A blank attachment clears it, so a request that is not a set of fields is
    # refused (400) by expect rather than read as blank.
    person_asset.update!(attachment_id: params.expect(person_asset: [:attachment_id])[:attachment_id].presence)
    assets_outcome(:success, "Attachment updated.")
  end

  private

  # Terminal outcome of an asset action. Redirects to assets_return_path by
  # default. Includers whose asset controls render inside a turbo-frame (the
  # site-registration wizard) override this to update in place instead — a
  # redirect there cannot match the frame and would discard the wizard's
  # client-side step state.
  #
  # +asset:+ carries the Asset a successful checkout or check-in acted on, and
  # is nil for every failure and for attachment changes — mirroring upstream,
  # where onAssetCheckOut/onAssetCheckIn only ran on success and only those two
  # actions had callbacks. Includers that key checklist state off the action
  # need it; the default outcome ignores it.
  def assets_outcome(flash_type, message, **)
    redirect_to assets_return_path, flash_type => message
  end

  # Reads path_parameters, not params: the HQ routes carry the row as
  # :person_asset_id and the person routes as :id, and taking it from the merged
  # params would let a query string override the id in the URL path.
  def locate_person_asset
    path = request.path_parameters
    PersonAsset.includes(PersonAsset::RELATIONSHIPS)
               .where(person_id: assets_person.id)
               .find(path[:person_asset_id] || path[:id])
  end

  def asset_checkout_params
    params.expect(person_asset: [:barcode, :attachment_id, :force])
  end

  # Upstream names the holder and checkout time, falling back to
  # "Deleted #<id>" when the holder's account no longer exists.
  def still_checked_out_error(asset, open_checkout)
    holder = open_checkout.person&.callsign || "Deleted ##{open_checkout.person_id}"
    message = "Asset #{asset.barcode} is still checked out by #{holder}"
    if open_checkout.checked_out
      message += " (checked out #{open_checkout.checked_out.strftime(DateTimeHelper::MONTH_DAY_TIME)})"
    end
    "#{message}."
  end

  # update (not append) so a repeated scan replaces the open interstitial
  # instead of stacking dialogs.
  def render_asset_modal(partial, locals = {})
    render turbo_stream: turbo_stream.update("modal", partial: "common/assets/#{partial}",
                                                      locals: locals)
  end
end
