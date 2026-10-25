# frozen_string_literal: true

module Vc::ThankYouCardsHelper
  # The address as it would be written on the envelope, one line per line of
  # the label. Returns an empty array when there is nothing to mail to, so the
  # page can say so instead of printing blank lines.
  #
  # @param person [Person]
  # @return [Array<String>]
  def thank_you_card_address_lines(person)
    # The unit is joined on plainly rather than labelled: people write it in
    # themselves, so adding a word gives addresses like "Apt Apt 2B".
    street = [person.street1, person.apt].compact_blank.join(" ").strip
    city_line = [person.city, [person.state, person.zip].compact_blank.join(" ")].compact_blank.join(", ")

    [street, person.street2.to_s.strip, city_line].compact_blank
  end

  # The country spelled out the way a reader would say it. Falls back to
  # whatever is on file when the code is not one we know.
  #
  # @param code [String]
  # @return [String]
  def thank_you_card_country(code)
    return "" if code.blank?

    CountryStateHelper::COUNTRY_LABELS[code].presence || code
  end

  # One chip per status the reader added back, each linking to the same page
  # without it.
  #
  # @param year [Integer]
  # @param include_statuses [Array<String>]
  # @return [Array<Hash>]
  def thank_you_card_filter_chips(year, include_statuses)
    include_statuses.map do |status|
      { label: "Including: #{status}",
        url: vc_thank_you_cards_path(year:, include_statuses: include_statuses - [status]) }
    end
  end

  # The one summary line above the rows, in the filter bar's count slot.
  # Missing addresses are named only when there are some.
  #
  # @param shown [Integer]
  # @param missing [Integer]
  # @return [String]
  def thank_you_card_summary_count(shown, missing)
    return "No one to send cards to" if shown.zero?

    line = "#{pluralize(shown, "person")} to send cards to"
    line += " · #{missing} with no address on file" if missing.positive?
    line
  end

  # Statuses the department does not mail are marked, so a reader can tell
  # which part of the count they just added back. The icon carries the same
  # meaning as the colour for anyone who cannot see it.
  #
  # @param status [String]
  # @return [Hash] keyword arguments for ui_stat_box
  def thank_you_card_stat_options(status)
    return { variant: :secondary, icon: "user" } unless ThankYouCardsReport::OPTIONAL_STATUSES.include?(status)

    { variant: :warning, icon: "triangle-exclamation" }
  end
end
