# frozen_string_literal: true

# The public voucher page: whether one person is a Ranger, read without signing
# in by whoever was handed the link. Voucher decides what it may say.
class VouchersController < ApplicationController
  layout "bookmark"

  allow_unauthenticated_access
  # The reader is not the subject: a sign-in cookie on the checking device has
  # nothing to do with this page.
  skip_before_action :set_current_user
  skip_before_action :build_menu_items

  # The id is the only key, so guessing at it is slowed down.
  rate_limit to: 30, within: 1.minute,
             with: -> { render :rate_limited, status: :too_many_requests }

  def show
    # A status can change between two checks, the address is the secret, and
    # no search engine should list it.
    no_store
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Robots-Tag"] = "noindex"

    @voucher = Voucher.find(params[:id])
    render :not_found, status: :not_found unless @voucher
  end
end
