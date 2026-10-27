# frozen_string_literal: true

# Every passkey on every account, for an Admin to look over: who has taken
# them up, and above all which ones an Admin put there.
#
# To look, not to touch. A passkey is removed from the page of the person it
# belongs to, so there is one place that does it and one line in the log that
# says so. Each row links there.
class Admin::PasskeysController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  def index
    @form = PasskeyFilterForm.new(filter_params)

    result = PersonPasskey.find_for_list(added_by_admin: @form.added_by_admin?, page: @form.page)
    # Pagy returns a lazy relation; load it so the view's .any? doesn't issue
    # an extra query.
    @passkeys = result[:passkeys].to_a
    @pagy = result[:pagy]
    @stats = PersonPasskey.list_stats
  end

  private

  def filter_params
    scoped_params(PasskeyFilterForm::PARAM_SCOPE, :added_by, :page)
  end
end
