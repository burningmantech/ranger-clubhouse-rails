# frozen_string_literal: true

# Presentation for /mentoring/alpha-signout: what became of one submitted row,
# and the window the page describes itself with.
module Mentoring::AlphaSignoutHelper
  # Keyed on the symbols AlphaSignOut.sign_out returns. Each carries an icon as
  # well as a colour -- the outcome must not be legible by colour alone.
  RESULT_BADGES = {
    signed_out: ["Signed out", :success, "circle-check"],
    already_signed_out: ["Was already signed out", :error, "circle-exclamation"],
    not_eligible: ["No longer an open Alpha shift", :error, "circle-xmark"]
  }.freeze

  def alpha_signout_result_badge(result)
    label, variant, icon = RESULT_BADGES.fetch(result)
    ui_badge label, variant, icon: icon, icon_type: :solid
  end

  # The clock times the shift's window actually covers, so the banner can state
  # them instead of asking the reader to do the arithmetic (and instead of
  # repeating upstream's wrong "one hour before til one after"). Dated, not
  # bare times: a late-swing window crosses midnight.
  #
  # safe_join, not interpolation: datetime_format returns a tooltip-carrying
  # <span>, which a plain String would escape into view.
  def alpha_signout_window(slot)
    safe_join([datetime_format(slot.begins - AlphaSignOut::HOURS_PRIOR, tz: slot.timezone),
               datetime_format(slot.begins + AlphaSignOut::HOURS_AFTER, tz: slot.timezone)], " and ")
  end
end
