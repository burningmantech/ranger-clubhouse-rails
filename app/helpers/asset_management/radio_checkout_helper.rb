# frozen_string_literal: true

module AssetManagement::RadioCheckoutHelper
  # One of the two view buttons. Both are always on screen in the same order, so
  # the pair has to say which view you are reading: the current one is filled in
  # rather than outlined, and says so in its accessible name for anyone who
  # cannot see the fill. It still links to itself, which keeps it in the tab
  # order and makes clicking it a no-op rather than a surprise.
  #
  # Deliberately NOT aria-current: active_links_controller is mounted on <body>
  # and rewrites that attribute on every <a> on the page, deciding by exact
  # query-string match -- which these two links lose on param order alone
  # (?view=summary&year=2024 against a ?year=2024&view=summary address bar). A
  # server-rendered aria-current here survives the response and is gone by the
  # time anyone reads it. The name is somewhere nothing else reaches.
  def radio_checkout_view_button(label, icon:, current:, url:)
    label = safe_join([label, tag.span(" (current view)", class: "sr-only")]) if current

    button_link label, current ? :primary : :secondary, url, { icon:, icon_type: :solid }
  end

  # How long the radio has been gone. Rendered in hours and minutes the way
  # upstream's hour-minute-format does, until a day has passed: this report
  # measures an open checkout against right now, so a radio still marked out
  # from a past event reads "17520:00" -- true, unreadable, and the reason the
  # Asset History sibling hands anything longer to the same day_hour_format.
  def radio_checkout_duration(row) = hour_minute_or_day_format(row.duration)

  # What an empty page means depends on which view asked. The chase list going
  # quiet is the good outcome and should say so; an empty after-action summary
  # means no radio was held long and none is missing.
  def radio_checkout_empty_message(summary_view, year)
    return "No radios were held past #{RadioCheckoutReport::HOUR_LIMIT} hours in #{year}, " \
           "and none are unaccounted for." if summary_view

    "No radios have been out longer than #{RadioCheckoutReport::HOUR_LIMIT} hours."
  end
end
