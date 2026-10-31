# frozen_string_literal: true

# Shared mailbox behavior for the end-user (me/messages) and person-management
# (person/:id/messages) interfaces. Every action operates from the perspective
# of +message_owner+ — the mailbox owner — so folders, read/archive state, and
# reply participants resolve identically whether the owner or a manager is
# driving. Including controllers supply the owner, the route namespace, and
# (optionally) how compose participants are resolved.
module MessagesConcern
  extend ActiveSupport::Concern

  NO_CALLSIGNS_MATCHED = "No callsigns matched."

  # The relay (group_send_allowed? false) refusing a group send: a team to
  # send to or as, or more than one callsign.
  RELAY_ONE_SENDER = "A relayed message comes from one sender."

  # Under a suggested callsign whose person last signed in over two years ago.
  AWAY_TOO_LONG = ["Hasn't logged in for over 2 years.", "They may not receive notifications."].freeze

  # The most people a search names as chips (?with[]=): the field replaces the
  # oldest with a fourth, and #search_chips reads no more than this.
  MAX_SEARCH_WITH = 3

  # Over the people the search field suggests: what taking one does.
  SUGGESTED_PEOPLE = "People — Add as a Filter"

  included do
    before_action :set_message, only: %i[show create_reply toggle_read toggle_archive mark_read]
    # Suggestions are JSON, fetched as the reader types: no layout, so no menu.
    skip_before_action :build_menu_items, only: %i[suggest suggest_callsigns]

    helper_method :message_owner, :messages_route_prefix, :search_query, :search_with, :searching?, :search_scope,
                  :lookup_label, :lookup_role_label, :direction_params,
                  :mark_read_on_view?, :mark_read_message_path,
                  :messages_path, :message_path, :new_message_path, :suggest_messages_path,
                  :find_recipient_messages_path, :search_callsigns_messages_path, :suggest_callsigns_messages_path,
                  :select_callsign_messages_path, :create_reply_message_path, :group_send_allowed?,
                  :toggle_read_message_path, :toggle_archive_message_path
  end

  def index
    @folder = normalize_folder(params[:folder])
    @messages = retrieve_list_messages
    # The thread page's list loads itself once on screen (_list_frame), and the
    # search field loads it in place; that request gets the list's frame alone,
    # its open thread marked by ?selected=. The search field always sends q,
    # blank or not: then the tab row rides inside, since a search takes the tabs
    # away and a blank one brings them back.
    if list_request?
      selected_id = Integer(params[:selected].to_s, exception: false)
      streams = params.key?(:q) ? [folder_selector_stream] : []
      return render partial: "common/messages/list_frame",
                    locals: { folder: @folder, messages: @messages, selected_id:, streams: }
    end

    respond_to do |format|
      format.html
      format.turbo_stream { render turbo_stream: folder_streams(@messages) }
    end
  end

  # The thread in the workspace's pane, beside the folder's list. A row's link
  # loads the pane's own frame; nothing outside it changes for that, so that
  # request gets the pane alone -- no list, no hero, no layout -- rather than
  # the whole page for Turbo to throw away. What reading it changed outside the
  # pane rides along inside the frame (#read_state_streams). The full page loads
  # no list: it loads itself (_list_frame).
  def show
    newly_read = mark_read_on_view? && !@message.thread_read?(message_owner.id)
    @message.mark_thread_read!(message_owner.id) if newly_read
    @reply_form = new_reply_form
    @folder = normalize_folder(params[:folder])
    return unless pane_request?

    render partial: "common/messages/pane",
           locals: { message: @message, folder: @folder, reply_form: @reply_form,
                     streams: newly_read ? read_state_streams : [] }
  end

  def toggle_read
    read = @message.toggle_thread_read!(message_owner.id)
    render_message_flags("Message marked as #{read ? "read" : "unread"}.", thread: true)
  end

  # The open thread, when a reply lands in it while the page is on screen
  # (thread_live_controller; ruling D6 of the messaging rework). Idempotent,
  # unlike the toggle, and only where reading a thread marks it read: only /me
  # routes it. It answers what opening the thread would have changed, and the
  # cards, whose New chips go. The folder and search it posts are the list's,
  # from the tab row's fields as the toggles post them, so the row comes back
  # as that list draws it, never with the search the pane was opened with.
  def mark_read
    @folder = normalize_folder(params[:folder])
    @message.mark_thread_read!(message_owner.id) unless @message.thread_read?(message_owner.id)
    render turbo_stream: [*read_state_streams, *card_streams]
  end

  def toggle_archive
    archived = @message.toggle_archived!(message_owner.id)
    render_message_flags("Message #{archived ? "archived" : "moved to inbox"}.")
  end

  def new
    @message_form = MessageForm.new
  end

  def find_recipient
    render turbo_stream: turbo_stream.append("modal", partial: "common/messages/find_recipient",
                                             locals: { find_form: FindRecipientForm.new })
  end

  def search_callsigns
    find_form = FindRecipientForm.new(params.expect(find_recipient_form: [:query]))
    if find_form.valid?
      people = callsign_matches(find_form)
      find_form.errors.add(:query, NO_CALLSIGNS_MATCHED) unless people.any?
    else
      people = nil
    end
    render turbo_stream: turbo_stream.update("find-recipient", partial: "common/messages/find_recipient_form",
                                             locals: { people:, find_form: })
  end

  # The recipients chip field's suggestions, as autocomplete JSON: whom the
  # Find Recipient modal would list for q, each warned of if long away.
  def suggest_callsigns
    find_form = FindRecipientForm.new(query: params[:q].is_a?(String) ? params[:q].strip : "")
    people = find_form.valid? ? callsign_matches(find_form) : []
    items = people.map do |person|
      photo = rails_blob_path(person.avatar_photo, only_path: true) if person.avatar_photo
      lines = person.last_seen_at&.before?(2.years.ago) ? AWAY_TOO_LONG : []
      html = render_to_string(partial: "autocomplete/item", formats: [:html],
                              locals: { icon: :user, title: person.callsign, photo:, lines: })
      { id: "callsign-#{person.id}", label: person.callsign, value: person.callsign, html: }
    end
    render json: Autocomplete::ResponseBuilder.build(
      query: find_form.query, mode: "callsign",
      adapter_result: { items:, flat_item_ids: items.pluck(:id), empty_text: NO_CALLSIGNS_MATCHED }
    )
  end

  # The search field's suggestions (common/messages/_search_field), as
  # autocomplete JSON, from the owner's own conversations: the search for the
  # text first, then the people in them whose callsign starts with it, each
  # taken as a chip that narrows the search to the conversations they are in,
  # less those the field holds already (?with[]=), then the teams whose name
  # holds it, each a search for that name. Each row's meta.kind tells
  # message_search_controller which it is.
  def suggest
    query = params[:q].is_a?(String) ? params[:q].strip.first(100) : ""
    found = PersonMessage.search_suggestions_for_person(message_owner.id, query, without: search_people.compact)
    preload_avatars(found[:people].map(&:first))

    search = query.present? ? [search_suggestion("search", "search", query, title: "Search messages for “#{query}”")] : []
    people = found[:people].map do |person, count|
      photo = rails_blob_path(person.avatar_photo, only_path: true) if person.avatar_photo
      search_suggestion("person-#{person.id}", "person", person.callsign, icon: "user", photo:,
                                                                         lines: [helpers.pluralize(count, "conversation")])
    end
    teams = found[:teams].map { |team| search_suggestion("team-#{team.id}", "team", team.title, icon: "people-group") }
    groups = { "search" => ["", search], "people" => [SUGGESTED_PEOPLE, people], "teams" => ["Teams", teams] }
               .filter_map { |key, (title, rows)| { key:, title:, item_ids: rows.pluck(:id) } if rows.any? }
    render json: Autocomplete::ResponseBuilder.build(query:, mode: "messages",
                                                     adapter_result: { items: [*search, *people, *teams], groups: })
  end

  def select_callsign
    callsign = params[:callsign] || ""
    if callsign.blank?
      return respond_to do |format|
        format.html { redirect_to new_message_path(**direction_params) }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "find-recipient",
            partial: "common/messages/find_recipient_form",
            locals: { people: nil, find_form: FindRecipientForm.new }
          )
        end
      end
    end

    find_form = FindRecipientForm.new
    person, error = validate_person_for_messaging(callsign)
    if error
      find_form.errors.add(:query, error)
      return respond_to do |format|
        format.html { redirect_to new_message_path(**direction_params) }
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "find-recipient",
            partial: "common/messages/find_recipient_form",
            locals: { people: nil, find_form: }
          )
        end
      end
    end

    # The choice joins the chips, or is the relay's one party, replacing it.
    choice = turbo_stream.action(group_send_allowed? ? :append : :update, "message_form_callsigns_chips",
                                 partial: "shared/callsign_chip",
                                 locals: { name: "message_form[callsigns][]", callsign: person.callsign })
    respond_to do |format|
      format.html { redirect_to new_message_path(**direction_params) }
      format.turbo_stream do
        render turbo_stream: [
          turbo_empty_frame("modal"),
          choice,
          # The summary sits outside the frame just replaced, so an error about
          # the old recipient would outlive the choice; field errors stay inline.
          turbo_stream.remove("form-error-summary")
        ]
      end
    end
  end

  # One callsign saves a one-to-one message, as it always has. Several, a
  # Cadre or Delegation, or a message sent as one, save one shared group
  # thread (#send_group_message).
  def create
    @message_form = MessageForm.new params.expect(message_form: [:subject, :body, :team_id, :sender_team_id, { callsigns: [] }])
    people = message_recipients
    team = message_team
    sender_team = message_sender_team

    if @message_form.errors.any? || !@message_form.valid?
      render :new, status: :unprocessable_entity
      return
    end

    return send_group_message(people, team, sender_team) if team || sender_team || people.many?

    person = people.first
    sender, recipient = resolve_participants(person)
    letter = build_person_message(sender, recipient, @message_form.subject, @message_form.body)

    if letter.save
      notify_recipients([recipient], letter)
      redirect_to message_path(letter), notice: "Message sent."
    else
      @message_form.errors.add(:unknown, "An error occurred. Try again.")
      render :new, status: :unprocessable_entity
    end
  end

  def create_reply
    @reply_form = MessageReplyForm.new(params.expect(message_reply_form: %i[reply shown_through as_team_id]))

    # Refused before the recipient lookup: a message that takes no reply has no
    # sender_person_id to send one to.
    unless @message.accepts_replies?
      @reply_form.errors.add(:base, "This message cannot be replied to.")
      render_reply_form
      return
    end

    team = reply_team if @reply_form.valid?
    if @reply_form.errors.empty?
      message_thread, recipients = build_reply(team)

      saved = PersonMessage.transaction do
        next false unless message_thread.save

        # The author has read the thread up to the reply they wrote, in the
        # reply's commit, so its broadcasts show them read -- on their own page
        # alone (ruling D3): a reply HQ or a manager writes as them leaves
        # their unread alone, as opening the thread there does. Only through
        # what the page showed: a reply from someone else since stays New (D2).
        @message.mark_thread_read!(message_owner.id, through: @reply_form.shown_through) if mark_read_on_view?
        true
      end
      if saved
        notify_recipients(recipients, message_thread)
        @reply_form = new_reply_form(shown_through: @reply_form.shown_through)
        render_reply_form [
                            turbo_stream.append("messages-thread",
                                                partial: "common/messages/message_card",
                                                locals: { message: message_thread, owner: message_owner }),
                            ui_toast_stream("Reply sent", :success)
                          ]
        return
      end
      # e.g. the other party's status no longer allows messages
      @reply_form.errors.merge!(message_thread.errors)
    end
    render_reply_form
  end

  private

  # --- Namespace hooks: including controllers override these -----------------

  # Whose mailbox is being viewed and acted on.
  def message_owner
    raise NotImplementedError
  end

  # Route helper namespace, e.g. "me" builds me_messages_path.
  def messages_route_prefix
    raise NotImplementedError
  end

  # Leading route helper arguments, e.g. [@person] for person-nested routes.
  def messages_route_args
    []
  end

  # [sender, recipient] for a composed message; +lookup_person+ is the party
  # chosen via the callsign lookup. Default: owner writes to the looked-up person.
  def resolve_participants(lookup_person)
    [message_owner, lookup_person]
  end

  # Whether opening a thread marks it read for the owner. True for the owner
  # reading their own mailbox; the administration interface must not alter the
  # person's read state just by viewing.
  def mark_read_on_view?
    true
  end

  # Compose-flow query params that must survive the find-recipient round trips.
  def direction_params
    {}
  end

  # Whether compose may address several people or a team. The HQ window's
  # relay (a looked-up sender writing to the person) is always one-to-one.
  def group_send_allowed?
    true
  end

  # How the looked-up party is labeled on the compose form ("To:"/"From:").
  def lookup_label
    "To:"
  end

  # The looked-up party's role, used in the lookup modal title and select button.
  def lookup_role_label
    "Recipient"
  end

  # What a callsign that can't be looked up is told. Self-serve gives every
  # +reason+ the same words, so a crafted callsign can't tell an unknown one
  # from a person's status (the recipient search hides those people too).
  def recipient_refusal(_reason)
    "You can't message that callsign."
  end

  # --- Namespaced path helpers (exposed to the shared views) -----------------

  def messages_path(**opts) = send(:"#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def message_path(message, **opts) = send(:"#{messages_route_prefix}_message_path", *messages_route_args, message, **opts)
  def new_message_path(**opts) = send(:"new_#{messages_route_prefix}_message_path", *messages_route_args, **opts)
  def find_recipient_messages_path(**opts) = send(:"find_recipient_#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def search_callsigns_messages_path(**opts) = send(:"search_callsigns_#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def suggest_callsigns_messages_path(**opts) = send(:"suggest_callsigns_#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def suggest_messages_path(**opts) = send(:"suggest_#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def select_callsign_messages_path(**opts) = send(:"select_callsign_#{messages_route_prefix}_messages_path", *messages_route_args, **opts)
  def create_reply_message_path(message, **opts) = send(:"create_reply_#{messages_route_prefix}_message_path", *messages_route_args, message, **opts)
  def toggle_read_message_path(message, **opts) = send(:"toggle_read_#{messages_route_prefix}_message_path", *messages_route_args, message, **opts)
  def toggle_archive_message_path(message, **opts) = send(:"toggle_archive_#{messages_route_prefix}_message_path", *messages_route_args, message, **opts)
  # Only /me routes it; the panel asks mark_read_on_view? first.
  def mark_read_message_path(message, **opts) = send(:"mark_read_#{messages_route_prefix}_message_path", *messages_route_args, message, **opts)

  # --- Shared internals -------------------------------------------------------

  # The people a send would accept whose callsign starts with the query: the
  # five the Find Recipient modal lists and the chip field suggests.
  def callsign_matches(find_form)
    PersonSearch.search_callsigns_for_messaging(find_form.query, PersonSearch::TYPE_CONTACT).tap { |people| preload_avatars(people) }
  end

  # The photos a suggestion row draws, for every person in one go.
  def preload_avatars(people)
    ActiveRecord::Associations::Preloader.new(records: people,
                                              associations: { avatar_photo_attachment: { avatar_attachment: :blob } }).call
  end

  # One row of #suggest, drawn as every autocomplete row is: +value+ is what
  # taking it puts in the field, +kind+ what message_search_controller does then.
  def search_suggestion(id, kind, value, icon: "magnifying-glass", title: value, photo: nil, lines: [])
    html = render_to_string(partial: "autocomplete/item", formats: [:html], locals: { icon:, title:, photo:, lines: })
    { id:, label: value, value:, html:, meta: { kind: } }
  end

  # Rbs.message_notify, which may text or email, for each person a one-to-one
  # message went to (a group message's job notifies its members), from the
  # name the row was written under. It gets the text, not the editor's HTML:
  # the email would print the tags (MailTemplateRenderer escapes every value it
  # is handed).
  def notify_recipients(people, message)
    people.each do |person|
      Rbs.message_notify(person, message.sender_person_id, message.sender_name, message.subject, message.body_text)
    end
  end

  # A row's link loads the pane's frame (Turbo-Frame: messages-pane), the way
  # UnifiedFlaggingConcern#review_pane_request? reads its own. Only for HTML.
  def pane_request?
    request.format.html? && turbo_frame_request_id == "messages-pane"
  end

  # The thread page's lazy list loads its own frame (Turbo-Frame:
  # messages-conversation-list); only #index answers it.
  def list_request?
    request.format.html? && turbo_frame_request_id == "messages-conversation-list"
  end

  # What the mailbox is searched for (?q=), or nil for none: a folder's list,
  # or a search by chips alone (#searching? tells the two apart). Carried
  # like the folder -- by a hit's link, the pane's toggles and the thread page's
  # lazy list -- so the list column keeps showing the hits through each of them.
  def search_query
    return @search_query if defined?(@search_query)

    @search_query = (params[:q].strip.first(100).presence if params[:q].is_a?(String))
  end

  # The search's chips (?with[]=), each the callsign it shows and the person it
  # names: looked up as the compose form looks one up and shown as that
  # person's callsign, so however an address spells someone, they are one chip.
  # One naming nobody shows as typed, with no person, and the search finds
  # nothing (PersonMessage.search_for_person).
  def search_chips
    @search_chips ||= Array(params[:with].presence).grep(String).map { |callsign| callsign.strip.first(Person::CALLSIGN_MAX_LENGTH) }
                                                   .compact_blank.uniq(&:downcase).first(MAX_SEARCH_WITH)
                                                   .map { |callsign| Person.resolve_callsign(callsign).then { |person| [person&.callsign || callsign, person] } }
                                                   .uniq(&:first)
  end

  # The callsigns the search field holds as chips: the search keeps to the
  # conversations every one of them is in. Carried with the query.
  def search_with = search_chips.map(&:first)

  # Whom the chips name, nil for one naming nobody.
  def search_people = search_chips.map(&:last)

  # Whether the list shows a search's hits: some text, or a chip alone.
  def searching?
    search_query.present? || search_with.any?
  end

  # A search as a link carries it, to stay on its hits: a hit's thread, the
  # thread page's lazy list, Next Unread and the way back.
  def search_scope
    { q: search_query, with: search_with.presence }
  end

  # The folder tabs and the list, streamed back in place: a folder switch, and a
  # toggle in the pane that changes the list beside it.
  def folder_streams(messages, selected_id: nil)
    [
      folder_selector_stream,
      turbo_stream.update("messages-conversation-list", partial: "common/messages/conversation_list",
                          locals: { messages:, folder: @folder, selected_id: })
    ]
  end

  def folder_selector_stream
    turbo_stream.update("messages-folder-selector", partial: "common/messages/folder_selector",
                        locals: { folder: @folder })
  end

  # The viewer's navbar envelope. On Person and HQ the flags changed are someone
  # else's, so it re-renders unchanged there.
  def navbar_stream
    turbo_stream.replace("navbar-messages", partial: "application/navbar_messages",
                         locals: { count: PersonMessage.count_unread(current_user.id) })
  end

  # What opening an unread thread in the pane changed outside it: the envelope,
  # the Unread tab's count and the thread's row. They ride inside the frame's
  # answer, where Turbo runs a turbo-stream as it renders. The row is morphed, so
  # the link the reader activated keeps its node, its focus and its mark. The
  # count is replaced alone: the tab row would take the active tab from the
  # folder the pane was opened with, which a row a live reply replaced does not
  # carry (PersonMessage#announce_reply).
  def read_state_streams
    [
      navbar_stream,
      turbo_stream.replace("messages-unread-count", helpers.messages_unread_badge(helpers.unread_message_count)),
      turbo_stream.replace(helpers.dom_id(@message, :conversation), method: :morph,
                           partial: "common/messages/conversation_summary",
                           locals: { message: @message, owner: message_owner, namespace: messages_route_prefix,
                                     folder: @folder, selected_id: @message.id, **search_scope })
    ]
  end

  def normalize_folder(folder)
    if folder.blank? || !PersonMessage::VALID_FOLDERS.include?(folder)
      return PersonMessage::FOLDER_INBOX
    end

    folder
  end

  # The list column's rows: a search's hits in every folder, else the folder's.
  def retrieve_list_messages
    return PersonMessage.search_for_person(message_owner.id, search_query, with: search_people) if searching?

    PersonMessage.retrieve_for_person(message_owner.id, @folder)
  end

  def validate_person_for_messaging(callsign)
    person = Person.resolve_callsign(callsign)
    return [nil, recipient_refusal("Callsign not found")] if person.nil?
    return [nil, recipient_refusal("Person is deceased.")] if person.deceased?
    return [nil, recipient_refusal("Person may not be messaged.")] unless person.messaging_permitted?

    [person, nil]
  end

  # A one-to-one row, the top or a reply (a group row is PersonMessage's own:
  # .new_group_thread, .new_group_reply).
  def build_person_message(sender, recipient, subject, body, reply_to: nil)
    PersonMessage.new(
      message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
      person_id: recipient.id,
      creator_person_id: current_user.id,
      sender_person_id: sender.id,
      sender_type: PersonMessage::SENDER_TYPE_PERSON,
      subject: subject,
      body: body,
      reply_to:
    )
  end

  # The people the compose form names, each callsign through
  # validate_person_for_messaging: one refused stops the whole send, and with
  # several named the refusal says which. A found callsign is kept as the
  # person spells it.
  def message_recipients
    return [] if @message_form.callsigns.size > MessageForm::MAX_CALLSIGNS # valid? says so, before any lookup

    callsigns = @message_form.recipient_callsigns
    resolved = callsigns.map { |callsign| [callsign, *validate_person_for_messaging(callsign)] }
    resolved.each do |callsign, _person, error|
      @message_form.errors.add(:callsigns, callsigns.many? ? "#{callsign}: #{error}" : error) if error
    end
    @message_form.callsigns = resolved.map { |callsign, person, _error| person&.callsign || callsign }.compact
    resolved.filter_map { |_callsign, person, _error| person }.uniq(&:id)
  end

  # The team a form names by id (+attribute+), as the block finds it among the
  # teams the form offered, or nil with +refusal+ on the form when it names one
  # outside them.
  def team_choice(form, attribute, refusal)
    team_id = form.public_send(attribute)
    return if team_id.blank?

    team = yield team_id
    form.errors.add(attribute, refusal) unless team
    team
  end

  # The Cadre or Delegation the compose form names; a missing, inactive or
  # plain team is refused (Team.messageable).
  def message_team
    team_choice(@message_form, :team_id, "Choose an active Cadre or Delegation.") { |id| Team.messageable.find_by(id:) }
  end

  # The Cadre or Delegation the compose form sends as (MessageForm#sender_team_id),
  # or nil for the owner's own name: an active one the owner is on now
  # (Team.cadres_and_delegations_of). The refusal names both conditions, since
  # a team deactivated after the form was drawn fails the same lookup. The relay
  # has one sender, so it refuses one however it was sent.
  def message_sender_team
    return if @message_form.sender_team_id.blank?

    unless group_send_allowed?
      @message_form.errors.add(:sender_team_id, RELAY_ONE_SENDER)
      return
    end

    team_choice(@message_form, :sender_team_id, "Choose an active Cadre or Delegation you're a member of.") do |id|
      Team.cadres_and_delegations_of(message_owner.id).find_by(id:)
    end
  end

  # One shared thread (ruling D2 of the messaging rework) for everyone named,
  # the sender a member too, written as +sender_team+ when one was chosen: the
  # top and the named members in one save, and the members of the team written
  # to and of the one written as join it as it is saved, marked
  # (PersonMessage#sync_team_members!). Refused when nobody besides the sender
  # would be in it. The members are notified by its job
  # (GroupMessageAnnounceJob), not here.
  def send_group_message(people, team, sender_team)
    unless group_send_allowed?
      @message_form.errors.add(:callsigns, RELAY_ONE_SENDER)
      return render :new, status: :unprocessable_entity
    end

    sender = message_owner
    recipients = people.reject { |person| person.id == sender.id }
    # As PersonMessage#teams orders them: the team written as first, once.
    teams = [sender_team, team].compact.uniq
    if recipients.empty? && teams.none? { |each| each.messageable_members.where.not(id: sender.id).exists? }
      # Beside the select it is about: the Cadre to send to when one was chosen.
      @message_form.errors.add(team ? :team_id : :sender_team_id,
                               "Nobody in the #{teams.map(&:title).join(" or ")} can be messaged.")
      return render :new, status: :unprocessable_entity
    end

    letter = PersonMessage.new_group_thread(sender, recipients, as_team: sender_team,
                                                                creator_person_id: current_user.id,
                                                                recipient_team: team,
                                                                message_type: PersonMessage::MESSAGE_TYPE_CONTACT,
                                                                subject: @message_form.subject, body: @message_form.body)

    unless letter.save
      # The model's own sentences (errors.format is %{message}), as a reply's
      # refusal shows them; the generic one only when it gave none.
      @message_form.errors.merge!(letter.errors)
      @message_form.errors.add(:unknown, "An error occurred. Try again.") if letter.errors.empty?
      return render :new, status: :unprocessable_entity
    end

    redirect_to message_path(letter), notice: "Message sent."
  end

  # A reply form as it is first drawn: written as the first team the owner may
  # reply as, when there is one (the owner's ruling of 2026-10-19, replacing
  # R1's own name). A refused reply keeps the choice it was sent with.
  def new_reply_form(**attributes)
    MessageReplyForm.new(as_team_id: @message.reply_teams_for(message_owner.id).first&.id, **attributes)
  end

  # The team the reply is written as (MessageReplyForm#as_team_id), or nil for
  # the owner's own name: one of the thread's teams the owner is on now
  # (PersonMessage#reply_teams_for).
  def reply_team
    team_choice(@reply_form, :as_team_id,
                "Only a current member of an active Cadre or Delegation in this conversation can reply as it.") do |id|
      @message.reply_teams_for(message_owner.id).find { |team| team.id == id }
    end
  end

  # A reply and whom the request notifies: on a group thread nobody, since its
  # job notifies every other member (GroupMessageAnnounceJob), its row the
  # author's, written as +team+ when one was chosen; else the other party.
  def build_reply(team)
    if @message.group?
      reply = PersonMessage.new_group_reply(@message, message_owner, body: @reply_form.reply, as_team: team,
                                                                    creator_person_id: current_user.id,
                                                                    message_type: PersonMessage::MESSAGE_TYPE_CONTACT)
      return [reply, []]
    end

    is_sender = @message.sender?(message_owner.id)
    person = Person.find(is_sender ? @message.person_id : @message.sender_person_id)
    [build_person_message(message_owner, person, @message.subject, @reply_form.reply, reply_to: @message), [person]]
  end

  def set_message
    # One hash, so one Preloader, whose batch loads the top's teams and the
    # replies' in one Team query: each argument of its own (includes flattens
    # an array) would take three.
    @message = PersonMessage.includes(sender_team: {}, recipient_team: {}, members: :person,
                                      replies: %i[sender_person sender_team])
                            .find_by(id: params[:message_id] || params[:id])
    return refuse_message("Message not found") unless @message
    return refuse_message("Invalid message id") unless @message.participant?(message_owner.id)

    return refuse_message("Message not thread top") if @message.reply_to_id

    true
  end

  # A pane request is answered in the pane, at 200: a redirect would be
  # followed inside the frame, its notice thrown away with the layout, and the
  # address moved to the mailbox. (A 4xx would make Turbo render the bare
  # partial as an error page.)
  def refuse_message(notice)
    if pane_request?
      render partial: "common/messages/pane",
             locals: { message: nil, folder: normalize_folder(params[:folder]), notice: }
    else
      redirect_to messages_path, error: notice
    end
    false
  end

  # The cards this request loaded, each morphed: only what changed is touched
  # (the New chip, the tint, data-unread), so the log region announces nothing
  # new and the reply form is left alone. Card by card, never the whole thread:
  # a reply that landed live after this request loaded the thread is not in it,
  # and a morph of #messages-thread would remove that card (review finding V10).
  # A body and the ring of the card a search landed on are the page's own:
  # _thread drew them with the search the pane was opened with, which this
  # request does not carry, and review_pane_controller keeps them through the
  # morph, so the marks never follow another search and a live card never
  # gains any.
  def card_streams
    @message.thread_rows.map do |card|
      turbo_stream.replace(helpers.dom_id(card, :card), method: :morph, partial: "common/messages/message_card",
                                                        locals: { message: card, owner: message_owner })
    end
  end

  def render_reply_form(streams = [])
    form = turbo_stream.update(
      "messages-reply-form",
      partial: "common/messages/reply_form",
      locals: { message: @message, reply_form: @reply_form, autofocus: true }
    )
    streams << form
    respond_to do |format|
      format.html { redirect_to message_path(@message) }
      format.turbo_stream { render turbo_stream: streams }
    end
  end

  # A toggle in the pane changes the list beside it -- the row's chip, its
  # place in the folder, the Unread count -- so the folder the header's forms
  # carry is streamed back with the header, as a folder switch would. `thread`
  # morphs the cards too (#card_streams), whose New chips follow the read state.
  def render_message_flags(toast, thread: false)
    @folder = normalize_folder(params[:folder])
    streams = [
      turbo_stream.update("messages-panel-header", partial: "common/messages/messages_panel_header",
                          locals: { message: @message, folder: @folder }),
      navbar_stream,
      *folder_streams(retrieve_list_messages, selected_id: @message.id),
      ui_toast_stream(toast, :success)
    ]
    streams.concat(card_streams) if thread

    respond_to do |format|
      format.turbo_stream { render turbo_stream: streams }
    end
  end
end
