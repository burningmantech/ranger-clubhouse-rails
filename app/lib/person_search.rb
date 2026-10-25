# frozen_string_literal: true

# PersonSearch - Fuzzy search for people based on callsign, name, email, and FKA
# Supports phonetic matching, status filtering, and grouped results
#
# The thin client sends {q, mode, limit, filters}; the server (this class +
# Autocomplete::PersonAdapter) derives the search semantics and pre-renders HTML
# rows. PersonSearch returns a per-field shape ({field:, total:, people:}); the
# adapter normalizes it into the unified autocomplete envelope. The field-tag
# prefixes (callsign:/name:/fka:/last:/phone:) are parsed server-side here so the
# client stays dumb.
class PersonSearch
  # Contact is for the me/message page. Search is limited to active/current
  TYPE_CONTACT = :contact
  TYPE_MESSAGE = :message

  # Search field identifiers
  FIELD_CALLSIGN = "callsign"
  FIELD_EMAIL = "email"
  FIELD_OLD_EMAIL = "old-email"
  FIELD_FKA = "fka"
  FIELD_ID = "id"
  FIELD_NAME = "name"
  FIELD_LAST_NAME = "last"
  FIELD_PHONE = "phone"

  # Explicit field-tag prefixes a user can type to scope a search to one field,
  # e.g. "last:Smith", "name:Harper Hubcap", "fka:Sparkle", "callsign:Hubcap",
  # "phone:775-555-0142".
  # When present, the tag is stripped, the search is scoped to that single field,
  # and status grouping is cleared so the scoped search runs across ALL statuses.
  FIELD_TAG_REGEXP = /\A(callsign|name|fka|last|phone)\s*:\s*(.*)\z/im

  # Minimum query length (after any field-tag prefix is stripped).
  MIN_QUERY_LENGTH = 2

  # Pseudo status - find anyone signed up for a Cheetah Cub shift
  # Useful for HQ Window Worker handling a retired Ranger returning back
  CHEETAH_CUB_STATUS = "cheetahcub"

  # Base columns to select for person records.
  #
  # NOTE: `last_seen_at` is selected so the row renderer / future "recently seen"
  # affordances have it without a re-query. It is safe to drop if it ever causes drift.
  BASE_COLUMNS = %i[
    id
    callsign
    status
    first_name
    last_name
    preferred_name
    last_seen_at
  ].freeze

  # Status groups for organizing search results
  STATUS_GROUPS = [
    {
      title: "Active/Current",
      statuses: [
        Person::ACTIVE,
        Person::ALPHA,
        Person::INACTIVE,
        Person::INACTIVE_EXTENSION,
        Person::ECHELON,
        Person::PROSPECTIVE,
        Person::SUSPENDED
      ]
    },
    {
      title: "Auditor",
      statuses: [Person::AUDITOR]
    },
    {
      title: "Resigned/Retired",
      statuses: [
        Person::RESIGNED,
        Person::RETIRED
      ]
    },
    {
      title: "Dismissed/Bonked",
      statuses: [
        Person::BONKED,
        Person::DISMISSED,
        Person::UBERBONKED
      ]
    },
    {
      title: "Past Prospective",
      statuses: [Person::PAST_PROSPECTIVE]
    },
    {
      title: "Deceased",
      statuses: [Person::DECEASED]
    }
  ].freeze

  attr_accessor :results, :limit, :offset, :query, :statuses, :exclude_statuses, :messageable_only

  # Perform a fuzzy search for a person based on the given query
  #
  # @param query [Hash] Search parameters including query string, statuses, etc.
  # @param can_view_email [Boolean] Whether the searcher can view email addresses
  # @param can_view_phone [Boolean] Whether the searcher can view phone numbers
  # @return [Array] Search results organized by field type
  def self.execute(query, can_view_email: false, can_view_phone: false)
    return [] unless query[:query].present?

    # Remove duplicate spaces
    q = query[:query].to_s.gsub(/\s+/, " ").strip

    return [] if q.blank?

    # Search by ID if query starts with '+'
    if q.start_with?("+")
      begin
        person = Person.select(BASE_COLUMNS).find(q.delete_prefix("+"))
        return [
          {
            field: FIELD_ID,
            total: person ? 1 : 0,
            people: person ? [person] : []
          }
        ]
      rescue ActiveRecord::RecordNotFound
        return []
      end
    end

    # Explicit field-tag prefix (e.g. "last:Smith"). Strip the tag and scope the
    # search to that single field. Status grouping is preserved (when the caller
    # asked for it) so a tagged search is bucketed into status categories with real
    # chip counts, exactly like the default search. Every live status belongs to a
    # STATUS_GROUP, so grouping does not drop any matches. Parsed server-side to keep
    # the client thin.
    if (match = FIELD_TAG_REGEXP.match(q))
      field = match[1].downcase
      # A match shows the number, so only viewers who may read phones search them.
      return [] if field == FIELD_PHONE && !can_view_phone

      q = match[2].to_s.gsub(/\s+/, " ").strip
      # Re-check the minimum length AFTER stripping the tag.
      return [] if q.length < MIN_QUERY_LENGTH

      query = query.merge(search_fields: field)
    end

    # Email matches are status-agnostic by design: search_email/search_old_email
    # ignore the per-group status filter, so running them through the status-group
    # loop returns the same person in every category (the bogus all-"1" chip bar).
    # Route email straight to the flat path: one Email/Old Email group, no chips.
    return execute_query(q, query, can_view_email) if q.include?("@")

    if query[:status_groups]
      execute_search_status_groups(q, query, can_view_email)
    else
      execute_query(q, query, can_view_email)
    end
  end

  # Search callsigns for messaging (autocomplete)
  def self.search_callsigns_for_messaging(callsign, type)
    is_contact = type == TYPE_CONTACT
    query = {
      limit: is_contact ? 5 : 10
    }

    if is_contact
      # Only people a send would accept (Person.messageable, applied by
      # execute_query): listing anyone else would show that a callsign exists
      # but can't be messaged, which the compose page never says (roster
      # enumeration).
      fields = [FIELD_CALLSIGN]
      query[:match_prefix] = true
    else
      search_name = callsign.start_with?("name:")
      if search_name
        callsign = callsign[5..].strip
        # A min search length is required. There are (older) callsigns that are only 2 characters long.
        return [] if callsign.length < 2
      end

      fields = if is_contact
                 [search_name ? FIELD_NAME : FIELD_CALLSIGN]
               elsif search_name
                 [FIELD_NAME]
               else
                 [FIELD_CALLSIGN, FIELD_NAME]
               end
    end

    query[:search_fields] = fields.join(",")

    execute_query(callsign, query, false, is_contact).dig(0, :people) || []
  end

  # Execute search grouped by status categories
  #
  # @param q [String] Search query
  # @param query [Hash] Search parameters
  # @param can_view_email [Boolean] Whether to include email searches
  # @return [Array] Results grouped by status category
  def self.execute_search_status_groups(q, query, can_view_email)
    result_groups = []

    STATUS_GROUPS.each do |group|
      group_query = query.merge(statuses: group[:statuses])
      results = execute_query(q, group_query, can_view_email)
      next if results.empty?

      result_groups << {
        title: group[:title],
        results: results
      }
    end

    result_groups
  end

  # Execute the main search query
  #
  # @param q [String] Search query string
  # @param query [Hash] Search parameters
  # @param can_view_email [Boolean] Whether to search emails
  # @return [Array] Search results by field type
  def self.execute_query(q, query, can_view_email, is_contact = false)
    search = new
    search.query = q

    search.statuses = query[:statuses]
    if search.statuses.is_a? String
      search.statuses = search.statuses.split(",")
    end

    search.exclude_statuses = query[:exclude_statuses]
    if search.exclude_statuses.is_a? String
      search.exclude_statuses = search.exclude_statuses.split(",")
    end

    search.messageable_only = is_contact
    search.offset = query[:offset] || 0
    search.limit = query[:limit] || 10
    search.results = []

    search_fields = query[:search_fields]
    email_only = q.include?("@")

    if email_only && can_view_email
      search.search_email
      search.search_old_email
    else
      search_fields.to_s.split(",").each do |field|
        case field
        when FIELD_CALLSIGN
          search.search_callsign(match_prefix: query[:match_prefix])
        when FIELD_FKA
          search.search_fka
        when FIELD_NAME
          search.search_name
        when FIELD_LAST_NAME
          search.search_last_name
        when FIELD_PHONE
          search.search_phone
        end
      end
    end

    search.results
  end

  # Search for callsigns with phonetic matching
  #
  # @param match_prefix [Boolean] Whether to match only prefix or substring
  def search_callsign(match_prefix: false)
    sql = base_sql
    normalized = WordUtils.normalize_word(query)
    metaphone = WordUtils.metaphone(query)

    # Build WHERE clause conditions
    sql = if match_prefix
            sql.where(
              "callsign_normalized = ? OR callsign_soundex = ? OR callsign_normalized LIKE ?",
              normalized, metaphone, "#{normalized}%"
            )
          else
            sql.where(
              "callsign_normalized = ? OR callsign_soundex = ? OR callsign_normalized LIKE ? OR callsign_soundex LIKE ?",
              normalized, metaphone, "%#{normalized}%", "#{metaphone}%"
            )
          end

    # Callsign sort priority:
    # - Exact callsign match
    # - Beginning of callsign match
    # - Substring callsign match (if not match_prefix)
    # - Exact phonetic callsign match
    # - Beginning of phonetic match
    # - Substring phonetic match (if not match_prefix)
    # - Everything else
    order_sql = "CASE"
    order_sql += " WHEN callsign_normalized = #{sanitize_sql_value(normalized)} THEN CONCAT('01', callsign)"
    order_sql += " WHEN callsign_normalized LIKE #{sanitize_sql_value("#{normalized}%")} THEN CONCAT('02', callsign)"
    unless match_prefix
      order_sql += " WHEN callsign_normalized LIKE #{sanitize_sql_value("%#{normalized}%")} THEN CONCAT('03', callsign)"
    end
    order_sql += " WHEN callsign_soundex = #{sanitize_sql_value(metaphone)} THEN CONCAT('04', callsign)"
    order_sql += " WHEN callsign_soundex LIKE #{sanitize_sql_value("#{metaphone}%")} THEN CONCAT('05', callsign)"
    unless match_prefix
      order_sql += " WHEN callsign_soundex LIKE #{sanitize_sql_value("%#{metaphone}%")} THEN CONCAT('06', callsign)"
    end
    order_sql += " ELSE CONCAT('99', callsign) END"

    sql = sql.order(Arel.sql(order_sql))

    add_result(run_sql(sql, FIELD_CALLSIGN))
  end

  # Search by first/last name or preferred name
  def search_name
    sql = base_sql
    like_name = "%#{query}%"

    sql = sql.where(
      "CONCAT(first_name, ' ', last_name) LIKE ? OR " \
        "(preferred_name != '' AND CONCAT(preferred_name, ' ', last_name) LIKE ?) OR " \
        "last_name LIKE ?",
      like_name, like_name, "#{query}%"
    )

    # Sort by name match priority.
    #
    # Last-name-prefix matches sort under "11" + the last_name COLUMN
    # (CONCAT('11', last_name)) so results are actually prioritized by last name.
    # Pinned by a regression test in test/lib/person_search_test.rb
    # ("searchName sorts by last_name column").
    order_sql = "CASE"
    order_sql += " WHEN CONCAT(first_name, ' ', last_name) LIKE #{sanitize_sql_value(like_name)} THEN CONCAT('12', first_name, ' ', last_name)"
    order_sql += " WHEN CONCAT(preferred_name, ' ', last_name) LIKE #{sanitize_sql_value(like_name)} THEN CONCAT('12', preferred_name, ' ', last_name)"
    order_sql += " WHEN last_name LIKE #{sanitize_sql_value("#{query}%")} THEN CONCAT('11', last_name)"
    order_sql += " ELSE CONCAT('99', callsign) END"

    sql = sql.order(Arel.sql(order_sql))

    add_result(run_sql(sql, FIELD_NAME))
  end

  # Search by last name only
  def search_last_name
    sql = base_sql
    sql = sql.where("last_name LIKE ?", "#{query}%")
    sql = sql.order(:last_name)

    add_result(run_sql(sql, FIELD_LAST_NAME))
  end

  # Search for Formerly Known As (FKA) callsigns.
  #
  # Each matching row is annotated with the matched FKA string via a standardized
  # `fka_match` accessor, surfaced to _person_item.html.erb.
  # Because a single person can have several matching FKAs (the join yields one row
  # per FKA), people are de-duplicated here, keeping the first matched FKA.
  def search_fka
    normalized = WordUtils.normalize_word(query)
    metaphone = WordUtils.metaphone(query)
    sql = base_sql

    # Use ActiveRecord joins instead of raw SQL
    sql = sql.select(
      "person.*",
      "person_fka.fka",
      "person_fka.fka_normalized",
      "person_fka.fka_soundex",
      "person.callsign_normalized"
    )
    sql = sql.joins(:person_fka)
    sql = sql.where(person_fka: { is_irrelevant: false })
    sql = sql.order(:callsign)

    sql = sql.where(
      "person_fka.fka_normalized = ? OR person_fka.fka_normalized LIKE ? OR " \
        "person_fka.fka_soundex = ? OR person_fka.fka_soundex LIKE ?",
      normalized, "%#{normalized}%", metaphone, "#{metaphone}%"
    )

    add_result(run_fka_sql(sql, normalized, metaphone))
  end

  # Search for current email addresses
  def search_email
    sql = base_sql(add_statuses: false)
    sql = sql.where(email: query)

    add_result(run_sql(sql, FIELD_EMAIL))
  end

  # Search for old email addresses (ignores the status filter, as search_email
  # does). A subquery, not a join, so an address recorded twice still finds the
  # person once.
  def search_old_email
    sql = base_sql(add_statuses: false)
    sql = sql.where(id: EmailHistory.where(email: query).select(:person_id)).order(:callsign)

    add_result(run_sql(sql, FIELD_OLD_EMAIL))
  end

  # Search home and alternate phones for the typed digits anywhere in the number.
  # Both sides are compared as digits alone: "+1 (775) 555-0142" finds the stored
  # "+17755550142", a phone kept as typed from before numbers were stored in E.164
  # ("(775) 555-0142") still matches, and LIKE's % and _ never reach the pattern.
  # Each row carries the number that matched as `phone_match`, for
  # _person_item.html.erb.
  def search_phone
    digits = query.delete("^0-9")
    return if digits.length < MIN_QUERY_LENGTH

    like = "%#{digits}%"
    home_hit = Person.sanitize_sql_array(["REGEXP_REPLACE(home_phone, '[^0-9]', '') LIKE ?", like])
    alt_hit = Person.sanitize_sql_array(["REGEXP_REPLACE(alt_phone, '[^0-9]', '') LIKE ?", like])

    sql = base_sql.select("IF(#{home_hit}, home_phone, alt_phone) AS phone_match")
    sql = sql.where("#{home_hit} OR #{alt_hit}")
    sql = sql.order(:callsign)

    add_result(run_sql(sql, FIELD_PHONE))
  end

  # Build base SQL query with optional status filtering. exclude_statuses applies
  # either way: the email searches skip the status filter, but a caller that
  # excludes deceased people must not get them back from an email search.
  def base_sql(add_statuses: true)
    sql = Person.select(BASE_COLUMNS).includes(photo: :avatar_attachment)

    if add_statuses && statuses.present? && statuses != "all"
      # dup so a frozen status-array constant (e.g. HQ_STATUSES / STATUS_GROUPS)
      # isn't mutated by the delete below.
      status_list = (statuses.is_a?(String) ? statuses.split(",") : statuses).dup

      if status_list.delete(CHEETAH_CUB_STATUS)
        # Build EXISTS subquery for Cheetah Cub shifts using ActiveRecord
        cheetah_cub_subquery = PersonSlot.where("person_slot.person_id = person.id")
                                         .joins(:slot)
                                         .where(slot: { begins_year: Current.year, position_id: Position::CHEETAH_CUB })
                                         .arel.exists

        # Combine status filter with Cheetah Cub check
        sql = if status_list.any?
                sql.where(status: status_list).or(Person.where(cheetah_cub_subquery))
              else
                sql.where(cheetah_cub_subquery)
              end
      else
        sql = sql.where(status: status_list)
      end
    end

    # Harden against either an Array or a comma-separated String (latent NoMethodError
    # when an Array was passed and .split was called on it).
    if exclude_statuses.present?
      exclude_list = if exclude_statuses.is_a?(String)
                       exclude_statuses.split(",")
                     else
                       Array(exclude_statuses)
                     end
      sql = sql.where.not(status: exclude_list)
    end

    messageable_only ? sql.merge(Person.messageable) : sql
  end

  # Run the SQL query and format results
  #
  # @param sql [ActiveRecord::Relation] Query to execute
  # @param field [String] Field type being searched
  # @return [Hash] Results with field, total, and people array

  def run_sql(sql, field)
    total = sql.except(:select).count

    {
      field: field,
      total: total,
      people: total.positive? ? sql.limit(limit).offset(offset) : []
    }
  end

  # Run the FKA query, annotate each person with a standardized `fka_match`
  # accessor (the FKA string that matched), and de-duplicate people who have
  # several matching FKAs (the join yields one row per FKA), keeping the first.
  #
  # @param sql [ActiveRecord::Relation] Query to execute (already FKA-joined)
  # @param normalized [String] Normalized query for the substring match check
  # @param metaphone [String] Phonetic query for the soundex match check
  # @return [Hash] Results with field, total, and de-duplicated people array
  def run_fka_sql(sql, normalized, metaphone)
    rows = sql.limit(limit).offset(offset).to_a

    people = []
    seen = {}

    rows.each do |person|
      next if seen[person.id]

      seen[person.id] = true
      # Standardized `fka_match` accessor on the row. Defined as a singleton method
      # to avoid touching the Person model (AGENTS.md restricts model changes during
      # translation); _person_item.html.erb reads person.fka_match directly.
      annotate_fka_match(person, matched_fka(person, normalized, metaphone))
      people << person
    end

    {
      field: FIELD_FKA,
      total: people.size,
      people: people
    }
  end

  # The FKA string that caused the match, or nil. Report the matched FKA when the
  # normalized query is a substring of the row's normalized FKA, or the phonetic
  # query is a substring of the row's FKA soundex.
  def matched_fka(person, normalized, metaphone)
    fka_normalized = person.try(:fka_normalized).to_s
    fka_soundex = person.try(:fka_soundex).to_s

    if fka_normalized.include?(normalized) || fka_soundex.include?(metaphone)
      person.try(:fka)
    end
  end

  # Attach a singleton `fka_match` reader to a row without modifying the Person model.
  def annotate_fka_match(person, value)
    person.singleton_class.attr_accessor(:fka_match) unless person.respond_to?(:fka_match)
    person.fka_match = value
  end

  # Add result to results array if it has records
  #
  # @param result [Hash] Search result to add
  def add_result(result)
    return if result[:total].zero?
    results << result
  end

  private

  # Helper to sanitize a single SQL value
  def sanitize_sql_value(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
