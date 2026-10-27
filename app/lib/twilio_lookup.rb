# frozen_string_literal: true

# Administration › SMS Management's Look Up a Number: what Twilio's Lookup v2
# knows of a number -- valid or not, how it is written at home, its country --
# for working out why a text did not arrive. The line type (mobile, landline,
# VoIP) is billed for every lookup, so it is asked for only when the person
# asking ticks the box that says so (the owner's ruling, 2026-10-26).
module TwilioLookup
  # What Twilio answered. line_type is Twilio's line_type_intelligence (type,
  # carrier_name, error_code) when it was asked for, else nil.
  Answer = Data.define(:number, :valid, :national_format, :country, :validation_errors, :line_type)

  # Typed as a phone number: digits, and what is written between them.
  PHONE_LIKE = /\A[\d\s()+.\-]+\z/

  module_function

  # The number to look up for what was typed -- a phone number, or a
  # callsign's number on file -- or why there is none: [number, problem].
  def number_for(typed)
    typed = typed.to_s.strip
    return [nil, "Enter a phone number or a callsign."] if typed.empty?
    return [request_form(typed), nil] if PHONE_LIKE.match?(typed)

    person = Person.resolve_callsign(typed)
    return [nil, unknown_callsign(typed)] if person.nil?
    return [nil, "#{person.callsign} has no text number on file."] if person.sms_number.blank?

    [request_form(person.sms_number), nil]
  end

  # Ask Twilio about number: { answer: } or { problem: }, Twilio's refusal in
  # words or why it could not be asked.
  def look_up(number, line_type: false)
    client = TwilioAccount.client
    return { problem: "The Clubhouse cannot ask Twilio until the Account SID and Auth Token are set." } if client.nil?

    request = line_type ? { fields: "line_type_intelligence" } : {}
    phone = client.lookups.v2.phone_numbers(number).fetch(**request)
    { answer: Answer.new(number: phone.phone_number, valid: phone.valid, national_format: phone.national_format,
                         country: phone.country_code, validation_errors: Array(phone.validation_errors),
                         line_type: (phone.line_type_intelligence if line_type)) }
  rescue *TwilioAccount::ERRORS => e
    { problem: "Twilio could not look it up: #{TwilioAccount.describe(e)}." }
  end

  # A number as Lookup takes it in its address, which twilio-ruby does not
  # escape: E.164 where it can be read, else only its digits and any plus.
  def request_form(number)
    normalized = SmsService.normalize_phone(number)
    normalized.start_with?("+") ? normalized : number.gsub(/[^\d+]/, "")
  end

  # Person.resolve_callsign finds no one both for a callsign nobody has and
  # for one that, written loosely, could be two people.
  def unknown_callsign(typed)
    if Person.where(callsign_normalized: WordUtils.normalize_word(typed)).limit(2).count > 1
      "#{typed} could be more than one Ranger: enter the whole callsign, or the number."
    else
      "No Ranger has the callsign #{typed}."
    end
  end
end
