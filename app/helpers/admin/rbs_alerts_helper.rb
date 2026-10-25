# frozen_string_literal: true

module Admin::RbsAlertsHelper
  # How an alert is allowed to reach a Ranger. This is fixed per alert and is
  # not something the form can change, but it decides which checkboxes the
  # Ranger is offered -- so anyone rewriting the wording needs to see it.
  #
  # Returns the label and the badge colour to draw it in, or nil to print the
  # label as plain text.
  def rbs_alert_channels(alert)
    return ["Required", :warning] if alert.no_opt_out
    return ["SMS only", :secondary] if alert.sms_only
    return ["Email only", :secondary] if alert.email_only

    ["SMS or email", nil]
  end
end
