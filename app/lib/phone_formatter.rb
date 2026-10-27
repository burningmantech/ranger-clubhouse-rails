# frozen_string_literal: true

# Phone numbers are stored in E.164 ("+17755550199") and shown the way their
# own country writes them.
module PhoneFormatter
  # An extension after the number -- "x12", "ext. 12", "#12", a dialer's "p12"
  # or "w12". E.164 has no room for one, so it goes, digits and all.
  EXTENSION = /(?<=\d)\s*(?:ext(?:ension|n)?\.?|x|#|;|p|w)\s*\d.*/im

  # All that may sit between a number's digits, "=" being a slip for the "-"
  # beside it. Anything else there -- a letter, a "!" or "*" that is a shifted
  # digit -- is a mistyped digit or a second number, and the number is refused:
  # dropping it would leave a shorter number that is still valid where lengths
  # vary, as in Germany ("030 12345 l7").
  PUNCTUATION = %r{\A[\d\s+()./=-]*\z}

  # o, O, l or I against a digit, not starting a word: a typo for 0 or 1
  # ("0777584550o"), where "0199office" is a note.
  LOOKALIKE = /\d[oOlI](?!\p{L})/

  # `number` in E.164, or nil when it is not a phone number. Every digit typed
  # must be in it, bar an extension's; words before or after it ("Text ...",
  # "(cell)", "wk") are dropped. One typed without a country code is read as a
  # number from `country`, or as a +1 number (the US, Canada and the rest of
  # North America); one that reads validly as both is refused, not guessed at.
  def self.e164(number, country = "US")
    number = digits_typed(number) or return
    readings = [country, "US"].uniq.filter_map { |region| reading(number, region) }.uniq
    readings.first if readings.one?
  end

  # A stored number the way its country writes it: (775) 555-0199 for any +1
  # number, and elsewhere the country's own grouping behind its code,
  # +44 121 496 0497. Anything not stored in E.164 -- a value from before
  # numbers were checked -- is shown as typed, never as a guess.
  #
  # The "US" hint is for speed alone: without one Phonelib tries every country
  # sharing +1 in turn, ten times slower, and the number is already known good.
  def self.format(number)
    return number.to_s if number.blank? || e164(number) != number

    phone = Phonelib.parse(number, "US")
    number.start_with?("+1") ? phone.national : phone.international
  end

  # The stretch of `number` from its first digit (or +) to its last, once
  # full-width digits from a CJK keyboard are plain ones, every dash (a Japanese
  # keyboard's "ー" too) is "-", invisible characters from a paste are gone, and
  # any extension is off. Nil when that stretch holds anything but digits and
  # their punctuation. Public for TwilioLookup, which asks Twilio about numbers
  # e164 would refuse.
  def self.digits_typed(number)
    number = number.to_s.unicode_normalize(:nfkc)
                   .gsub(/[\p{Cf}\p{Mn}]/, "")
                   .gsub(/[\p{Pd}ー−]/, "-")
                   .sub(EXTENSION, "")
    return if number.match?(LOOKALIKE)

    first = number.index(/[\d+]/)
    last = number.rindex(/\d/)
    return unless first && last

    number[first..last] if number[first..last].match?(PUNCTUATION)
  end

  # `number` read as one from `region`, in E.164. +1 is shared, so a number
  # that is not valid for the region is judged again as a whole: a Toronto
  # number is not a valid *US* number, but it is a valid one. Bare digits never
  # move to a third country -- eleven digits typed in the US are a typo, not a
  # call to Pakistan.
  def self.reading(number, region)
    data = Phonelib.phone_data[region] or return
    typed = Phonelib.parse(number, region)
    whole = typed.valid? ? typed : Phonelib.parse(typed.e164)
    return unless whole.valid?

    whole.e164 if typed.explicit_international_prefix? || whole.e164.start_with?("+#{data[:country_code]}")
  end
  private_class_method :reading
end
