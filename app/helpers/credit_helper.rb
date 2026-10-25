# frozen_string_literal: true

module CreditHelper
  def credit_format(credits)
    credits = credits.to_f
    if credits.zero?
      "zero credits"
    elsif credits == 1
      "1 credit"
    else
      "#{"%.2f" % credits} credits"
    end
  end

  # Short format for hero stats badges (number only, no "credits" text)
  def credit_format_short(credits)
    credits = credits.to_f
    credits.zero? ? "0" : "%.2f" % credits
  end
end
