# frozen_string_literal: true

# In-shell assets page for the HQ Window Interface (Ember port/assets.hbs):
# the person's currently checked-out gear and the current year's check in/out
# history, plus barcode checkout — replacing the sidebar link-out to the
# Event-Management-gated /person assets page, so the whole HQ persona can
# check gear in and out without leaving the shell. All asset behaviour is
# AssetManagementConcern's; this controller only supplies the page and the
# path contract. Always the current year — the shell has no year selector.
class Hq::AssetsController < ApplicationController
  include HqConcern
  include AssetManagementConcern

  # Only index renders the shell. Same reasoning as Hq::SchedulingController:
  # load_hq_shell consumes the once-per-person entry-warning session flag, so
  # letting it run on the redirect and turbo-stream actions would silently eat
  # the operator's warning modal.
  skip_before_action :load_hq_shell,
                     only: %i[asset_checkout asset_check_in
                              asset_change_attachment asset_update_attachment]

  def index
    @assets_checked_out, @assets_history =
      PersonAsset.find_for_query(person_id: @person.id, year: Current.year)
                 .partition { |ap| ap.checked_in.nil? }

    # The barcode form only renders once the radio agreement is signed.
    return unless @person_event.asset_authorized

    @checkout_form = AssetCheckoutForm.new
    @attachments = AssetAttachment.find_all
  end

  private

  # AssetManagementConcern contract
  def assets_person = @person

  def assets_return_path = hq_assets_path(@person)

  def assets_checkout_path = hq_assets_checkout_path(@person)

  def assets_check_in_path(person_asset)
    hq_assets_check_in_path(@person, person_asset)
  end

  def assets_change_attachment_path(person_asset)
    hq_assets_change_attachment_path(@person, person_asset)
  end

  def assets_update_attachment_path(person_asset)
    hq_assets_update_attachment_path(@person, person_asset)
  end
end
