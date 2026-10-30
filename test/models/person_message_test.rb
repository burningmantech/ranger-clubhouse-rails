# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# PersonMessage.search_for_person reads the person_message fixtures: InnoDB's
# full-text index sees committed rows only, so nothing a transactional test
# creates can be found by MATCH ... AGAINST.
class PersonMessageTest < ActiveSupport::TestCase
  include GroupMessageTestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @owner = person(:inactive_ranger)
    @swap = person_message(:search_dirt_swap)
    @radio = person_message(:search_radio_archived)
    @khaki = person_message(:search_khaki_notes)
  end

  # --- Team threads (.scratch/team-messaging/PRD.md) --------------------------

  test "a thread sent to a team marks the team's members, and a reply brings in who joined since and keeps who left" do
    cadre = teams(:green_dot_cadre)
    author = person(:active_ranger)
    leaver = person(:ranger_with_custom_gender)
    newcomer = person(:echelon_ranger)
    [author, leaver].each { |member| join_team(member, cadre) }

    top = create_team_thread(author, cadre)
    assert_equal({ author.id => cadre.id, leaver.id => cadre.id }, team_marks(top))
    assert_equal ["Green Dot Cadre"], top.group_party_names(author.id), "the marked members collapse into the team"

    join_team(newcomer, cadre)
    PersonTeam.find_by!(person: leaver, team: cadre).destroy!
    assert_difference -> { PersonMessageMember.count }, 1 do
      create_group_reply(top, author)
    end

    marks = top.reload.members.index_by(&:person_id)
    assert_equal cadre.id, marks.fetch(newcomer.id).team_id
    assert_nil marks.fetch(newcomer.id).last_read_message_id
    assert_includes PersonMessage.unread_for_person(newcomer.id), top
    assert_equal cadre.id, marks.fetch(leaver.id).team_id, "a leaver keeps their row and its mark"
    assert top.participant?(leaver.id)

    assert_no_difference -> { PersonMessageMember.count } do
      create_group_reply(top, author, body: "Nothing changed.")
    end
  end

  test "a thread sent as one team to another names the sending team first, and marks someone on both with it" do
    author = person(:active_ranger) # on the Council Cadre by fixture
    join_team(author, teams(:green_dot_cadre))

    top = create_team_thread(author, teams(:council_cadre), as_team: teams(:green_dot_cadre))

    assert_equal ["Green Dot Cadre", "Council Cadre"], top.teams.map(&:title)
    assert_equal teams(:green_dot_cadre).id, top.member(author.id).team_id
  end

  # Review finding: search never matched the team name a team thread lists under.
  test "search finds a team thread by its team's name" do
    author = person(:active_ranger)
    heron = person(:ranger_with_custom_gender)
    join_team(author, teams(:green_dot_cadre))
    heron.update!(last_seen_at: 1.day.ago)
    top = create_group_thread(author, heron, as_team: teams(:green_dot_cadre), subject: "Radios")

    assert_includes PersonMessage.search_for_person(heron.id, "Green Dot"), top
    assert_includes PersonMessage.search_for_person(heron.id, "dot cad"), top
    assert_not_includes PersonMessage.search_for_person(heron.id, "Council"), top
  end

  test "a deactivated team stops growing its threads, and a deleted one is named by its id" do
    cadre = teams(:green_dot_cadre)
    author = person(:active_ranger)
    join_team(author, cadre)
    top = create_team_thread(author, cadre)
    cadre.update!(active: false)
    join_team(person(:echelon_ranger), cadre)

    assert_no_difference -> { PersonMessageMember.count } do
      create_group_reply(top, author)
    end

    reply = create_group_reply(top, author, as_team: cadre.tap { |team| team.update!(active: true) })
    TeamManagement.destroy(cadre)
    reply = PersonMessage.find(reply.id)
    assert_equal "Deleted Team ##{cadre.id}", reply.sender_name
    assert_equal ["Deleted Team ##{cadre.id}"], PersonMessage.find(top.id).group_party_names(author.id)
  end

  test "a team thread takes replies where a Clubhouse 2 team message never did, and a row as the team keeps its author" do
    cadre = teams(:green_dot_cadre)
    author = person(:active_ranger)
    join_team(author, cadre)
    top = create_team_thread(author, cadre)
    assert top.accepts_replies?
    assert_equal [cadre.id], top.team_ids

    legacy = PersonMessage.new(sender_type: PersonMessage::SENDER_TYPE_TEAM, sender_team: cadre, group: false)
    assert_not legacy.accepts_replies?
    assert_empty legacy.team_ids

    as_team = PersonMessage.new(person: author, sender_type: PersonMessage::SENDER_TYPE_TEAM, sender_team: cadre,
                                group: true, reply_to: top, subject: top.subject, body: "Noted.",
                                message_type: PersonMessage::MESSAGE_TYPE_CONTACT)
    assert_not as_team.valid?
    assert_includes as_team.errors[:sender_person_id], "The sender is missing."
    as_team.sender_person = author
    assert as_team.valid?, as_team.errors.full_messages.join(", ")
  end

  # #thread_read? and #unread? agree with unread_for_person, expiry included.
  test "an expired message is read by everyone, as unread_for_person counts it" do
    recipient = person(:active_ranger)
    broadcast = PersonMessage.create!(person: recipient, creator_person: recipient, message_from: "Ranger HQ",
                                      sender_type: PersonMessage::SENDER_TYPE_RBS, subject: "Hold at your post",
                                      body: "Dust storm.", expires_at: Current.time + 1.hour)
    assert_not broadcast.thread_read?(recipient.id)
    assert broadcast.unread?(recipient.id)
    assert_includes PersonMessage.unread_for_person(recipient.id), broadcast

    broadcast.update_column(:expires_at, Current.time - 1.minute)
    assert broadcast.thread_read?(recipient.id)
    assert_not broadcast.unread?(recipient.id)
    assert_not_includes PersonMessage.unread_for_person(recipient.id), broadcast
  end

  test "search needs every word, each as the start of a word, and looks in every folder" do
    # The radio thread is archived; the swap thread moved last (its reply).
    assert_equal [@swap, @radio], search("dirt shi")
    assert_equal [@swap], search("dirt saturday")
  end

  test "search matches a subject, and a reply's hit lists its thread" do
    assert_equal [@khaki], search("khaki")
    assert_equal [@swap], search("thermos")
  end

  test "search keeps an underscore in a word, as InnoDB indexes it" do
    assert_equal [@khaki], search("gate_log")
    assert_equal [@khaki], search("gate_log_book")
    assert_equal [@khaki], search("gate")
    # A part after an underscore is inside the word, as "shift" is in "midshift".
    assert_empty search("book")
    assert_equal "gate_log_book", PersonMessage.search_pattern("gate_log").match("filed under gate_log_book.")[0]
    assert_nil PersonMessage.search_pattern("book stack").match("filed under gate_log_book.")
  end

  test "search matches the start of the other party's callsign" do
    assert_equal [@swap], search("alphan")
    # Compared as the compose form's lookup compares them: no case, accents or punctuation.
    assert_equal [@swap], search("Alpha-New")
    assert_equal [@radio, @khaki], search("RANGER")
  end

  test "a query of short words alone matches it anywhere in the subject or body" do
    assert_equal [@swap], search("18")
    assert_equal [@swap], search("18:00")
  end

  test "stopwords and short words are left out of the full-text match" do
    # Required, either would match nothing: InnoDB indexes neither.
    assert_equal [@radio], search("the dirt radio at")
  end

  test "the query's own boolean operators are only text" do
    assert_equal [@radio], search('+dirt -shift "radio*')
    assert_empty search("*")
  end

  test "search reads a message's text, so a tag or attribute word of the editor's finds nothing" do
    # A fixture is written past body=, so each spells out the text it would write.
    PersonMessage.find_each { |row| assert_equal PersonMessage.plain_text(row.body), row.body_text, "fixture #{row.id}" }

    assert_equal [@radio], search("spare batteries")
    %w[strong href https example].each { |word| assert_empty search(word), word }
    # The short-word fallback reads the text too.
    assert_empty search("<p")
  end

  # The release serving while 20261018000005 migrates knows no body_text, and
  # its INSERTs leave the column out (review finding 4).
  test "a message saved by a release that knows no body_text is accepted, its text empty" do
    recipient = person(:active_ranger)
    id = PersonMessage.connection.insert(<<~SQL.squish)
      INSERT INTO person_message (person_id, creator_person_id, subject, body, message_from, sender_type)
      VALUES (#{recipient.id}, #{recipient.id}, 'Radios', 'Who has them?', 'Outpost 3', 'other')
    SQL

    assert_equal "", PersonMessage.find(id).body_text
  end

  test "a body is the editor's HTML only when it opens with one of the editor's blocks" do
    ["<p>Hi</p>", " <ul><li>One</li></ul>", "<h2>Plan</h2>", "<P class=\"x\">Hi</P>"].each do |body|
      assert PersonMessage.rich_text?(body), body
    end
    ["I <3 Outpost", "a < b", "<eom>", "<name@example.org> wrote:", "<pre", "<prep>", "plain", nil].each do |body|
      assert_not PersonMessage.rich_text?(body), body.inspect
    end
  end

  test "the text of the editor's HTML has a line per block, no tags, and its entities decoded" do
    html = "<p>Bring the <strong>spare</strong> batteries.<br>Today.</p><ul><li>One</li><li>Two</li></ul><p>A &amp; B</p>" \
           "<p><br></p><figure><table><tr><td>Cell</td><th>Head</th></tr></table></figure><hr><div>Old</div>" \
           "<script>alert(1)</script>"
    assert_equal "Bring the spare batteries.\nToday.\nOne\nTwo\nA & B\nCell\nHead\nOld", PersonMessage.plain_text(html)
    # Plain text is kept as it is, entities and less-than signs included.
    assert_equal "I <3 Outpost &amp; a < b", PersonMessage.plain_text("I <3 Outpost &amp; a < b")

    message = PersonMessage.new(body: "<p>Hi <em>there</em></p>")
    assert_equal "Hi there", message.body_text
    assert message.rich_text?
  end

  test "the length limit counts the text, not the markup" do
    message = PersonMessage.new(body: "<p><strong>#{"x" * PersonMessage::MAX_TEXT}</strong></p>")
    message.valid?
    assert_empty message.errors[:body]

    message.body = "<p>#{"x" * (PersonMessage::MAX_TEXT + 1)}</p>"
    message.valid?
    assert_equal ["Your message is 4,001 characters long. Shorten it to 4,000 or fewer."], message.errors[:body]

    # Markup past what the editor writes for that much text is refused before it is read.
    message.body = "<p>#{"<strong></strong>" * 4000}Hi</p>"
    message.valid?
    assert_equal ["Your message has too much formatting to send. Remove some, or shorten it."], message.errors[:body]

    # So is markup nested past what Nokogiri parses (400 levels), small as it is.
    message.body = "<p>#{"<b>" * 450}Hi</p>"
    message.valid?
    assert_equal ["Your message has too much formatting to send. Remove some, or shorten it."], message.errors[:body]

    # An editor holding nothing but an empty line holds no message.
    message.body = "<p><br></p>"
    message.valid?
    assert_equal ["Write your message before sending it."], message.errors[:body]
  end

  test "search finds only the person's own messages" do
    assert_empty search("roster")
    assert_equal [person_message(:search_not_the_owners)],
                 PersonMessage.search_for_person(person(:plate_collision_ranger).id, "roster")
  end

  test "search finds a group thread through the member's row, whoever wrote the match" do
    crew = person_message(:search_group_crew)

    assert_equal [crew], search("sandstorm")
    # EchelonTest's reply: a row whose person_id and sender are both someone else.
    assert_equal [crew], search("lanterns")
    assert_empty PersonMessage.search_for_person(person(:alpha_ranger).id, "lanterns")
  end

  test "search matches the start of another member's callsign, never the searcher's own" do
    crew = person_message(:search_group_crew)
    starter = person(:retired_ranger)

    assert_equal [crew], search("echelon")
    assert_equal [crew], PersonMessage.search_for_person(starter.id, "inactive")
    assert_empty PersonMessage.search_for_person(starter.id, "retired")
  end

  # --- The search field's chips and suggestions (.scratch/messages-search/PRD.md, slices 4 and 5)

  test "a chip keeps the search to its person's conversations, and alone lists them all" do
    ranger1 = person(:plate_collision_ranger)

    assert_equal [@radio, @khaki], search("", with: [ranger1])
    assert_equal [@radio], search("dirt", with: [ranger1])
    # RANGER1's thread with AlphaNewbie holds both words, but it is not the owner's.
    assert_empty search("roster", with: [ranger1])
    assert_empty search("khaki", with: [person(:alpha_ranger)])
  end

  test "chips need every person in the conversation, and one naming nobody finds nothing" do
    crew = person_message(:search_group_crew)
    retired = person(:retired_ranger)

    assert_equal [crew], search("", with: [retired, person(:echelon_ranger)])
    assert_empty search("", with: [retired, person(:plate_collision_ranger)])
    assert_empty search("", with: [nil])
    assert_empty search("dirt", with: [person(:plate_collision_ranger), nil])
  end

  # Review finding: text starting a chip's own callsign matched every thread the chip kept.
  test "with a chip, a callsign in the text matches the others in its threads, never the chip's own person" do
    retired = person(:retired_ranger)

    assert_empty search("ran", with: [person(:plate_collision_ranger)])
    assert_empty search("retired", with: [retired])
    # EchelonTest is in the crew's thread beside the chip.
    assert_equal [person_message(:search_group_crew)], search("echelon", with: [retired])
  end

  test "the field suggests the other people in the owner's conversations, with how many each shares" do
    assert_equal [[person(:plate_collision_ranger), 2]], suggest("ran")[:people]
    # The thread AlphaNewbie shares with RANGER1 is not the owner's, so it is not counted.
    assert_equal [[person(:alpha_ranger), 1]], suggest("Alpha-N")[:people]
    assert_empty suggest("inactive")[:people], "never the owner"
    assert_equal({ people: [], teams: [] }, suggest(" "))
    # Nor one the field holds as a chip already.
    assert_empty PersonMessage.search_suggestions_for_person(@owner.id, "ran", without: [person(:plate_collision_ranger)])[:people]
  end

  test "the field suggests the people shared most first, as many as asked for" do
    retired = person(:retired_ranger)
    2.times { letter(retired, to: @owner) }

    assert_equal [[retired, 3], [person(:plate_collision_ranger), 2]], suggest("r")[:people]
    assert_equal [[retired, 3]], PersonMessage.search_suggestions_for_person(@owner.id, "r", limit: 1)[:people]
  end

  # Review finding: the field suggested, and a chip or a callsign found, the
  # members a team brought into a thread, whom its row names as the team.
  test "the members a team brings into a thread are the team there: never suggested, chipped or matched by callsign" do
    cadre = teams(:green_dot_cadre)
    author = person(:active_ranger)
    echelon = person(:echelon_ranger)
    [author, echelon].each { |member| join_team(member, cadre) }
    top = create_group_thread(author, @owner, as_team: cadre, subject: "Radios")
    assert_equal({ author.id => cadre.id, echelon.id => cadre.id, @owner.id => nil }, team_marks(top))

    assert_equal [[echelon, 1]], suggest("echelon")[:people], "the crew's thread alone"
    assert_empty suggest("TestRanger")[:people]
    assert_not_includes search("", with: [echelon]), top
    assert_not_includes search("TestRanger"), top
    assert_includes search("Green Dot"), top
  end

  test "the field suggests the teams of the owner's team conversations whose name holds the text" do
    cadre = teams(:green_dot_cadre)
    author = person(:active_ranger)
    [@owner, author].each { |member| join_team(member, cadre) }
    create_team_thread(author, cadre)

    assert_equal [cadre], suggest("dot cad")[:teams]
    assert_empty PersonMessage.search_suggestions_for_person(person(:alpha_ranger).id, "dot cad")[:teams]
  end

  # --- Group threads: each member's own read and archive state ------------------

  test "a group thread is unread for each member until they read it, and again when someone else replies" do
    author, heron, quill = group_people
    top = create_group_thread(author, heron, quill)

    assert_not_includes PersonMessage.unread_for_person(author.id), top
    assert_includes PersonMessage.unread_for_person(heron.id), top
    assert_not top.thread_read?(heron.id)

    top.mark_thread_read!(heron.id)
    assert top.reload.thread_read?(heron.id)
    assert_not_includes PersonMessage.unread_for_person(heron.id), top
    assert_includes PersonMessage.unread_for_person(quill.id), top

    reply = create_group_reply(top, quill, created_at: 1.minute.from_now)
    top.reload
    [author, heron].each do |member|
      assert_includes PersonMessage.unread_for_person(member.id), top
      assert_not top.thread_read?(member.id)
      assert reply.unread?(member.id)
    end
    # The author's own top never reads New to them.
    assert top.read?(author.id)
  end

  test "Mark Unread on a group thread flags the newest row someone else wrote, and only that" do
    author, heron = group_people
    top = create_group_thread(author, heron)
    first = create_group_reply(top, author, created_at: 1.minute.from_now)
    own = create_group_reply(top, heron, created_at: 2.minutes.from_now)
    top.reload.mark_thread_read!(heron.id)

    assert_equal false, top.reload.toggle_thread_read!(heron.id)

    top.reload
    assert_includes PersonMessage.unread_for_person(heron.id), top
    assert first.unread?(heron.id)
    assert_not top.unread?(heron.id)
    assert_not own.unread?(heron.id)
    assert_equal true, top.toggle_thread_read!(heron.id)
    assert_not_includes PersonMessage.unread_for_person(heron.id), top
  end

  # The member model, slice 2: a one-to-one thread reads its member rows, as a
  # group thread does.
  test "Mark Unread on a one-to-one thread marks the other party's newest row New, not the top" do
    author, other = group_people
    top = letter(other, to: author)
    own = letter(author, to: other, reply_to: top)
    newest = letter(other, to: author, reply_to: top)

    top.reload.mark_thread_read!(author.id)
    assert_equal false, top.reload.toggle_thread_read!(author.id)

    top.reload
    assert_includes PersonMessage.unread_for_person(author.id), top
    assert_not top.unread?(author.id)
    assert_not own.unread?(author.id)
    assert newest.reload.unread?(author.id)
  end

  test "search lists only the threads the person may open" do
    author, other, third = group_people
    top = letter(author, to: other)
    # A reply by someone outside the thread, as Clubhouse 2 left a few: theirs,
    # but not a thread they may open, so not one search lists.
    stray = PersonMessage.create!(person: other, sender_person: third, creator_person: third, reply_to: top,
                                  subject: "Radios", body: "Q7 is mine", sender_type: PersonMessage::SENDER_TYPE_PERSON)

    assert_not top.participant?(third.id)
    # Two characters: the LIKE fallback, which sees this test's uncommitted rows.
    assert_empty PersonMessage.search_for_person(third.id, "Q7")
    assert_equal [top], PersonMessage.search_for_person(other.id, "Q7")
    assert stray.persisted?
  end

  test "an archived note to self is in Archived alone" do
    author, = group_people
    note = letter(author, to: author)

    assert_equal true, note.toggle_archived!(author.id)
    assert_includes folder(author, PersonMessage::FOLDER_ARCHIVED), note
    assert_not_includes folder(author, PersonMessage::FOLDER_INBOX), note
  end

  test "Mark Unread on a group thread nobody else has written in yet makes it never read" do
    author, heron = group_people
    top = create_group_thread(author, heron)

    assert_equal false, top.toggle_thread_read!(author.id)
    assert_nil top.member(author.id).last_read_message_id
    assert_includes PersonMessage.unread_for_person(author.id), top
  end

  test "a group thread is in each member's Inbox or Archived by their own row, and in its author's Sent" do
    author, heron, quill = group_people
    top = create_group_thread(author, heron, quill)
    top.member(heron.id).update!(archived: true)

    [author, quill].each { |member| assert_includes folder(member, PersonMessage::FOLDER_INBOX), top }
    assert_not_includes folder(heron, PersonMessage::FOLDER_INBOX), top
    assert_includes folder(heron, PersonMessage::FOLDER_ARCHIVED), top
    assert top.archived?(heron.id)
    assert_not top.archived?(quill.id)

    assert_includes folder(author, PersonMessage::FOLDER_SENT), top
    assert_not_includes folder(heron, PersonMessage::FOLDER_SENT), top
    # A reply of theirs does not put the thread in Sent: it lists the threads they started.
    create_group_reply(top, quill)
    assert_not_includes folder(quill, PersonMessage::FOLDER_SENT), top
    assert_empty PersonMessage.retrieve_for_person(person(:alpha_ranger).id, PersonMessage::FOLDER_INBOX) & [top]
  end

  test "a group thread's list loads each member row with the folder" do
    author, heron, quill = group_people
    create_group_reply(create_group_thread(author, heron, quill), quill)
    create_group_thread(author, heron)
    threads = folder(heron, PersonMessage::FOLDER_INBOX)

    assert_no_queries do
      threads.each do |thread|
        thread.thread_read?(heron.id)
        thread.archived?(heron.id)
        thread.group_party_names(heron.id) if thread.group?
      end
    end
  end

  test "a group row names each other member, the viewer left out" do
    author, heron, quill = group_people
    top = create_group_thread(author, heron, quill)

    assert_equal [heron, quill].map(&:callsign).sort_by(&:downcase), top.group_party_names(author.id)
    assert_equal [author, quill].map(&:callsign).sort_by(&:downcase), top.group_party_names(heron.id)
  end

  test "the Unread folder's ids come in the folder's own order, the thread that moved last first" do
    owner, other = group_people
    letter = lambda do |created_at, reply_to: nil|
      PersonMessage.create!(person: owner, sender_person: other, creator_person: other, reply_to:, created_at:,
                            subject: "Radios", body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    end
    oldest = letter.call(3.hours.ago)
    letter.call(2.hours.ago)
    letter.call(1.hour.ago)
    letter.call(1.minute.ago, reply_to: oldest) # the oldest thread moved last

    folder = PersonMessage.retrieve_for_person(owner.id, PersonMessage::FOLDER_UNREAD).map(&:id)
    assert_equal oldest.id, folder.first
    assert_equal folder, PersonMessage.unread_thread_ids(owner.id)
  end

  # created_at holds whole seconds, so a tie is ordered by id, which runs in
  # date order (all 26,045 rows on dev, 2026-10-19).
  test "rows of the same second keep the order they were written in" do
    owner, other = group_people
    second = 1.hour.ago.change(usec: 0)
    letter = lambda do |reply_to: nil|
      PersonMessage.create!(person: owner, sender_person: other, creator_person: other, reply_to:, created_at: second,
                            subject: "Radios", body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    end
    first = letter.call
    last = letter.call
    replies = Array.new(3) { letter.call(reply_to: first) } # the first thread moved last

    assert_equal replies, first.reload.replies.to_a
    assert_equal [first.id, last.id], PersonMessage.retrieve_for_person(owner.id, PersonMessage::FOLDER_UNREAD).map(&:id)
    assert_equal [first.id, last.id], PersonMessage.unread_thread_ids(owner.id)
  end

  # Live replies (slice 5): the card goes to [participant, thread top], the
  # stream the pane subscribes to for that mailbox, rendered as they see it.
  test "a reply lands in the thread of both parties, New only for the one it is to" do
    author, other = group_people
    top = PersonMessage.create!(person: other, sender_person: author, creator_person: author, subject: "Radios",
                                body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    reply = PersonMessage.create!(person: author, sender_person: other, creator_person: other, reply_to: top,
                                  subject: "Radios", body: "<p>I do.</p>", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    # Without a block: everything each stream was sent.
    to_author = capture_turbo_stream_broadcasts([author, top])
    to_other = capture_turbo_stream_broadcasts([other, top])

    [to_author, to_other].each do |streams|
      assert_equal [%w[append messages-thread]], streams.map { |stream| [stream["action"], stream["target"]] }
      assert_equal "card_person_message_#{reply.id}", streams.first.at_css("template article")["id"]
    end
    # The reply is to the top's author, who has not read it; the replier has.
    assert to_author.first.at_css("article[data-unread] .badge")
    assert_nil to_other.first.at_css("article[data-unread]")
  end

  test "a new thread is open nowhere, so nothing is appended to one" do
    author, other = group_people
    top = nil
    streams = capture_turbo_stream_broadcasts(other) do
      top = PersonMessage.create!(person: other, sender_person: author, creator_person: author, subject: "Radios",
                                  body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    end
    assert_equal %w[replace append], streams.pluck("action"), "the envelope and the screen reader line only"
    assert_no_turbo_stream_broadcasts [other, top]
    assert_no_turbo_stream_broadcasts [author, top]
    # Nor is it listed anywhere yet, so no list hears of it.
    PersonMessage::MAILBOX_NAMESPACES.each { |namespace| assert_no_turbo_stream_broadcasts [other, :messages, namespace] }
  end

  # A reply moves its thread's row and the Unread count in each party's mailbox
  # lists, one stream per namespace, whose path the row's link is.
  test "a reply replaces its thread's row and the Unread count in every mailbox list of both parties" do
    author, other = group_people
    top = PersonMessage.create!(person: other, sender_person: author, creator_person: author, subject: "Radios",
                                body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    top.mark_thread_read!(other.id)
    PersonMessage.create!(person: author, sender_person: other, creator_person: other, reply_to: top,
                          subject: "Radios", body: "I do.", sender_type: PersonMessage::SENDER_TYPE_PERSON)
    routes = Rails.application.routes.url_helpers

    { author => true, other => false }.each do |owner, unread|
      paths = [routes.me_message_path(top), routes.person_message_path(owner, top), routes.hq_message_path(owner, top)]
      PersonMessage::MAILBOX_NAMESPACES.zip(paths).each do |namespace, path|
        # Without a block: everything the stream was sent.
        streams = capture_turbo_stream_broadcasts([owner, :messages, namespace])
        assert_equal [["replace", "conversation_person_message_#{top.id}"], %w[replace messages-unread-count]],
                     streams.map { |stream| [stream["action"], stream["target"]] }, "#{owner.callsign} #{namespace}"
        link = streams.first.at_css("template a.review-line")
        assert_equal path, link["href"], "no folder or search: the broadcast knows neither"
        assert_equal unread, link.classes.include?("messages-conversation-unread"), owner.callsign
        chip = link.at_css(".badge")&.text&.strip
        unread ? assert_equal("New Reply", chip) : assert_nil(chip)
        assert_equal PersonMessage.count_unread(owner.id).to_s, streams.last.at_css("template #messages-unread-count").text
      end
    end
  end

  test "a group reply lands in the thread of every member, its author included" do
    author, heron, quill = group_people
    top = create_group_thread(author, heron, quill)
    # The job, not yet run, holds only the texts and emails: the cards are sent as the reply is saved.
    create_group_reply(top, heron)

    [author, heron, quill].each do |member|
      streams = capture_turbo_stream_broadcasts([member, top])
      assert_equal [%w[append messages-thread]], streams.map { |stream| [stream["action"], stream["target"]] }, member.callsign
      # Heron wrote it; the others have not read it.
      assert_equal member != heron, streams.first.at_css("article[data-unread]").present?, member.callsign
    end
  end

  test "a group message tells every member but its author that it arrived" do
    author, heron, quill = group_people
    to_heron = to_quill = nil

    # Captured: assert_turbo_stream_broadcasts counts what earlier tests sent too.
    to_author = capture_turbo_stream_broadcasts author do
      to_heron = capture_turbo_stream_broadcasts heron do
        to_quill = capture_turbo_stream_broadcasts(quill) { create_group_thread(author, heron, quill) }
      end
    end
    assert_empty to_author
    [to_heron, to_quill].each do |streams|
      assert_equal [%w[replace navbar-messages], %w[append live-region]],
                   streams.map { |stream| [stream["action"], stream["target"]] }
      assert_equal "#{author.callsign} sent you a message.", streams.last.text.strip
    end
  end

  private

  def search(query, with: []) = PersonMessage.search_for_person(@owner.id, query, with:)
  def suggest(query) = PersonMessage.search_suggestions_for_person(@owner.id, query)

  def folder(person, name) = PersonMessage.retrieve_for_person(person.id, name)

  def letter(sender, to:, reply_to: nil)
    PersonMessage.create!(person: to, sender_person: sender, creator_person: sender, reply_to:, subject: "Radios",
                          body: "Who has them?", sender_type: PersonMessage::SENDER_TYPE_PERSON)
  end

  # Three people a group thread can hold, mailbox users all.
  def group_people
    [person(:active_ranger), person(:ranger_with_custom_gender), person(:plate_collision_ranger)]
  end
end
