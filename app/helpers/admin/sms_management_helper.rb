# frozen_string_literal: true

# Administration › SMS Management: Twilio's log of the account's texts, the
# account panel, and the Twilio settings card.
module Admin::SmsManagementHelper
  SMS_FILTER_CHIP_LABELS = { to: "To", from: "From", sent_after: "Sent on or After",
                             sent_before: "Sent on or Before" }.freeze

  # Twilio's own words for what became of a text, in the order the panel
  # counts them; any other it reports follows. The two that mean the text did
  # not arrive are marked.
  TWILIO_TEXT_STATUSES = %w[delivered sent undelivered failed received].freeze
  TWILIO_TEXT_VARIANTS = { "undelivered" => :warning, "failed" => :error }.freeze
  # A text's status in the log: the troubles marked, and delivered as success.
  TWILIO_STATUS_BADGES = TWILIO_TEXT_VARIANTS.merge("delivered" => :success, "read" => :success).freeze
  TWILIO_ALERT_VARIANTS = { "error" => :error, "warning" => :warning }.freeze
  # A Twilio id: a two-letter type (AC account, IS Notify service, MG messaging
  # service) and 32 hex digits.
  TWILIO_SID = /\b[A-Z]{2}\h{32}\b/

  # Why Lookup says a number is not valid, in words.
  LOOKUP_VALIDATION_ERRORS = {
    "TOO_SHORT" => "it is too short",
    "TOO_LONG" => "it is too long",
    "INVALID_LENGTH" => "it is the wrong length",
    "INVALID_COUNTRY_CODE" => "its country code is not one Twilio knows",
    "INVALID_BUT_POSSIBLE" => "it has the right form, but no such number is in use",
    "NOT_A_NUMBER" => "it is not a phone number"
  }.freeze

  # Lookup's line types, in words.
  LINE_TYPES = {
    "mobile" => "Mobile", "landline" => "Landline", "fixedVoip" => "Fixed VoIP", "nonFixedVoip" => "Non-fixed VoIP",
    "tollFree" => "Toll-free", "personal" => "Personal", "premium" => "Premium rate", "sharedCost" => "Shared cost",
    "uan" => "Universal access", "voicemail" => "Voicemail", "pager" => "Pager", "unknown" => "Unknown"
  }.freeze

  # One chip per active filter; each URL drops that one filter, keeps the rest
  # and starts again at Twilio's first page.
  def sms_filter_chips(form)
    filter_chips(form.active_filters, SMS_FILTER_CHIP_LABELS) do |remaining, _key|
      admin_sms_management_path(SmsFilterForm::PARAM_SCOPE => remaining)
    end
  end

  # The log page Twilio's neighbouring page { page:, token: } leads to.
  def sms_log_page_path(form, neighbour)
    admin_sms_management_path(form.query_params(page: neighbour[:page], page_token: neighbour[:token]))
  end

  # Who has the number at the Ranger's end of a text, by the log's lookup.
  def sms_text_person(people, text)
    person = people[text.number]
    person_display_link(person, person&.id)
  end

  def sms_setting_badge(present)
    if present
      ui_badge "Set", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "Missing", :error, icon: "circle-xmark", icon_type: :solid
    end
  end

  # A Twilio id with all but its two-letter type and last four characters
  # hidden: enough to tell two apart, not enough to use.
  def sms_masked_id(id)
    "#{id.first(2)}…#{id.last(4)}"
  end

  # Twilio's error text names a resource by its full id (".../Accounts/AC…");
  # the page shows every id masked, as the settings card does.
  def sms_mask_sids(text)
    text.to_s.gsub(TWILIO_SID) { |sid| sms_masked_id(sid) }
  end

  # A webhook address as the page shows it: scheme, host, port and path. A
  # user name, password or query on it stays off the page.
  def sms_url_shown(url)
    return "(not set)" if url.blank?

    uri = URI.parse(url)
    port = ":#{uri.port}" unless uri.port == uri.default_port
    "#{uri.scheme}://#{uri.host}#{port}#{uri.path}"
  rescue URI::InvalidURIError
    "(unreadable)"
  end

  # This server's address for the texts Rangers send: the one their signatures
  # are checked against, never the address this page was reached at, so it is
  # the one Twilio must be given.
  def sms_incoming_address = TwilioSignatureConcern.address(infrastructure_sms_inbound_path)

  # Where Twilio posts the texts Rangers send, against this server's own
  # address for them.
  def twilio_incoming_badge(service, here)
    if service[:defers_to_number]
      ui_badge "Each number's own", :warning, icon: "triangle-exclamation", icon_type: :solid
    elsif service[:incoming_url].blank?
      ui_badge "Not set", :warning, icon: "triangle-exclamation", icon_type: :solid
    elsif service[:incoming_url] == here
      ui_badge "This server", :success, icon: "circle-check", icon_type: :solid
    else
      ui_badge "Another server", :warning, icon: "triangle-exclamation", icon_type: :solid
    end
  end

  # Why the panel does not offer to change where Twilio sends incoming texts,
  # or nil when it does. It is offered only once Twilio read the Messaging
  # Service in TwilioMessagingServiceId, the one service the change reads
  # again and makes. (The Groundhog Day Server never draws the panel at all.)
  def twilio_incoming_lock(status)
    return unless status[:messaging_service].key?(:error)

    "The address can be changed here once TwilioMessagingServiceId names a Messaging Service Twilio can read."
  end

  # One of TwilioStatus's answers: the block's rendering of what Twilio said,
  # or why it could not be read.
  def twilio_answer(answer, &)
    return capture(answer[:value], &) if answer.key?(:value)

    safe_join([ui_badge("Could not be read", :warning, icon: "triangle-exclamation", icon_type: :solid),
               tag.span(sms_mask_sids(answer[:error]), class: "text-sm")], " ")
  end

  def twilio_account_badges(account)
    badges = if account[:status] == "active"
               [ui_badge("Active", :success, icon: "circle-check", icon_type: :solid)]
             else
               [ui_badge(account[:status].to_s.capitalize, :error, icon: "circle-xmark", icon_type: :solid)]
             end
    badges << ui_badge("Subaccount", :secondary) if account[:subaccount]
    # A trial account texts only the numbers verified on it.
    badges << ui_badge("Trial account", :warning, icon: "triangle-exclamation", icon_type: :solid) if account[:type] == "Trial"
    safe_join(badges, " ")
  end

  # Twilio's count of the day's texts by what became of them:
  # "1,201 delivered · 31 undelivered · 2 failed".
  def twilio_text_counts(counts)
    return "Twilio lists no texts from the last 24 hours." if counts.empty?

    statuses = (TWILIO_TEXT_STATUSES & counts.keys) | counts.keys
    parts = statuses.map do |status|
      text = "#{number_with_delimiter(counts[status])} #{status}"
      TWILIO_TEXT_VARIANTS[status] ? ui_badge(text, TWILIO_TEXT_VARIANTS[status]) : text
    end
    safe_join(parts, " · ")
  end

  # What became of one text, in Twilio's word for it.
  def twilio_status_badge(status)
    ui_badge status, TWILIO_STATUS_BADGES.fetch(status, :secondary)
  end

  def twilio_alert_badge(level)
    ui_badge level.capitalize, TWILIO_ALERT_VARIANTS.fetch(level, :secondary)
  end

  # Built from the code rather than taken from Twilio's answer, so the page
  # never prints a link Twilio's answer chose.
  def twilio_error_link(code)
    return "—" unless code.to_i.positive?

    link_to code.to_s, "https://www.twilio.com/docs/api/errors/#{code.to_i}", target: "_blank", rel: "noopener"
  end

  # Whether Lookup found the number valid, and if not, why.
  def sms_lookup_validity(answer)
    return ui_badge("Valid", :success, icon: "circle-check", icon_type: :solid) if answer.valid

    reasons = answer.validation_errors.map { |code| LOOKUP_VALIDATION_ERRORS.fetch(code, code) }
    safe_join([ui_badge("Not valid", :error, icon: "triangle-exclamation", icon_type: :solid),
               (" #{reasons.to_sentence.upcase_first}." if reasons.any?)])
  end

  # A number's line type and carrier, as Lookup gave them -- or why it gave
  # none. A landline is why a text to it fails with error 30006.
  def sms_line_type(info)
    return "—" if info.blank?

    code = info["error_code"]
    if code.present?
      return "Twilio gives no line type for this number: a Canadian number's needs NPAC approval (Twilio error 60601)." if code.to_i == 60601

      return "Twilio could not give the line type (Twilio error #{code.to_i})."
    end

    words = LINE_TYPES.fetch(info["type"].to_s) { info["type"].presence || "Unknown" }
    words += ", #{info['carrier_name']}" if info["carrier_name"].present?
    words += ". A landline cannot get texts, so a text to it fails with Twilio error 30006." if info["type"] == "landline"
    words
  end
end
