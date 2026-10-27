# frozen_string_literal: true

module Communication
  # The words a sender reads about each kind of broadcast: when it is the right
  # one, who it reaches, and anything they should know before sending it.
  module RbsHelper
    # on_playa: used while the event is running, and grouped that way
    # variant:  how serious it is, which decides the card's colour
    TYPES = {
      Broadcast::TYPE_EMERGENCY => {
        title: "Emergency Broadcast",
        icon: "bell",
        variant: :error,
        on_playa: true,
        situation: "Fire, fatality, plane crash — every Ranger is needed now.",
        reaches: "every on-playa Ranger who is not already on a shift",
        note: "No one can opt out of this message. Be brief and choose your words carefully."
      },
      Broadcast::TYPE_ONSHIFT => {
        title: "Text Everyone on Shift",
        icon: "walkie-talkie",
        variant: :warning,
        on_playa: true,
        situation: "Radio repeater down, a city split is about to happen.",
        reaches: "the Rangers who are on a shift right now",
        note: "Text only, and only to those carrying a phone. Delivery is not guaranteed."
      },
      Broadcast::TYPE_RECRUIT_DIRT => {
        title: "Call Up Off-Duty Dirt Rangers",
        icon: "people-group",
        variant: :primary,
        on_playa: true,
        situation: "The city is understaffed and HQ needs more Dirt Rangers.",
        reaches: "off-duty Rangers who are on site"
      },
      Broadcast::TYPE_RECRUIT_POSITION => {
        title: "Call Up an Off-Duty Special Team",
        icon: "user-group",
        variant: :primary,
        on_playa: true,
        situation: "A team shift — Green Dots, LEAL, Shift Leads — is short-handed.",
        reaches: "off-duty holders of one team position who are on site"
      },
      Broadcast::TYPE_SLOT => {
        title: "Shift Sign-Ups",
        icon: "calendar-check",
        variant: :secondary,
        on_playa: false,
        situation: "A time change or other news about one particular shift.",
        reaches: "everyone signed up for that shift"
      },
      Broadcast::TYPE_POSITION => {
        title: "Team or Position",
        icon: "users",
        variant: :secondary,
        on_playa: false,
        situation: "Meeting requests and team news.",
        reaches: "everyone who holds a position or is on a team"
      },
      Broadcast::TYPE_GENERAL => {
        title: "General Broadcast",
        icon: "bullhorn",
        variant: :secondary,
        on_playa: false,
        situation: "Season-wide news for a broad audience.",
        reaches: "most Clubhouse accounts, narrowed by status and attendance"
      }
    }.freeze

    CHANNEL_ICONS = { "Text" => "comment-sms", "Email" => "envelope", "Clubhouse" => "comments" }.freeze

    # Why a text or an email cannot reach someone, in words a sender can act on.
    RECIPIENT_BLOCK_REASONS = {
      Rbs::SMS_STATUS_NO_PHONE => "no number",
      Rbs::EMAIL_STATUS_NO_ADDRESS => "no address",
      Rbs::SMS_STATUS_UNVERIFIED => "number not confirmed",
      Rbs::SMS_STATUS_STOPPED => "asked to stop",
      Rbs::SMS_STATUS_NO_CONTACT => "opted out",
      # The record does not say which of the two; the person's page does.
      Rbs::EMAIL_STATUS_SUPPRESSED => "bounce or spam report on file"
    }.freeze

    # The account statuses a broadcast may be aimed at. Some statuses are never
    # messaged at all, so offering them would promise something that cannot
    # happen. Statuses read exactly as they are stored.
    def rbs_status_options
      (Person::LIVE_STATUSES - Person::NO_MESSAGES_STATUSES).map { |status| [status, status] }
    end

    # How a position broadcast may be narrowed by this year's sign-ups.
    def rbs_signed_up_options
      [["Anyone who holds the position", Rbs::SIGNED_UP_ANY],
       ["Only those signed up for one of its shifts this year", Rbs::SIGNED_UP_YES],
       ["Only those not signed up for one of its shifts this year", Rbs::SIGNED_UP_NO]]
    end

    # How a general broadcast may be narrowed by in-person training.
    def rbs_training_options
      [["Does not matter", Rbs::TRAINING_ANY],
       ["Passed in-person training", Rbs::TRAINING_PASSED],
       ["Signed up for or passed in-person training", Rbs::TRAINING_REGISTERED],
       ["Not signed up for in-person training", Rbs::TRAINING_NONE]]
    end

    # A shift as it reads in the picker: when it is, what it is called, and how
    # many people are already signed up for it.
    #
    # The date is written out here rather than taken from the shared date helper:
    # that one returns marked-up text, which a list of choices can only show as
    # the tags themselves.
    def rbs_slot_label(slot)
      "#{slot.begins.strftime(DateTimeHelper::MONTH_DAY_TIME)} — #{slot.description} " \
        "(#{pluralize(slot.signed_up, "sign-up")})"
    end

    def rbs_type(type)
      TYPES.fetch(type)
    end

    def rbs_type_title(type)
      rbs_type(type)[:title]
    end

    def rbs_type_on_playa?(type)
      rbs_type(type)[:on_playa]
    end

    # Which channels this kind of broadcast can use. The short ones always text,
    # and email as well unless they are text-only; the rest offer all three.
    def rbs_type_channels(type)
      attrs = Rbs::ATTRIBUTES[type] || {}
      return %w[Text Email Clubhouse] unless attrs[:is_simple]

      attrs[:sms_only] ? %w[Text] : %w[Text Email]
    end

    # An alert type as senders and readers see it named, which says when in the
    # season it applies. Two alerts share a title, so the prefix is what tells
    # them apart.
    def rbs_alert_label(alert)
      return "—" if alert.nil?

      "#{alert.on_playa ? "On playa" : "Pre-event"}: #{alert.title}"
    end

    def rbs_alert_options(alerts)
      alerts.map { |alert| [rbs_alert_label(alert), alert.id] }
    end

    # What the sender chose, in the order the form asked for it, so the review
    # page can be read against the page before it.
    def rbs_criteria_rows(form)
      rows = []
      rows << ["Alert", rbs_alert_label(Alert.find_by(id: Rbs.alert_id_for(form.type, form.alert_id)))]
      rows << ["Shift", rbs_slot_summary(form.slot_id)] if form.has_slot?
      rows << ["Account status", form.statuses.to_sentence] if form.has_status?

      if form.has_position?
        rows << ["Positions", rbs_position_summary(form.position_ids)]
        rows << ["Shift sign-ups", rbs_label_for(rbs_signed_up_options, form.position_signed_up)]
      end

      rows << ["Position", rbs_position_summary([form.position_id])] if form.has_muster_position?

      if form.has_restrictions?
        rows << ["Attendance", rbs_attendance_summary(form)]
        rows << ["In-person training", rbs_label_for(rbs_training_options, form.training)]
      end

      rows << ["No longer relevant after", datetime_format(form.expires_at_time, year: true)] if form.expires_at_time
      rows
    end

    def rbs_position_summary(position_ids)
      ids = Array(position_ids).compact
      return "—" if ids.empty?

      Position.titles_by_id(ids).values.sort.to_sentence
    end

    def rbs_slot_summary(slot_id)
      slot = Rbs.slot_choice(slot_id)
      return "—" if slot.nil?

      [slot.position_title, rbs_slot_label(slot)].compact.join(" — ")
    end

    def rbs_attendance_summary(form)
      chosen = []
      chosen << "signed up for a shift during the event, or has said they are here" if form.on_site
      chosen << "signed up for anything this year" if form.attending
      chosen.any? ? chosen.to_sentence(two_words_connector: ", or ", last_word_connector: ", or ") : "Everyone"
    end

    def rbs_label_for(options, value)
      options.find { |_label, option| option == value }&.first || value
    end

    # The channel badges shown on a card and beside a sent broadcast.
    def rbs_channel_badges(channels)
      safe_join(channels.map { |channel| ui_badge(channel, :secondary, icon: CHANNEL_ICONS[channel]) }, " ")
    end

    # The channels this broadcast will use, as the sender chose them.
    def rbs_sending_channels(form)
      channels = []
      channels << "Text" if form.sends_sms?
      channels << "Email" if form.sends_email?
      channels << "Clubhouse" if form.sends_clubhouse?
      channels
    end

    # Whether a channel can reach one person, with the reason it cannot when
    # there is one. The word carries the meaning; the icon only repeats it.
    def rbs_channel_cell(usable, reason = nil)
      return safe_join([fa_icon("check", :solid, class: "icon-success"), " yes"]) if usable

      tag.span(RECIPIENT_BLOCK_REASONS.fetch(reason, "—"), class: "text-stone-subtle")
    end

    # What became of one person's text message.
    def rbs_delivery_cell(status)
      case status
      when Broadcast::STATUS_SENT
        safe_join([fa_icon("check", :solid, class: "icon-success"), " sent"])
      when Broadcast::STATUS_SERVICE_FAIL
        tag.span(safe_join([fa_icon("triangle-exclamation", :solid), " failed"]), class: "text-error")
      else
        tag.span(RECIPIENT_BLOCK_REASONS.fetch(status, "—"), class: "text-stone-subtle")
      end
    end

    # A message handed to a queue: it has not been delivered yet, and nothing
    # here can say whether it will be.
    def rbs_queued_cell(usable, status = nil)
      return rbs_delivery_cell(status) if status.present?
      return safe_join([fa_icon("check", :solid, class: "icon-success"), " queued"]) if usable

      tag.span("—", class: "text-stone-subtle")
    end

    def rbs_not_sent
      tag.span("not sent", class: "text-stone-subtle")
    end

    # A channel the broadcast does not use, in every row of the review table:
    # one word, never a reason, so the column does not read as people the
    # broadcast misses. "not sent" would sit oddly under "Nothing has been sent
    # yet".
    def rbs_not_used
      tag.span("not used", class: "text-stone-subtle")
    end

    # A count that only matters when it is not zero: badged when it is, plain
    # when it is not, so the eye lands on the rows that need doing something
    # about.
    def rbs_count_cell(count, variant)
      return count.to_s unless count.positive?

      ui_badge(count.to_s, variant)
    end

    # -----------------------------------------------------------------------
    # The message log
    # -----------------------------------------------------------------------

    # What a message log row means, in words rather than the codes the record
    # keeps. Outbound rows say what the Clubhouse did; inbound rows say what the
    # phone asked for.
    MESSAGE_STATUS_LABELS = {
      Broadcast::STATUS_SENT => "Sent",
      Broadcast::STATUS_DELIVERED => "Delivered",
      Broadcast::STATUS_QUEUED => "Queued",
      Broadcast::STATUS_SERVICE_FAIL => "Delivery failed",
      Broadcast::STATUS_VERIFY => "Confirmation code sent",
      Broadcast::STATUS_REPLY => "Replied",
      Broadcast::STATUS_START => "Asked to start",
      Broadcast::STATUS_STOP => "Asked to stop",
      Broadcast::STATUS_HELP => "Asked for help",
      Broadcast::STATUS_STATS => "Asked for a summary",
      Broadcast::STATUS_NEXT => "Asked for their next shift",
      Broadcast::STATUS_UNKNOWN_COMMAND => "Not understood",
      Broadcast::STATUS_UNKNOWN_PHONE => "Unknown number",
      Broadcast::STATUS_BOUNCED => "Bounced",
      Broadcast::STATUS_BLOCKED => "Blocked",
      # Never sent: the address bounced for good, or its owner reported spam.
      Rbs::EMAIL_STATUS_SUPPRESSED => "Bounce or spam report on file",
      # Never sent: its person opted out of the alert's email, or has no address
      # on file. The Address cell tells which: empty for no address.
      Rbs::EMAIL_STATUS_NO_CONTACT => "Opted out or no address on file",
      # Why a broadcast email did not go, by the reason Amazon SES gave.
      "message-rejected" => "Rejected by SES",
      Broadcast::STATUS_INVALID_PARAMETER => "Invalid address on file",
      "transient-failure" => "SES temporary failure",
      "account-throttled" => "SES rate limit",
      "account-daily-quota-exceeded" => "SES daily limit reached",
      "account-sending-paused" => "SES sending paused",
      "configuration-set-sending-paused" => "SES configuration set paused",
      "account-suspended" => "SES account suspended",
      "mail-from-domain-not-verified" => "Sender not verified in SES",
      "configuration-set-not-found" => "SES configuration set missing",
      "template-not-found" => "SES template missing",
      "invalid-sending-pool-name" => "SES sending pool missing",
      # Any other reason SES gives, or a text Twilio says it could not deliver.
      Broadcast::STATUS_FAILED => "Not delivered",
      # SES's or Twilio's: the call may have gone through, and no answer came.
      Broadcast::STATUS_SEND_UNCONFIRMED => "May have been sent"
    }.freeze

    MESSAGE_STATUS_VARIANTS = {
      Broadcast::STATUS_SENT => :success,
      Broadcast::STATUS_DELIVERED => :success,
      Broadcast::STATUS_REPLY => :success,
      Broadcast::STATUS_START => :success,
      Broadcast::STATUS_BOUNCED => :error,
      Broadcast::STATUS_BLOCKED => :error,
      Broadcast::STATUS_STOP => :warning,
      Broadcast::STATUS_UNKNOWN_COMMAND => :warning,
      Broadcast::STATUS_UNKNOWN_PHONE => :warning,
      **Broadcast::FAILURE_STATUSES.index_with(:error)
    }.freeze

    def rbs_message_status_label(status)
      MESSAGE_STATUS_LABELS.fetch(status, status)
    end

    def rbs_message_status_badge(status)
      ui_badge(rbs_message_status_label(status), MESSAGE_STATUS_VARIANTS.fetch(status, :secondary))
    end

    # The outcomes the message log can be filtered by, in two groups: what
    # happened to any message, and the reasons a broadcast email did not go --
    # twelve of those would bury the rest in one list. A text can be
    # send-unconfirmed or failed too, so those two sit with the first group.
    def rbs_message_status_options(email_failures: false)
      statuses = Broadcast::EMAIL_FAIL_STATUSES - [Broadcast::STATUS_SEND_UNCONFIRMED, Broadcast::STATUS_FAILED]
      statuses = Broadcast::MESSAGE_STATUSES - statuses unless email_failures

      statuses.map { |status| [status, rbs_message_status_label(status)] }
    end

    def rbs_direction_options
      [UiComponents::FilterBarHelper::ALL_FILTER_OPTION,
       ["Incoming from phones", "inbound"], ["Outgoing from the Clubhouse", "outbound"]]
    end

    # Which way one message points: out from the Clubhouse, or in from a phone.
    # Never whether it went; the Outcome says that.
    def rbs_direction_cell(message)
      icon = message.direction == "inbound" ? "arrow-left" : "arrow-right"
      safe_join([fa_icon(icon, :solid, class: "text-stone-icon"), " #{rbs_direction_word(message.direction)}"])
    end

    # The one pair of words for a direction, wherever it is written out: the
    # log's cell, and an export.
    def rbs_direction_word(direction)
      direction == "inbound" ? "incoming" : "outgoing"
    end

    # The broadcast a message went out in, as a link to its record. A message
    # outside any broadcast -- a text a phone sent in, a reply, a confirmation
    # code -- has a dash.
    def rbs_broadcast_link(message)
      return tag.span("—", class: "text-stone-subtle") unless message.broadcast_id

      link_to "##{message.broadcast_id}", communication_rbs_history_broadcast_path(message.broadcast_id),
              class: "underline"
    end

    # Whether a message carries text worth opening: what a phone sent in, and
    # what was sent back to it.
    def rbs_message_has_text?(message)
      message.direction == "inbound" || message.status == Broadcast::STATUS_REPLY
    end

    # One chip per filter narrowing the message log.
    def rbs_message_filter_chips(form, year)
      filter_chips(form.active,
                   { callsign: "Callsign", direction: "Direction", status: "Outcome" },
                   value_label: lambda { |key, value|
                     case key
                     when :direction then rbs_label_for(rbs_direction_options, value)
                     when :status then value.split(", ").map { |s| rbs_message_status_label(s) }.to_sentence
                     else value
                     end
                   }) do |remaining|
        communication_rbs_messages_path({ year: }.merge(
                                          RbsMessageLogFilterForm::PARAM_SCOPE => remaining
                                        ))
      end
    end

    # A phone number or email address as the log shows it.
    def rbs_message_address(message)
      return message.address if message.address_type != "sms"

      PhoneFormatter.format(message.address)
    end

    # -----------------------------------------------------------------------
    # The records
    # -----------------------------------------------------------------------

    def rbs_kind_options
      [["Broadcasts", Broadcast::KIND_BROADCAST],
       ["Message alerts", Broadcast::KIND_NOTIFICATION],
       UiComponents::FilterBarHelper::ALL_FILTER_OPTION]
    end

    def rbs_delivery_options
      [UiComponents::FilterBarHelper::ALL_FILTER_OPTION, ["With failures only", "failed"]]
    end

    def rbs_alert_filter_options(alerts)
      [UiComponents::FilterBarHelper::ALL_FILTER_OPTION] +
        alerts.map { |alert| [rbs_alert_label(alert), alert.id.to_s] }
    end

    # One chip per filter that is narrowing the list, each linking to the same
    # page without it.
    #
    # Dropping the kind is not the same as leaving it out: a page arriving with
    # no kind starts on the broadcasts, so the chip that says so has to ask for
    # everything by name or clicking it changes nothing.
    def rbs_history_filter_chips(filters, year, alerts)
      titles = alerts.index_by { |alert| alert.id.to_s }
      active = UiComponents::FilterBarHelper.active_filters(filters)

      filter_chips(active, { kind: "Kind", delivery: "Delivery", alert_id: "Alert" },
                   value_label: lambda { |key, value|
                     case key
                     when :kind then rbs_label_for(rbs_kind_options, value)
                     when :delivery then rbs_label_for(rbs_delivery_options, value)
                     else rbs_alert_label(titles[value])
                     end
                   }) do |remaining, dropped|
        remaining = remaining.merge(kind: UiComponents::FilterBarHelper::ALL_FILTER) if dropped == :kind
        communication_rbs_history_path(remaining.merge(year:))
      end
    end

    # "Clear all filters" has the same problem: asking for nothing brings the
    # default back, so it asks for every kind instead.
    def rbs_history_clear_url(year)
      communication_rbs_history_path(year:, kind: UiComponents::FilterBarHelper::ALL_FILTER)
    end

    # What a broadcast said, short enough to scan a page of them.
    def rbs_broadcast_summary(broadcast)
      text = broadcast.subject.presence || broadcast.sms_message.presence
      return tag.span("—", class: "text-stone-subtle") if text.blank?

      text.truncate(70)
    end

    def rbs_delivery_badge(broadcast)
      return ui_badge("Delivered", :success, icon: "check") unless broadcast.failed?

      ui_badge("#{broadcast.sms_failed + broadcast.email_failed} failed", :error,
               icon: "triangle-exclamation")
    end

    # Why some of a broadcast's failed messages, texts or emails, stay failed:
    # one reason that covers them all. They are "It" or "They" when nothing
    # else failed that can go again.
    def rbs_unretryable_sentence(stuck, retryable)
      subject = if retryable.positive? then pluralize(stuck, "message")
                else (stuck == 1) ? "It" : "They"
                end
      "#{subject} can't be sent again. Twilio or SES may already have sent #{(stuck == 1) ? "it" : "them"}, " \
        "the address is invalid, or the Ranger can no longer be reached that way."
    end

    # The people on a broadcast's list no channel reaches (Rbs.unreachable),
    # counted and named by callsign. Their rows say why, but past the first
    # Broadcast::RECIPIENT_LIMIT the table hides them, and the sender can still
    # reach them another way, by radio or a runner. A plain String, so the
    # callsigns are escaped.
    def rbs_unreachable_sentence(unreached)
      "#{pluralize(unreached.size, "person")} on the list can't be reached by text or email: " \
        "#{unreached.map(&:callsign).to_sentence}."
    end

    # What was recorded for one person on one channel, from a broadcast that has
    # already been sent. A bounced email, or a text Twilio reported bounced or
    # blocked, looks like a failure here -- it did not arrive -- though it is not
    # counted as one.
    #
    # A no-contact row with a blank address reads "no address", as the review
    # and sent pages called that person; with an address, "opted out". The rule
    # is for the email send's skip rows, which keep the person's own address.
    # The cell can't see the channel, so a text row like that would read "no
    # address" too; none is written, since only the email send records a skip.
    def rbs_recorded_cell(entry)
      return tag.span("—", class: "text-stone-subtle") if entry.nil?

      case entry[:status]
      when Broadcast::STATUS_SENT, Broadcast::STATUS_DELIVERED
        safe_join([fa_icon("check", :solid, class: "icon-success"), " #{entry[:status]}"])
      when *Broadcast::FAILURE_STATUSES, Broadcast::STATUS_BOUNCED, Broadcast::STATUS_BLOCKED
        word = (entry[:status] == Broadcast::STATUS_SERVICE_FAIL) ? "failed" : rbs_message_status_label(entry[:status])
        tag.span(safe_join([fa_icon("triangle-exclamation", :solid), " ", word]), class: "text-error")
      else
        reason = entry[:status]
        reason = Rbs::EMAIL_STATUS_NO_ADDRESS if reason == Rbs::EMAIL_STATUS_NO_CONTACT && entry[:address].blank?
        tag.span(RECIPIENT_BLOCK_REASONS.fetch(reason, reason), class: "text-stone-subtle")
      end
    end

    # The channels one sent broadcast actually used, as icons. Each carries its
    # name for a screen reader, so the icons are never the only thing saying it.
    def rbs_channel_icons(broadcast)
      used = []
      used << "Text" if broadcast.sent_sms
      used << "Email" if broadcast.sent_email
      used << "Clubhouse" if broadcast.sent_clubhouse
      return tag.span("—", class: "text-stone-subtle") if used.empty?

      safe_join(used.map do |channel|
        safe_join([fa_icon(CHANNEL_ICONS[channel], :solid, class: "text-stone-icon", fixed: true),
                   tag.span(channel, class: "sr-only")])
      end, " ")
    end
  end
end
