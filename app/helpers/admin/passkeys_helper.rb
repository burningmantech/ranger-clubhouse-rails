# frozen_string_literal: true

module Admin::PasskeysHelper
  PASSKEY_FILTER_CHIP_LABELS = { added_by: "Added By" }.freeze

  # The filter_bar chip for the one filter, when it is on. Its URL drops it.
  def passkey_filter_chips(form)
    active = form.query_params[PasskeyFilterForm::PARAM_SCOPE]&.except(:page) || {}

    filter_chips(active, PASSKEY_FILTER_CHIP_LABELS, value_label: ->(_key, _value) { "An Admin" }) do |_remaining, _key|
      admin_passkeys_path
    end
  end
end
