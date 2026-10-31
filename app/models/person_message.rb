# frozen_string_literal: true

class PersonMessage < ApplicationRecord
  self.table_name = "person_message"

  # Associations
  belongs_to :broadcast, optional: true
  belongs_to :person
  belongs_to :creator_person, class_name: "Person", optional: true
  belongs_to :sender_person, class_name: "Person", optional: true
  belongs_to :sender_team, class_name: "Team", optional: true
  belongs_to :recipient_team, class_name: "Team", optional: true
  belongs_to :creator_position, class_name: "Position", optional: true
  belongs_to :reply_to, class_name: "PersonMessage", optional: true

  # By id: created_at holds whole seconds, and ids run in date order.
  has_many :replies, -> { order(:id) },
           class_name: "PersonMessage",
           foreign_key: :reply_to_id,
           dependent: :destroy,
           inverse_of: :reply_to

  # A group thread's people, the sender included, each with their own read and
  # archive state; on the thread top only (see #group?).
  has_many :members, class_name: "PersonMessageMember", dependent: :delete_all, inverse_of: :person_message

  SENDER_TYPE_PERSON = "person" # from a Clubhouse user
  SENDER_TYPE_TEAM = "team" # from a Clubhouse Team - cadre / delegation
  SENDER_TYPE_OTHER = "other" # from a S.O, friend, another department -- usually a walk-up to HQ Window
  SENDER_TYPE_RBS = "rbs" # Broadcast message

  MESSAGE_TYPE_NORMAL = "normal"
  MESSAGE_TYPE_CONTACT = "contact"
  MESSAGE_TYPE_MENTOR = "mentor"

  FOLDER_ARCHIVED = "archived"
  FOLDER_INBOX = "inbox"
  FOLDER_SENT = "sent"
  FOLDER_UNREAD = "unread"

  VALID_FOLDERS = [FOLDER_ARCHIVED, FOLDER_INBOX, FOLDER_SENT, FOLDER_UNREAD].freeze

  # The pages that show a mailbox (MessagesConcern#messages_route_prefix): the
  # owner's own, and Person and HQ for a manager viewing it. Each listens on
  # [owner, :messages, namespace] (common/messages/_workspace), since a list
  # row's link is the namespace's path.
  MAILBOX_NAMESPACES = %w[me person hq].freeze

  # InnoDB's default full-text stopwords of three letters or more
  # (information_schema.INNODB_FT_DEFAULT_STOPWORD); the shorter ones are short
  # words already. Never indexed, so search_for_person leaves them out.
  SEARCH_STOPWORDS = %w[about are com for from how that the this und was what when where who will with www].to_set.freeze

  # The letters the search's columns compare without their accents
  # (utf8mb4_unicode_ci), so the database finds "Café" for "cafe" and "cafe" for
  # "café": each base letter with the accented forms Latin-1 and Latin Extended
  # A, B and Additional make of it, in both cases, and the marks after it in
  # text written decomposed. Both cases are written out because a pattern built
  # of them runs without /i, which costs Onigmo its fast search over a class
  # holding letters beyond ASCII (search_letters).
  SEARCH_ACCENTED_LETTERS = [*0xC0..0x24F, *0x1E00..0x1EFF].map { |code| code.chr(Encoding::UTF_8) }
                                                            .select { |char| char.downcase.length == 1 && char.upcase.length == 1 }
                                                            .group_by { |char| char.unicode_normalize(:nfd)[0].downcase }
                                                            .select { |base, _| base.match?(/\A[a-z]\z/) }
                                                            .to_h { |base, chars| [base, "[#{[base, base.upcase, *chars.flat_map { |char| [char.downcase, char.upcase] }].uniq.join}]\\p{Mn}*"] }
                                                            .freeze

  # The most text a message may hold, its markup not counted, and the most
  # markup that may carry it (MessageTextValidator): the column holds 16MB.
  MAX_TEXT = 4000
  MAX_HTML_BYTES = 64.kilobytes

  # The blocks the rich text editor writes. Lexxy puts every line inside one, a
  # paragraph at the least, so its HTML begins with one (RICH_TEXT_START). No
  # body written before it does -- 26,045 rows on dev (2026-10-18), 17 holding
  # something tag-like, such as "<eom>" or "<name@example.org>" -- and a plain
  # body such as "I <3 Outpost" never can.
  RICH_TEXT_BLOCKS = %w[p h1 h2 h3 h4 h5 h6 ul ol li blockquote pre figure table tr td th hr div].freeze
  RICH_TEXT_START = %r{\A\s*<(?:#{RICH_TEXT_BLOCKS.join("|")})[\s/>]}i

  # Where a line of the text ends: after a block, a line break or a divider.
  RICH_TEXT_LINE_END = %r{</(?:#{RICH_TEXT_BLOCKS.join("|")})>|<(?:br|hr)\b[^>]*>}i

  # Validations
  validates :message_from, length: { maximum: 255 }
  validates :subject, presence: true, length: { maximum: 255 }
  validates :body, message_text: true
  validates :sender_type, presence: true, on: :create

  validate :validate_sender, on: :create
  validate :validate_sender_type, on: :create
  validate :validate_recipient, on: :create
  validate :validate_reply, on: :create

  before_create :set_created_at
  before_create :set_creator

  # After the members' autosave (has_many :members, above): a group top's are
  # saved by then.
  after_create :add_members
  # A team thread's roster, read anew at the top's send and at every reply
  # (.scratch/team-messaging/PRD.md): the one writer of team-marked members,
  # a callback on purpose so every path that saves a row in the thread syncs
  # it. Before the barred check, which reads the members it loads.
  after_create -> { thread_top.sync_team_members!(self) }, if: -> { teams.any? }
  after_create :read_for_barred_members, if: -> { group? && reply_to_id }

  after_create_commit :announce_to_recipient

  # Class Methods

  # A deleted person's messages stay, since the schema has no foreign keys,
  # and name them as LinkHelper#person_display_name names a person no longer there.
  def self.deleted_name(person_id) = "Deleted ##{person_id}"

  # A team deleted since (TeamManagement.destroy leaves a thread's team ids in
  # place), named as a deleted person is.
  def self.deleted_team_name(team_id) = "Deleted Team ##{team_id}"

  ##
  # Is the body the rich text editor's HTML (slice 4 of the messaging rework)?
  # Anything else -- every message from before it, the RBS's copies, imports
  # -- is plain text, which hyperlink_text renders.
  #
  def self.rich_text?(body)
    RICH_TEXT_START.match?(body.to_s)
  end

  ##
  # A body as the reader reads it: the editor's HTML with each block and line
  # break a line of its own (no blank ones), the tags gone and the
  # entities decoded. Plain text comes back as it is, so "a < b" keeps its "<".
  # Markup nested deeper than Nokogiri parses (400 levels), which the editor
  # never writes, has none: nil, which MessageTextValidator refuses.
  #
  def self.plain_text(body)
    body = body.to_s
    return body unless rich_text?(body)

    fragment = Nokogiri::HTML5.fragment(body.gsub(RICH_TEXT_LINE_END) { |line_end| "#{line_end}\n" })
    # What the sanitized card never shows, a crafted script, is not text either.
    fragment.css("script, style").remove
    fragment.text.gsub(/[ \t]*\n\s*/, "\n").strip
  rescue ArgumentError # "Document tree depth limit exceeded"
    nil
  end

  ##
  # Unread threads for a person: thread-tops, not expired, whose member row
  # for them is unread (#unread_member_threads). Every thread has member rows
  # since the member model (.scratch/messaging-rework/member-model-plan.md):
  # a one-to-one thread its recipient and sender, a broadcast, walk-up or
  # import its recipient, a group thread everyone in it.
  #
  # One semi-join, nothing OR'd around it. Measured on a copy of dev
  # (Handler_read, 2026-10-18): 1,237 reads for the heaviest mailbox, 30 for
  # a typical one; plucking the ids first saved a sixth on the heaviest and
  # cost a second query. A UNION inside the subquery, or an OR around it,
  # turns it into a scan of the whole table (slice 3's 4.2 million reads).
  #
  # Only broadcasts expire, so the exclusion keeps NULL explicitly: a bare
  # where.not compiles to `column != value`, which is never true for NULL.
  #
  # This is the single source of truth shared by the Unread folder,
  # count_unread, and most_recent_unread_message so the badge count can
  # never disagree with the Unread folder. #thread_read? applies the same
  # rule to one loaded thread, expiry included: an expired message reads as
  # read (#read?), so its row and card show no New it is not counted for.
  #
  def self.unread_for_person(person_id)
    where(reply_to_id: nil, id: unread_member_threads(person_id))
      .and(where(expires_at: nil).or(where.not(expires_at: ..Current.time)))
  end

  ##
  # The threads a person is a member of and has not read, as a subquery:
  # never read at all, or holding a row someone else wrote after the newest
  # one they read (last_read_message_id, ruling D2). A broadcast, walk-up or
  # import has no sender person, so a NULL sender is someone else, kept
  # explicitly as above. #thread_read? is the same rule over one loaded thread.
  #
  def self.unread_member_threads(person_id)
    row = arel_table.alias("thread_row")
    member = PersonMessageMember.arel_table
    in_thread = row[:id].eq(member[:person_message_id]).or(row[:reply_to_id].eq(member[:person_message_id]))
    someone_else = row[:sender_person_id].eq(nil).or(row[:sender_person_id].not_eq(person_id))
    newer = someone_else.and(row[:id].gt(member[:last_read_message_id]))
    PersonMessageMember.where(person_id:)
                       .joins(member.join(row).on(in_thread).join_sources)
                       .where(member[:last_read_message_id].eq(nil).or(newer))
                       .select(:person_message_id)
  end
  private_class_method :unread_member_threads

  ##
  # Find all messages for a person
  #
  # A thread is in Inbox or Archived by the person's member row (by
  # index_person_message_member_on_person_id_and_archived), and in Sent when
  # they started it.
  #
  def self.retrieve_for_person(person_id, folder)
    folder = FOLDER_INBOX if folder.blank?

    sql = case folder
          when FOLDER_INBOX, FOLDER_ARCHIVED
            archived = folder == FOLDER_ARCHIVED
            where(id: PersonMessageMember.where(person_id:, archived:).select(:person_message_id))
          when FOLDER_SENT
            where(sender_person_id: person_id)
          when FOLDER_UNREAD
            unread_for_person(person_id)
          else
            raise ArgumentError, "Unknown folder type"
          end

    thread_list(sql)
  end

  ##
  # The person's Unread folder as thread-top ids, in the folder's own order
  # (the thread that moved last first, as thread_list sorts it), without loading
  # a thread: Next Unread asks for it on every pane header on Person and HQ.
  #
  def self.unread_thread_ids(person_id)
    tops = unread_for_person(person_id).pluck(:id)
    moved = where(reply_to_id: tops).group(:reply_to_id).maximum(:id)
    tops.sort_by { |id| moved[id] || id }.reverse
  end

  ##
  # The person's threads that a search finds, in every folder, newest activity
  # first: a thread they are a member of holding a row, whoever wrote it, whose
  # subject or text holds every word of the query (each as the start of a
  # word), or another member whose callsign starts with the whole query,
  # compared as the compose form's lookup does (callsign_normalized: no case,
  # accents or punctuation). A reply's hit lists its thread, by
  # COALESCE(reply_to_id, id).
  #
  # The thread ids and the hits are plucked: the top's and the replies' ids
  # OR'd cannot be one semi-join, and the hits as a subquery under the
  # callsign's OR made MariaDB scan the table for the short-word fallback
  # (73,903 reads against 1,656 on the heaviest mailbox of a copy of dev).
  #
  # InnoDB indexes no word shorter than innodb_ft_min_token_size (3) and no
  # stopword, and a required word it never indexed matches nothing, so those
  # are left out of the MATCH; a query of nothing else matches the whole query
  # anywhere in the subject or text instead. Only letters, digits and '_'
  # reach AGAINST, so the query's own + - * " ( ) ~ < > @ are never operators.
  #
  # A callsign is matched among the members a thread names
  # (PersonMessageMember.named), as its row in the list names them: one a team
  # brought in is the team there, and is found by the team's name.
  #
  # +with+ is the people the search field holds as chips: only threads naming
  # every one of them are searched, and with no query they are all listed. A
  # chip that names nobody is nil, and finds nothing, never the rest.
  #
  def self.search_for_person(person_id, query, with: [])
    return [] if with.include?(nil)

    query = query.to_s.strip
    thread_ids = PersonMessageMember.where(person_id:).pluck(:person_message_id)
    thread_ids = threads_with(thread_ids, with) if with.any?
    return thread_list(where(id: thread_ids)) if query.empty?

    words = search_words(query)
    text = if words.any?
             where("MATCH(subject, body_text) AGAINST (? IN BOOLEAN MODE)", words.map { |word| "+#{word}*" }.join(" "))
           else
             like = "%#{sanitize_sql_like(query)}%"
             where(arel_table[:subject].matches(like)).or(where(arel_table[:body_text].matches(like)))
           end
    hits = where(id: thread_ids).or(where(reply_to_id: thread_ids)).and(text)
                                .distinct.pluck(Arel.sql("COALESCE(reply_to_id, id)"))
    callsign = WordUtils.normalize_word(query)
    if callsign.present?
      # Never the chips' own people: every thread left names them.
      people = Person.where(Person.arel_table[:callsign_normalized].matches("#{sanitize_sql_like(callsign)}%")).select(:id)
      hits += PersonMessageMember.named.where(person_message_id: thread_ids, person_id: people)
                                 .where.not(person_id: [person_id, *with.map(&:id)]).pluck(:person_message_id)
    end
    # A team thread is listed under its teams' names (#group_party_names), so
    # a name holding the query finds it too. Plucked, as above.
    team_ids = Team.where(Team.arel_table[:title].matches("%#{sanitize_sql_like(query)}%")).pluck(:id)
    if team_ids.any?
      hits += where(id: thread_ids, sender_team_id: team_ids).or(where(id: thread_ids, recipient_team_id: team_ids)).pluck(:id)
    end

    thread_list(where(id: hits))
  end

  # The ones of +thread_ids+ that name every one of +people+.
  def self.threads_with(thread_ids, people)
    people.reduce(thread_ids) do |ids, person|
      PersonMessageMember.named.where(person_message_id: ids, person_id: person.id).pluck(:person_message_id)
    end
  end
  private_class_method :threads_with

  ##
  # What the search field suggests for +query+ (MessagesConcern#suggest), from
  # the person's own threads alone. People: the others they name whose
  # callsign starts with it, compared as search_for_person compares one, the
  # most threads shared first, each with that count, less +without+ (the
  # field's chips). Teams: those a thread was written to or as whose name
  # holds it, as search_for_person finds a team thread by it, matched by name
  # first: most text names no team.
  #
  def self.search_suggestions_for_person(person_id, query, without: [], limit: 5)
    query = query.to_s.strip
    callsign = WordUtils.normalize_word(query)
    return { people: [], teams: [] } if callsign.blank?

    threads = PersonMessageMember.where(person_id:).select(:person_message_id)
    counts = PersonMessageMember.named.joins(:person).where(person_message_id: threads)
                                .where.not(person_id: [person_id, *without.map(&:id)])
                                .where(Person.arel_table[:callsign_normalized].matches("#{sanitize_sql_like(callsign)}%"))
                                .group(:person_id).order(Arel.star.count.desc, Person.arel_table[:callsign].minimum)
                                .limit(limit).count
    people = Person.where(id: counts.keys).index_by(&:id)
    teams = Team.where(Team.arel_table[:title].matches("%#{sanitize_sql_like(query)}%")).order(:title).to_a
    if teams.any?
      tops = where(id: threads)
      team_ids = teams.map(&:id)
      used = tops.where(sender_team_id: team_ids).or(tops.where(recipient_team_id: team_ids))
                 .distinct.pluck(:sender_team_id, :recipient_team_id).flatten.to_set
      teams = teams.select { |team| used.include?(team.id) }
    end
    { people: counts.map { |id, count| [people.fetch(id), count] }, teams: teams.first(limit) }
  end

  # The people the threads of +person_id+'s mailbox name
  # (PersonMessageMember.named), the only ones a search's chip can find
  # anything with. A chip is looked up among them alone (MessagesConcern#search_chips),
  # so its spelling never tells whether a callsign names anyone else.
  def self.correspondents(person_id)
    threads = PersonMessageMember.where(person_id:).select(:person_message_id)
    Person.where(id: PersonMessageMember.named.where(person_message_id: threads).select(:person_id))
  end

  # The words of a query that the full-text index can match. InnoDB counts
  # '_' as part of a word, so "dirt_shift" is one word, found by its start
  # ("dirt", "dirt_shift") and never by "shift", the middle of a word.
  def self.search_words(query)
    query.to_s.downcase.scan(/[[:alnum:]_]+/).uniq.reject { |word| word.length < 3 || SEARCH_STOPWORDS.include?(word) }
  end

  # What search_for_person matched, for marking it in the text: each word from
  # the start of a word to its end, or the whole query where no word was left,
  # its letters compared as the database compares them (search_letters). For
  # text all in ASCII (+ascii+), which no accent can be in, the query's letters
  # without their accents find the same as a plain string, which Onigmo
  # searches for many times faster than for the classes.
  def self.search_pattern(query, ascii: false)
    words = search_words(query)
    source = if words.empty?
               search_letters(query.to_s.strip, ascii:)
             else
               "(?<![[:alnum:]_])(?:#{words.map { |word| search_letters(word, ascii:) }.join("|")})[[:alnum:]_]*"
             end
    Regexp.new(source, ascii ? Regexp::IGNORECASE : 0)
  end

  # Each word of a search alone, as search_pattern finds it: where a word starts.
  def self.search_word_patterns(query, ascii: false)
    search_words(query).map { |word| Regexp.new("(?<![[:alnum:]_])#{search_letters(word, ascii:)}", ascii ? Regexp::IGNORECASE : 0) }
  end

  # +text+ as a pattern's source. A Latin letter, accented or not, is its
  # class (SEARCH_ACCENTED_LETTERS), or with +ascii+ its base letter alone.
  # Anything else is matched as written, its case aside: a letter of another
  # script with its own marks (й, が), a symbol, a mark on its own.
  def self.search_letters(text, ascii:)
    text.unicode_normalize(:nfc).each_char.map do |char|
      base, *marks = char.unicode_normalize(:nfd).chars
      letters = SEARCH_ACCENTED_LETTERS[base.downcase] if marks.all? { |mark| mark.match?(/\p{Mn}/) }
      if letters
        ascii ? Regexp.escape(base) : letters
      elsif ascii || !char.match?(/\p{L}/)
        Regexp.escape(char)
      else
        "(?i:#{Regexp.escape(char)})"
      end
    end.join
  end
  private_class_method :search_letters

  ##
  # Thread-tops with everything the list draws loaded, the thread that moved
  # last first: by its newest row's id, as #replies orders them. The rosters
  # of every team thread in it come in one query, shared by the rows
  # (#addressed_from_team? reads them).
  #
  def self.thread_list(scope)
    tops = thread_list_rows(scope)
    team_ids = tops.flat_map(&:team_ids).uniq
    if team_ids.any?
      memberships = PersonTeam.where(team_id: team_ids).pluck(:team_id, :person_id).to_set
      tops.each { |top| top.current_team_memberships = memberships }
    end
    tops
  end
  private_class_method :thread_list

  def self.thread_list_rows(scope)
    scope.where(reply_to_id: nil)
         .order(id: :desc)
         .includes(
           {
             person: :avatar_photo_attachment,
             creator_person: :avatar_photo_attachment,
             sender_person: :avatar_photo_attachment
           },
           :creator_position,
           :sender_team,
           :recipient_team,
           members: :person,
           replies: %i[creator_person creator_position sender_team sender_person person]
         )
         .sort_by { |row| (row.replies.last || row).id }
         .reverse
  end
  private_class_method :thread_list_rows

  ##
  # A new group thread from the author to the people named (ruling D2): every
  # row of it carries the author as person and sender, and its members are
  # the author, read, and each of them; a team's members join once it is
  # saved (#sync_team_members!). Written as a team when as_team: is among the
  # attributes (#as_team=).
  #
  def self.new_group_thread(author, people, **attributes)
    new(person: author, sender_person: author, sender_type: SENDER_TYPE_PERSON, group: true, **attributes).tap do |top|
      top.members.build(person: author)
      people.each { |person| top.members.build(person:) }
    end
  end

  ##
  # A reply in a group thread: the author's row, in the thread's subject,
  # written as a team when as_team: is among the attributes.
  #
  def self.new_group_reply(top, author, **attributes)
    new(person: author, sender_person: author, sender_type: SENDER_TYPE_PERSON, group: true, reply_to: top,
        subject: top.subject, **attributes)
  end

  ##
  # How many unread messages does the person have?
  #
  def self.count_unread(person_id)
    unread_for_person(person_id).count
  end

  # Each person's unread count, counted once however many announcements of a
  # message ask for it (#announce_reply).
  def self.unread_counts
    Hash.new { |counts, person_id| counts[person_id] = count_unread(person_id) }
  end

  ##
  # Get the most recent unread message for a person
  #
  def self.most_recent_unread_message(person_id)
    unread_for_person(person_id)
      .order(created_at: :desc)
      .first
  end

  # Instance Methods / Virtual Attributes

  ##
  # The body's text (PersonMessage.plain_text) goes into body_text with it,
  # whoever sets it. The full-text index reads body_text, not body: indexing the
  # editor's HTML would let "strong" or "href" find every message with a bold
  # word or a link. Notifications send it too, since an email or a text has no
  # use for the tags.
  #
  def body=(value)
    super
    self.body_text = self.class.plain_text(value)
  end

  def rich_text?
    self.class.rich_text?(body)
  end

  ##
  # Has the message expired?
  #
  def has_expired?
    return false if expires_at.blank?

    Current.time >= expires_at
  end

  ##
  # Retrieve the sender's approved mugshot
  #
  # Neither is there for a deleted person (#deleted_name).
  def sender_avatar
    sender_person&.avatar_photo
  end

  def recipient_avatar
    person&.avatar_photo
  end

  ##
  # UI Helper to decide how to display the sent date
  #
  def sent_before_today?
    return false if created_at.blank?

    !created_at.today?
  end

  ##
  # Was the message sent yesterday?
  #
  def sent_yesterday?
    return false if created_at.blank?

    created_at.to_date == Date.yesterday
  end

  ##
  # UI Helper to decide how to display the sent date
  #
  def sent_prior_year?
    return false if created_at.blank?

    created_at.year != Current.year
  end

  def from_person?
    sender_type == SENDER_TYPE_PERSON
  end

  def from_rbs?
    sender_type == SENDER_TYPE_RBS
  end

  def from_other?
    sender_type == SENDER_TYPE_OTHER
  end

  def from_team?
    sender_type == SENDER_TYPE_TEAM
  end

  ##
  # A person's message takes a reply, and so does every row of a group thread,
  # one written as a team included (.scratch/team-messaging/PRD.md): an author
  # is behind each. A broadcast, a walk-up or a Clubhouse 2 team message takes
  # none, by its kind, whatever its columns hold.
  #
  def accepts_replies?
    group? || from_person?
  end

  # Written as +team+: the team on the row, its author kept in
  # sender_person_id; nil for the author's own name.
  def as_team=(team)
    self.sender_team = team
    self.sender_type = team ? SENDER_TYPE_TEAM : SENDER_TYPE_PERSON
  end

  def sender_name
    case sender_type
    when SENDER_TYPE_PERSON
      author_callsign
    when SENDER_TYPE_TEAM
      sender_team&.title || self.class.deleted_team_name(sender_team_id)
    when SENDER_TYPE_RBS
      "Ranger Broadcasting Service"
    else
      message_from
    end
  end

  # The thread top: the row a thread's members, teams and state hang off.
  def thread_top
    reply_to || self
  end

  # The teams the thread is a conversation with (.scratch/team-messaging/PRD.md),
  # named on the top: the one it was sent as first, then the one it was sent
  # to. A Clubhouse 2 team message is not a group thread, so it has none.
  def teams
    top = thread_top
    top.group? ? [top.sender_team, top.recipient_team].compact.uniq : []
  end

  # The ids of #teams, in its order, a team since deleted included.
  def team_ids
    top = thread_top
    top.group? ? [top.sender_team_id, top.recipient_team_id].compact.uniq : []
  end

  # One of the thread's teams by name; one since deleted by its id.
  def team_name(team_id)
    teams.find { |team| team.id == team_id }&.title || self.class.deleted_team_name(team_id)
  end

  def team_member_now?(team_id, person_id)
    thread_top.current_team_memberships.include?([team_id, person_id])
  end

  # PersonMessage.thread_list hands every row of a list one roster.
  attr_writer :current_team_memberships

  # The teams the person may reply as: the thread's that may still be written
  # as (Team#messageable?) and that they are on now, never by the mark on
  # their member row (a leaver cannot speak for the team).
  def reply_teams_for(person_id)
    teams.select { |team| team.messageable? && team_member_now?(team.id, person_id) }.sort_by(&:title)
  end

  # Whom a row written as a team names its author to: a member of that team,
  # on its roster now (ruling R3 of .scratch/team-messaging/PRD.md).
  def reveals_author_to?(person_id)
    from_team? && group? && team_member_now?(sender_team_id, person_id)
  end

  # The team the author of an individual row was marked a member of and has
  # since left; nil otherwise, and always for a row written as the team.
  def former_team
    return unless from_person? && group?

    team_id = member(sender_person_id)&.team_id
    teams.find { |team| team.id == team_id } if team_id && !team_member_now?(team_id, sender_person_id)
  end

  # Does the thread read as from a team to the person: sent as one they did
  # not write and are not on now. The roster, as the reveal and Reply As read
  # it, so a joiner and a leaver see one story (thread_list loads it for a
  # whole list).
  def addressed_from_team?(person_id)
    top = thread_top
    top.group? && top.from_team? && !top.sender?(person_id) && !team_member_now?(top.sender_team_id, person_id)
  end

  ##
  # The thread's roster, as of now (on the top), after +written+, the row just
  # saved in it. Every eligible member of each of its teams that may still be
  # written as (Team#messageable_members of a Team#messageable?) is a member
  # of the thread, marked with that team (person_message_member.team_id; the
  # first of #teams for someone on both): one who joined the team since the
  # thread began joins it here, unread, and one named directly is marked too.
  # So is whoever just wrote as the team, eligible or not (a manager writing
  # as someone who never signed in), or their name would stand beside it.
  # Nobody is removed: one who left the team keeps their row and its mark,
  # which is how their later replies are shown. Run after every save in the
  # thread, so it is idempotent. When anything changed the members are loaded
  # again with their people, as set_message and thread_list load them, for
  # the announcements that follow.
  #
  def sync_team_members!(written = self)
    # The rows as loaded (the request's, or one query), so a reply that
    # changes nothing writes nothing and locks nothing.
    marks = members.to_h { |member| [member.person_id, member.team_id] }
    changed = teams.select(&:messageable?).map do |team|
      person_ids = team.messageable_members.pluck(:id)
      person_ids |= [written.sender_person_id] if written.from_team? && written.sender_team_id == team.id
      fresh = person_ids.reject { |person_id| marks[person_id] }
      unmarked, missing = fresh.partition { |person_id| marks.key?(person_id) }
      members.where(person_id: unmarked).update_all(team_id: team.id) if unmarked.any?
      PersonMessageMember.insert_all(missing.map { |person_id| { person_message_id: id, person_id:, team_id: team.id } }) if missing.any?
      fresh.each { |person_id| marks[person_id] = team.id }
      fresh.any?
    end
    return if changed.none?

    members.reset
    ActiveRecord::Associations::Preloader.new(records: [self], associations: { members: :person }).call
  end

  # The author's callsign, whatever name the row was written under.
  def author_callsign
    sender_person&.callsign || self.class.deleted_name(sender_person_id)
  end

  ##
  # The person's member row of the thread: who the thread is between, each
  # with their own read and archive state (PersonMessageMember), from the
  # loaded members, so a list that includes them costs no query. A one-to-one
  # thread's are its recipient and its sender; a broadcast's, walk-up's or
  # import's its recipient. A group thread (group?, set on every row of it,
  # the top and each reply) is one conversation shared by several people:
  # each row's person_id and sender_person_id are its author.
  #
  def member(user_id)
    thread_top.members.find { |membership| membership.person_id == user_id }
  end

  # Everyone in the group thread but the person; +through+ caps it at the
  # member rows written by then (GroupMessageAnnounceJob). A member row may
  # outlive its person (a deletion before Person's dependent: :delete_all), so
  # it names nobody and is skipped, here and in #participants.
  def other_members(user_id, through: nil)
    rows = thread_top.members
    rows = rows.select { |row| row.id <= through } if through
    rows.filter_map(&:person).reject { |person| person.id == user_id }
  end

  # "Khaki Delegation, Quill": the thread's teams by name, then the callsigns
  # of the members named directly, the viewer left out (ruling R6 of
  # .scratch/team-messaging/PRD.md). To someone it reads as from a team
  # (#addressed_from_team?), the team alone: the rest are who it went to, not
  # who it is from. A member row may name nobody (#other_members).
  def group_party_names(user_id)
    top = thread_top
    return [team_name(top.sender_team_id)] if addressed_from_team?(user_id)

    named = top.members.reject { |member| member.team_id || member.person_id == user_id }
    team_ids.map { |team_id| team_name(team_id) } + named.filter_map(&:person).map(&:callsign).sort_by(&:downcase)
  end

  # The thread as its reader reads it: this message, then its replies, oldest
  # first.
  def thread_rows = [self, *replies]

  ##
  # Mark the entire thread as read for a person: their member row, through
  # the rows shown (PersonMessageMember#mark_read!). +through+ caps them at the
  # newest message a page showed, when the replies loaded here may hold newer
  # ones it never did (a reply's author, MessagesConcern#create_reply).
  #
  def mark_thread_read!(user_id, through: nil)
    rows = thread_rows
    rows = rows.select { |row| row.id <= through } if through
    member(user_id).mark_read!(rows)
  end

  ##
  # Flip the thread's read state for a person and return the new state.
  # Marking read clears the whole thread for them. Marking unread puts their
  # member row just before the newest row someone else wrote, so that row
  # alone reads New, or back to never read with none.
  #
  def toggle_thread_read!(user_id)
    read = !thread_read?(user_id)
    if read
      mark_thread_read!(user_id)
    else
      member(user_id).mark_unread_from!(thread_rows.reject { |row| row.sender?(user_id) }.max_by(&:id))
    end
    read
  end

  # Flip the thread's archived state for a person, their member row's, and
  # return the new state.
  def toggle_archived!(user_id)
    membership = member(user_id)
    membership.update!(archived: !membership.archived?)
    membership.archived?
  end

  # A row is read by its author, and by a member who has read the thread up to
  # it or past it (last_read_message_id, ruling D2). An expired message (only
  # broadcasts expire) is read by everyone: unread_for_person leaves it out.
  def read?(user_id)
    return true if sender?(user_id) || has_expired?

    last_read = member(user_id)&.last_read_message_id
    last_read.present? && id <= last_read
  end

  ##
  # Is the whole thread read for a person: this message and every reply?
  # Reads the loaded replies, so a list that includes them costs no query.
  # A thread its member never read is unread, whoever wrote its rows.
  #
  def thread_read?(user_id)
    return true if has_expired?
    return false if member(user_id)&.last_read_message_id.nil?

    thread_rows.all? { |row| row.read?(user_id) }
  end

  def unread?(user_id)
    !read?(user_id)
  end

  def sender?(user_id)
    (sender_person_id == user_id)
  end

  # May the person open the thread: one of its members.
  def participant?(user_id)
    member(user_id).present?
  end

  # Who the thread is between: its members (one, for a note to self).
  def participants
    members.filter_map(&:person)
  end

  def archived?(user_id)
    member(user_id)&.archived? || false
  end

  ##
  # Tell one person's open pages that a message arrived: their navbar envelope
  # takes their unread count, and a screen reader hears who sent it.
  #
  def announce_arrival_to(recipient, count)
    Turbo::StreamsChannel.broadcast_render_to(recipient, partial: "common/messages/arrival",
                                                         locals: { sender_name:, count: })
  end

  ##
  # A reply lands in its thread wherever that is open (slice 5 of the
  # messaging rework): every participant's stream [participant, thread top],
  # the author's included, which the pane subscribes to for the mailbox's
  # owner (common/messages/_messages_panel) -- on their own page and on the
  # Person and HQ pages viewing their mailbox. Each gets the card as that
  # participant sees it, New or not. The author's form appends the same card,
  # and Turbo's append replaces a child with the card's id, so it never shows
  # twice. Before the card, the thread's row and the Unread count go to each
  # participant's mailbox lists (MAILBOX_NAMESPACES), so on /me the read that
  # the card's arrival makes (thread_live_controller) answers after them. A new
  # thread top is open and listed nowhere yet, so it sends neither, which also
  # keeps an RBS broadcast to thousands from rendering a card for each.
  # +counts+ is PersonMessage.unread_counts, shared with the envelopes.
  #
  def announce_reply(counts)
    return unless reply_to_id

    # Loaded afresh: replies the request loaded before this one was saved lack
    # it. One hash, so one Preloader, which loads each class once
    # (MessagesConcern#set_message).
    top = PersonMessage.includes(replies: {}, sender_team: {}, recipient_team: {}, person: :avatar_photo_attachment,
                                 sender_person: :avatar_photo_attachment, members: :person).find(reply_to_id)
    top.participants.each do |participant|
      announcing(participant) do
        MAILBOX_NAMESPACES.each do |namespace|
          Turbo::StreamsChannel.broadcast_render_to(
            participant, :messages, namespace,
            partial: "common/messages/list_reply",
            locals: { message: top, owner: participant, namespace:, count: counts[participant.id] }
          )
        end
      end
      announcing(participant) do
        Turbo::StreamsChannel.broadcast_append_to(participant, top, target: "messages-thread",
                                                                    partial: "common/messages/message_card",
                                                                    locals: { message: self, owner: participant })
      end
    end
  end

  # One announcement, to one person when given: an error is logged, never
  # re-raised (#announce_to_recipient says why), whoever it was for.
  def announcing(person = nil)
    yield
  rescue StandardError => e
    ErrorLog.record_exception(e, "message-announce-exception", extra: { person_message_id: id, person_id: person&.id })
  end

  protected

  # Who is on the thread's teams now, as [team id, person id] pairs: one query
  # per thread render, memoized on the top (#team_member_now? asks it there),
  # shared by every card and the reply form.
  def current_team_memberships
    @current_team_memberships ||= PersonTeam.where(team_id: team_ids).pluck(:team_id, :person_id).to_set
  end

  private

  ##
  # Tell the recipient's open pages that a message arrived
  # (#announce_arrival_to) -- on a group row every member but its author, each
  # on their own -- and then, for a reply, every participant's
  # (#announce_reply).
  #
  # A group message's texts and emails wait for its GroupMessageAnnounceJob,
  # one per message, enqueued here: a Cadre of a hundred made the request text
  # each member in turn. Its pages update here, at once (owner's ruling
  # 2026-10-18, "Pages live, texts queued"), since the workers poll every 30
  # seconds.
  #
  # Every way a message is made passes through here, the RBS job's
  # save(validate: false) included; insert_all (the Clubhouse 2 archive merge)
  # skips callbacks, as it should. After commit, so a click on the envelope
  # finds the row, and the job finds it too. Nothing comes from Current: in a
  # request that is the sender, and the RBS job has none.
  #
  # Never re-raised: the message is already saved, and an error escaping an
  # after-commit callback leaves save, so the sender would see a failure, a
  # broadcast's job would stop partway through its recipients, and its retry
  # would send the first ones twice. The next page load shows the count anyway.
  # So everything here runs inside #announcing, the loads included (the
  # recipients, announce_reply's thread), each member's announcement in one of
  # its own, so one failure stops no one else's (review finding 11).
  #
  def announce_to_recipient
    counts = PersonMessage.unread_counts
    announcing do
      recipients = group? ? other_members(sender_person_id) : [person]
      recipients.each do |recipient|
        next if sender?(recipient.id) || !recipient.mailbox_user? || recipient.messages_barred?

        announcing(recipient) { announce_arrival_to(recipient, counts[recipient.id]) }
      end
    end
    announcing { announce_reply(counts) }
    # Through the member rows this message was saved among, so whoever a later
    # reply's sync brings in is not told of this one (its texts wait ~30 s).
    announcing { GroupMessageAnnounceJob.perform_later(id, thread_top.members.map(&:id).max) } if group?
  end

  ##
  # Setup creator person and position on message creation
  #
  def set_creator
    user_id = Current.person&.id
    return true unless user_id

    self.creator_person_id = user_id
    self.creator_position_id = Timesheet.where(person_id: user_id)
                                        .where(off_duty: nil)
                                        .pick(:position_id)

    true
  end

  ##
  # Setup and validate sender information

  def validate_sender_type
    case sender_type
    when SENDER_TYPE_PERSON
      sender_person_valid?
    when SENDER_TYPE_TEAM
      # A row written as a team (a group thread) keeps its author, so it takes
      # the person's checks too; Clubhouse 2's team rows, not group, have none.
      team_valid?(:sender_team_id) && (!group? || sender_person_valid?)
    when SENDER_TYPE_OTHER, SENDER_TYPE_RBS
      # No additional setup needed
      true
    else
      errors.add(:sender_type, "Unknown sender type #{sender_type}")
      false
    end
  end

  def sender_person_valid?
    if sender_person_id.nil?
      errors.add(:sender_person_id, "The sender is missing.")
      return false
    end

    if sender_person.nil?
      errors.add(:sender_person_id, "The sender does not exist.")
      return false
    end

    true
  end

  ##
  # A new thread's member rows (the member model,
  # .scratch/messaging-rework/member-model-plan.md). A one-to-one thread's are
  # its recipient, who has not read it, and its sender, who has: one member
  # for a note to self, read; the recipient alone when no person sent it (a
  # broadcast, a walk-up, a team message). A group top's named members came
  # with it (PersonMessage.new_group_thread), a team's join it through
  # #sync_team_members!; its author has read it up to its id, known only now.
  # A reply adds no one here; in a team thread #sync_team_members! may.
  #
  # Every way a message is made passes through here, the RBS job's
  # save(validate: false) included, inside the save's transaction. One
  # insert_all for both: an RBS broadcast makes a thread per recipient, and a
  # create! would look each person up again.
  #
  def add_members
    return if reply_to_id
    return member(sender_person_id).update!(last_read_message_id: id) if group?

    PersonMessageMember.insert_all([person_id, sender_person_id].compact.uniq.map do |member_id|
      { person_message_id: id, person_id: member_id, last_read_message_id: (id if member_id == sender_person_id) }
    end)
  end

  ##
  # A group reply counts unread for no member whose status now bars messages
  # (Person#messages_barred?; owner's ruling 2026-10-19, review finding 9):
  # their member row is read through it, so their Unread count, HQ's
  # unread-message prompt and its Deliver Messages todo leave it out. Nor is
  # their envelope told (#announce_to_recipient) or are they texted or
  # emailed (GroupMessageAnnounceJob). The thread top's members are loaded
  # already on a reply MessagesConcern builds.
  #
  def read_for_barred_members
    reply_to.members.each { |member| member.mark_read!([self]) if member.person&.messages_barred? }
  end

  ##
  # Setup sender person from message_from callsign
  #
  def validate_sender
    if (sender_type == SENDER_TYPE_OTHER) && message_from.blank?
      errors.add(:message_from, "Sender type is other and message_from is empty")
      return false
    end
    true
  end

  ##
  # Setup and validate recipient information
  #
  def validate_recipient
    if person_id.nil?
      errors.add(:person_id, "Missing person_id")
      return false
    end

    if person.nil?
      errors.add(:person_id, "Person does not exist")
      return false
    end

    # A group row's person is its author, whose status is not asked, as a
    # one-to-one sender's never is (owner's ruling 2026-10-19, review finding
    # 9): each member was checked as they were named, and one barred since is
    # skipped (#read_for_barred_members).
    if !group? && person.messages_barred?
      # A whole sentence: errors.format (config/locales/en.yml) drops the attribute name.
      errors.add(:person_id, "#{person.callsign} has a status that does not allow messages.")
      return false
    end

    # A group thread sent to a Cadre or Delegation names it here.
    return false if recipient_team_id.present? && !team_valid?(:recipient_team_id)

    true
  end

  ##
  # Validate reply_to_id if present

  def validate_reply
    return true if reply_to_id.blank?

    unless reply_to
      errors.add(:reply_to_id, "The original message was not found.")
      return false
    end

    unless reply_to.accepts_replies?
      errors.add(:reply_to_id, "The original message cannot be replied to.")
      return false
    end
    true
  end

  ##
  # Set created_at timestamp
  #
  def set_created_at
    self.created_at ||= Current.time
    true
  end

  ##
  # Validate team by attribute name
  #
  def team_valid?(column)
    team_id = send(column)
    if team_id.nil?
      errors.add(column, "is missing")
      return false
    end

    # The association: already loaded when the team was assigned as an object.
    team = send(column.to_s.delete_suffix("_id"))
    unless team
      errors.add(column, "team not found")
      return false
    end

    unless team.active
      errors.add(column, "team is inactive")
      return false
    end

    if team.type == Team::TYPE_TEAM
      errors.add(column, "team is not a Cadre or Delegation")
      return false
    end

    true
  end
end
