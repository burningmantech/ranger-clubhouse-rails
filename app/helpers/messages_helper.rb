# frozen_string_literal: true

# Helper methods for the Messages interface
module MessagesHelper
  # The icon on the callout that stands in for the reply form; a walk-up, whose
  # sender has no Clubhouse account, takes the fallback.
  NO_REPLY_ICONS = {
    PersonMessage::SENDER_TYPE_RBS => "bullhorn",
    PersonMessage::SENDER_TYPE_TEAM => "people-group"
  }.freeze

  def message_no_reply_icon(message)
    NO_REPLY_ICONS.fetch(message.sender_type, "user-slash")
  end
  # Renders a folder tab for the mailbox's tab row
  #
  # @param label [String] The tab label text
  # @param folder [String] The folder constant
  # @param current_folder [String] The currently active folder
  # @param badge [Integer, nil] The Unread count (messages_unread_badge)
  # @return [String] HTML for the folder tab
  def messages_folder_tab(label, folder, current_folder, badge: nil)
    is_active = current_folder == folder
    path = messages_path(folder: folder)

    content_tag(:a,
                href: path,
                class: class_names("tab", "no-decoration", "tab-active": is_active),
                role: "tab",
                aria: {
                  selected: is_active,
                  controls: "messages-conversation-list"
                },
                data: {
                  turbo_stream: true
                }) do
      badge ? safe_join([label, " ", messages_unread_badge(badge)]) : label
    end
  end

  # The Unread tab's count. Always on the tab, hidden at zero, so a stream can
  # replace it by its id without re-rendering the tab row and its active tab: a
  # live reply (PersonMessage#announce_reply) and a thread read in the
  # pane (MessagesConcern#read_state_streams).
  def messages_unread_badge(count)
    ui_badge(count.to_s, :warning, size: "xs", id: "messages-unread-count", hidden: count.zero?)
  end

  # A thread's address in the mailbox of +owner+, under the namespace showing it
  # (MessagesConcern#messages_route_prefix). The list row asks this rather than
  # the controller's message_path, since a broadcast render has no controller.
  def mailbox_message_path(namespace, owner, message, **)
    send(:"#{namespace}_message_path", *([owner] unless namespace == "me"), message, **)
  end

  # The list stamp: the clock time for a thread that moved today, the date
  # otherwise, and the year once it is not this year. The full stamp stays on
  # the thread page; in the list it crowded the callsign off a phone-width row.
  # The app's clock, which datetime_format prints the thread on, so the two
  # never disagree about the day.
  def message_list_time(time)
    local = time.in_time_zone
    today = Current.today
    return local.strftime(DateTimeHelper::HOUR_MINS) if local.to_date == today

    local.strftime(local.year == today.year ? "%b %-d" : DateTimeHelper::DATE)
  end

  # The line over a search's hits: how many threads it found, and that it looked
  # in every folder, since the tab row is gone while it shows.
  def message_search_summary(count, query)
    return "No conversations match “#{query}” in any folder" if count.zero?

    "#{pluralize(count, "conversation")} #{count == 1 ? "matches" : "match"} “#{query}” in every folder"
  end

  # +text+ with whatever the search matched marked (PersonMessage.search_pattern).
  # Built with safe_join, so the message text around the marks is escaped.
  def message_search_marks(text, query)
    return text if query.blank?

    mark_search_hits(text, message_search_pattern(query))
  end

  # A list row's last line: the latest message in the thread; on a search's
  # hit, five words either side of the first match in the thread, top first,
  # marked -- or the latest message still, for a hit on the subject or the
  # other party's callsign alone. Both read the text the search matched
  # (body_text), never the editor's markup.
  def message_list_snippet(message, query)
    rows = [message, *message.replies]
    if query.present?
      pattern = message_search_pattern(query)
      text = rows.lazy.map(&:body_text).find { |body| body.match?(pattern) }
      return mark_search_hits(excerpt(text, pattern, radius: 5, separator: " ", omission: "…"), pattern) if text
    end
    truncate(rows.last.body_text, length: 70)
  end

  # The Cadres and Delegations compose can send to, for its select.
  def message_team_options
    Team.messageable.order(:title).pluck(:title, :id)
  end

  # The Cadres and Delegations the mailbox owner may send a message as, for
  # compose's From select: none for most people, and none on the HQ window's
  # relay (group_send_allowed?), and then the select is not shown.
  def message_sender_team_options
    return [] unless group_send_allowed?

    Team.cadres_and_delegations_of(message_owner.id).order(:title).pluck(:title, :id)
  end

  # What the list row and pane header put before the party: "To:" on a thread
  # the owner started or is in as a group, "From:" when that group thread was
  # sent as a team the owner is not in; nothing on a message a person sent them.
  def message_address_label(message, owner)
    return unless message.sender?(owner.id) || message.group?

    message.addressed_from_team?(owner.id) ? "From:" : "To:"
  end

  # Who the mailbox owner's side of a thread is with, as its list row and pane
  # header name them: a group thread's teams and other named members, the
  # person the owner wrote to, or the sender.
  def message_party_name(message, owner)
    return message.group_party_names(owner.id).join(", ") if message.group?
    return message.person&.callsign || PersonMessage.deleted_name(message.person_id) if message.sender?(owner.id)

    message.sender_name
  end

  # Where reading a thread never marks it read (Person and HQ), the reader works
  # through the person's unread threads by hand: the id of the thread after
  # +message+ in their Unread folder, in the folder's own order, wrapping past
  # the end; the folder's first when +message+ is no longer in it (just marked
  # read); nil when no other is left.
  def next_unread_id(message)
    ids = PersonMessage.unread_thread_ids(message_owner.id)
    index = ids.index(message.id)
    index ? ids.rotate(index + 1).find { |id| id != message.id } : ids.first
  end

  # Returns the count of unread messages for the mailbox owner
  #
  # @return [Integer] The unread message count
  def unread_message_count
    @unread_message_count ||= PersonMessage.count_unread(message_owner.id)
  end

  private

  # Built once per render: every row of a search marks the same query.
  def message_search_pattern(query)
    (@message_search_patterns ||= {})[query] ||= /(#{PersonMessage.search_pattern(query)})/
  end

  # The pattern holds one group, so split hands back each match at an odd index.
  def mark_search_hits(text, pattern)
    parts = text.to_s.split(pattern)
    safe_join(parts.each_with_index.map { |part, index| index.odd? ? tag.mark(part, class: "search-hit") : part })
  end
end
