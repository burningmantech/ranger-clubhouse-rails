# frozen_string_literal: true

require "test_helper"

class PersonSearchTest < ActiveSupport::TestCase
  # Build a valid Person without leaning on a fixture, so each test seeds exactly
  # the rows it asserts on (no fixtures :all ordering dependence). Persisted with
  # callbacks suppressed (insert!) so the status-change audit log — which requires a
  # prior status — isn't triggered for a brand-new test row; the in-memory object is
  # still run through the model so callsign_normalized/_soundex are computed.
  def build_person(callsign:, first_name:, last_name:, status: Person::ACTIVE, preferred_name: "")
    seq = @seq = (@seq || 0) + 1
    person = Person.new(
      callsign:,
      first_name:,
      last_name:,
      preferred_name:,
      mi: "",
      email: "pst#{seq}-#{SecureRandom.hex(4)}@example.com",
      status:,
      status_date: Current.today,
      password: "password",
      gender_identity: "cis-male",
      home_phone: "+17755550101",
      street1: "123 Main St",
      city: "San Francisco",
      state: "California",
      zip: "94102",
      country: "United States"
    )
    person.validate!
    Person.insert!(person.attributes.except("id").compact)
    Person.find_by!(email: person.email)
  end

  def people_for(results, field = nil)
    field_groups(results)
      .select { |r| field.nil? || r[:field] == field }
      .flat_map { |r| r[:people].to_a }
  end

  # Status-grouped searches return [{title:, results: [field groups]}]; flat searches
  # return the field groups directly. Normalize to a flat list of field groups so the
  # assertions can inspect :field / :people regardless of shape.
  def field_groups(results)
    return results unless results.first.is_a?(Hash) && results.first.key?(:results)

    results.flat_map { |group| group[:results] }
  end

  # --- field-tag parsing -----------------------------------------------------

  test "last: prefix scopes search to last name across all statuses" do
    smith = build_person(callsign: "TagSmith", first_name: "Aaron", last_name: "Smithfield")
    # A deceased person also matching the last name proves the tagged search spans
    # every status group (the match lands in the Deceased group, not dropped).
    dead_smith = build_person(callsign: "TagSmithDead", first_name: "Zed", last_name: "Smithson",
                              status: Person::DECEASED)

    results = PersonSearch.execute(
      { query: "last:Smith", search_fields: "callsign,name,fka", status_groups: true }
    )

    ids = people_for(results).map(&:id)
    assert_includes ids, smith.id
    assert_includes ids, dead_smith.id, "field-tag search must search ALL statuses"
    # Only the last field should have been searched.
    assert_equal [PersonSearch::FIELD_LAST_NAME], field_groups(results).map { |r| r[:field] }.uniq
  end

  test "name: prefix scopes search to name field" do
    harper = build_person(callsign: "Hubcap", first_name: "Harper", last_name: "Hubcapper")

    results = PersonSearch.execute(
      { query: "name:Harper Hub", search_fields: "callsign", status_groups: true }
    )

    assert_equal [PersonSearch::FIELD_NAME], field_groups(results).map { |r| r[:field] }.uniq
    assert_includes people_for(results).map(&:id), harper.id
  end

  test "field-tag re-checks min length after stripping the tag" do
    build_person(callsign: "ShortTag", first_name: "A", last_name: "Bee")

    # "last:B" -> stripped query "B" is below the 2-char minimum -> empty.
    results = PersonSearch.execute({ query: "last:B", search_fields: "name", status_groups: true })
    assert_equal [], results
  end

  test "callsign: prefix scopes search to callsign field" do
    person = build_person(callsign: "Zephyr", first_name: "Cee", last_name: "Dee")

    results = PersonSearch.execute(
      { query: "callsign:Zephyr", search_fields: "name", status_groups: true }
    )

    assert_equal [PersonSearch::FIELD_CALLSIGN], field_groups(results).map { |r| r[:field] }.uniq
    assert_includes people_for(results).map(&:id), person.id
  end

  # --- searchName last-name sort order ------

  test "searchName sorts by last_name column, not a string literal" do
    # Two people whose only difference is last name, sharing a common token so a
    # single name query returns both. If a quoted CONCAT('11','last_name') string
    # literal were used in the sort key, both would collapse to the same key and
    # order would be undefined; the last_name column orders by last name.
    zulu  = build_person(callsign: "SortZulu",  first_name: "Common", last_name: "Zephyrson")
    alpha = build_person(callsign: "SortAlpha", first_name: "Common", last_name: "Aardvarkson")

    results = PersonSearch.execute({ query: "Common", search_fields: "name" })
    people = people_for(results, PersonSearch::FIELD_NAME)
    sorted_ids = people.map(&:id)

    # Both are matched on "first last" (priority 12) and ordered by "Common <last>",
    # so Aardvarkson precedes Zephyrson.
    assert_operator sorted_ids.index(alpha.id), :<, sorted_ids.index(zulu.id),
                    "results must sort by the last_name column (Aardvarkson before Zephyrson)"
  end

  # --- cheetahcub pseudo-status (dormant; reachable only once hq is enabled) --

  # Build a Cheetah Cub shift in the given year and sign `person` up for it.
  # Validations are bypassed on the slot so the test needn't seed a Position row
  # (there is no DB foreign key on slot.position_id).
  def sign_up_for_cheetah_cub(person, year: Current.year)
    # `begins` must fall within `year`: Slot#compute_time_fields derives begins_year
    # from begins.year, overwriting any explicit begins_year.
    begins = Time.utc(year, 8, 1, 12, 0, 0)
    slot = Slot.new(
      position_id: Position::CHEETAH_CUB,
      begins:,
      ends: begins + 1.hour,
      max: 1,
      timezone_abbr: "PDT"
    )
    slot.save!(validate: false)
    PersonSlot.create!(person:, slot:)
    slot
  end

  test "cheetahcub status also matches people signed up for a Cheetah Cub shift this year" do
    # A non-active person signed up for a Cheetah Cub shift must be returned via the
    # OR-composed pseudo-status, while a non-active person without a shift must not.
    returner  = build_person(callsign: "CubReturner",  first_name: "Returning",  last_name: "Cubley", status: Person::RETIRED)
    bystander = build_person(callsign: "CubBystander", first_name: "Bystanding", last_name: "Cubley", status: Person::RETIRED)
    sign_up_for_cheetah_cub(returner)

    results = PersonSearch.execute({
      query: "Cub",
      search_fields: "callsign",
      statuses: [Person::ACTIVE, PersonSearch::CHEETAH_CUB_STATUS]
    })
    ids = people_for(results, PersonSearch::FIELD_CALLSIGN).map(&:id)

    assert_includes ids, returner.id, "a Cheetah Cub shift signup must match despite a non-active status"
    assert_not_includes ids, bystander.id, "a non-active person with no Cheetah Cub shift must not match"
  end

  test "cheetahcub shift signup in a different year does not match" do
    returner = build_person(callsign: "CubLastYear", first_name: "Last", last_name: "Yearly", status: Person::RETIRED)
    sign_up_for_cheetah_cub(returner, year: Current.year - 1)

    results = PersonSearch.execute({
      query: "CubLastYear",
      search_fields: "callsign",
      statuses: [Person::ACTIVE, PersonSearch::CHEETAH_CUB_STATUS]
    })
    ids = people_for(results, PersonSearch::FIELD_CALLSIGN).map(&:id)

    assert_not_includes ids, returner.id, "a prior-year Cheetah Cub shift must not match the current-year pseudo-status"
  end

  test "cheetahcub as the only status searches solely on Cheetah Cub shift signups" do
    signed = build_person(callsign: "CubOnlySigned", first_name: "Only", last_name: "Signed", status: Person::RETIRED)
    sign_up_for_cheetah_cub(signed)

    results = PersonSearch.execute({
      query: "CubOnly",
      search_fields: "callsign",
      statuses: [PersonSearch::CHEETAH_CUB_STATUS]
    })
    ids = people_for(results, PersonSearch::FIELD_CALLSIGN).map(&:id)

    assert_includes ids, signed.id
  end

  # --- phonetic (soundex) matching -------------------------------------------

  test "callsign search matches phonetically when the normalized LIKE misses" do
    # "Filer" normalizes to "filer" / soundex "FLR". The query "Phyler" normalizes to
    # "phyler" (NOT a substring of "filer", so the normalized LIKE branch misses) but
    # shares the soundex "FLR" — so only the phonetic branch can produce this match.
    person = build_person(callsign: "Filer", first_name: "Fee", last_name: "Lurr")

    results = PersonSearch.execute({ query: "Phyler", search_fields: "callsign" })
    ids = people_for(results, PersonSearch::FIELD_CALLSIGN).map(&:id)

    assert_includes ids, person.id, "a soundex-only match must still be returned"
  end

  # --- FKA matching: annotation + de-dup + is_irrelevant ---------------------

  test "search_fka annotates fka_match and excludes is_irrelevant FKAs" do
    person = build_person(callsign: "FkaPrimary", first_name: "Eff", last_name: "Kay")
    person.person_fka.create!(fka: "Sparkleton")
    # An irrelevant FKA (matches IRRELEVANT_REGEXP) must be excluded from search.
    irrelevant = build_person(callsign: "FkaIrrelevant", first_name: "Eye", last_name: "Are")
    irrelevant.person_fka.create!(fka: "Sparkle12")

    results = PersonSearch.execute({ query: "Sparkle", search_fields: "fka" })
    people = people_for(results, PersonSearch::FIELD_FKA)

    ids = people.map(&:id)
    assert_includes ids, person.id
    assert_not_includes ids, irrelevant.id, "is_irrelevant FKAs must be excluded"

    matched = people.find { |p| p.id == person.id }
    assert_equal "Sparkleton", matched.fka_match, "fka_match must expose the matched FKA"
  end

  test "search_fka de-duplicates a person with multiple matching FKAs" do
    person = build_person(callsign: "FkaMulti", first_name: "Dee", last_name: "Up")
    person.person_fka.create!(fka: "Glimmerton")
    person.person_fka.create!(fka: "Glimmerson")

    results = PersonSearch.execute({ query: "Glimmer", search_fields: "fka" })
    ids = people_for(results, PersonSearch::FIELD_FKA).map(&:id)

    assert_equal 1, ids.count(person.id), "a multi-FKA person must appear only once"
  end

  # Fixture-anchored variant referencing person_fka.yml BY NAME (deterministic data,
  # no fixtures :all ordering dependence). The relevant FKA is surfaced and annotated;
  # the is_irrelevant FKA is excluded.
  test "search_fka surfaces the relevant fixture FKA and excludes the irrelevant one" do
    owner = person(:retired_ranger)
    relevant = person_fka(:retired_relevant_fka)
    person_fka(:retired_irrelevant_fka) # loaded but must not surface

    results = PersonSearch.execute({ query: "Moonbeam", search_fields: "fka" })
    people = people_for(results, PersonSearch::FIELD_FKA)
    ids = people.map(&:id)

    assert_includes ids, owner.id, "the relevant FKA owner must be found"
    matched = people.find { |p| p.id == owner.id }
    assert_equal relevant.fka, matched.fka_match, "fka_match must expose the matched fixture FKA"

    # The irrelevant FKA "Stardust42" must never surface even on a partial soundex/normalized hit.
    stardust = PersonSearch.execute({ query: "Stardust", search_fields: "fka" })
    assert_empty people_for(stardust, PersonSearch::FIELD_FKA),
                 "an is_irrelevant FKA fixture must be excluded from search"
  end

  # --- exclude_statuses type safety ------------------------------------------

  test "message recipient search lists only people who can be messaged" do
    ranger = person(:ranger_with_custom_gender)
    found = -> { PersonSearch.search_callsigns_for_messaging(ranger.callsign, PersonSearch::TYPE_CONTACT).map(&:id) }

    ranger.update!(last_seen_at: nil)
    assert_not_includes found.call, ranger.id

    ranger.update!(last_seen_at: 1.day.ago)
    assert_includes found.call, ranger.id

    ranger.update!(status: Person::SUSPENDED)
    assert_not_includes found.call, ranger.id
  end

  test "exclude_statuses accepts an Array without raising" do
    keep = build_person(callsign: "ExclKeep", first_name: "Keep", last_name: "Mestatus")
    drop = build_person(callsign: "ExclDrop", first_name: "Drop", last_name: "Mestatus",
                        status: Person::DECEASED)

    results = PersonSearch.execute({
      query: "Mestatus",
      search_fields: "name",
      exclude_statuses: [Person::DECEASED]
    })
    ids = people_for(results, PersonSearch::FIELD_NAME).map(&:id)

    assert_includes ids, keep.id
    assert_not_includes ids, drop.id
  end

  test "exclude_statuses accepts a comma-separated String without raising" do
    keep = build_person(callsign: "ExclKeep2", first_name: "Keep", last_name: "Strstatus")
    drop = build_person(callsign: "ExclDrop2", first_name: "Drop", last_name: "Strstatus",
                        status: Person::DECEASED)

    results = PersonSearch.execute({
      query: "Strstatus",
      search_fields: "name",
      exclude_statuses: Person::DECEASED
    })
    ids = people_for(results, PersonSearch::FIELD_NAME).map(&:id)

    assert_includes ids, keep.id
    assert_not_includes ids, drop.id
  end

  # --- +id lookup ------------------------------------------------------------

  test "+id returns the single person in the id group" do
    person = build_person(callsign: "IdLookup", first_name: "Eye", last_name: "Dee")

    results = PersonSearch.execute({ query: "+#{person.id}" })

    assert_equal 1, results.size
    assert_equal PersonSearch::FIELD_ID, results.first[:field]
    assert_equal [person.id], results.first[:people].map(&:id)
  end

  test "+id miss returns an empty result set" do
    assert_equal [], PersonSearch.execute({ query: "+999999999" })
  end

  # --- email gating ----------------------------------------------------------

  test "email search returns results only when can_view_email is true" do
    person = build_person(callsign: "EmailHit", first_name: "Ed", last_name: "Mailer")

    permitted = PersonSearch.execute({ query: person.email }, can_view_email: true)
    assert_includes people_for(permitted).map(&:id), person.id

    denied = PersonSearch.execute({ query: person.email, search_fields: "callsign,name,fka" },
                                  can_view_email: false)
    assert_not_includes people_for(denied).map(&:id), person.id
  end

  # Fixture-anchored old-email match referencing email_history.yml BY NAME. A prior
  # address resolves the owning person only for a viewer who can view email; a
  # non-permitted viewer must get nothing (security negative test).
  test "old-email search resolves the owner for permitted viewers only" do
    owner = person(:retired_ranger)
    old_email = email_history(:retired_old_email).email

    permitted = PersonSearch.execute({ query: old_email }, can_view_email: true)
    ids = people_for(permitted, PersonSearch::FIELD_OLD_EMAIL).map(&:id)
    assert_includes ids, owner.id, "permitted viewer resolves the owner from email history"

    denied = PersonSearch.execute({ query: old_email, search_fields: "callsign,name,fka" },
                                  can_view_email: false)
    assert_not_includes people_for(denied).map(&:id), owner.id,
                        "a non-permitted viewer must not surface email-history matches"
  end

  test "an old email recorded twice finds its owner once, as a Person" do
    old_email = email_history(:retired_old_email)
    EmailHistory.create!(person_id: old_email.person_id, email: old_email.email)

    results = PersonSearch.execute({ query: old_email.email }, can_view_email: true)
    people = people_for(results, PersonSearch::FIELD_OLD_EMAIL)

    # Record equality compares class too, so an EmailHistory row fails this.
    assert_equal [person(:retired_ranger)], people
  end

  test "an email search still honors the caller's excluded statuses" do
    [person(:retired_ranger).email, email_history(:retired_old_email).email].each do |address|
      results = PersonSearch.execute({ query: address, exclude_statuses: [Person::RETIRED] },
                                     can_view_email: true)

      assert_empty people_for(results), "#{address} must not bring back an excluded status"
    end
  end

  # Even when the caller asks for status_groups, an "@" email query must take the FLAT
  # per-field path. search_email/search_old_email ignore the per-group status filter, so
  # routing email through the status-group loop would echo the same person into every
  # category (the bogus all-"1" chip bar). The result must be the flat field shape
  # ({field:, ...}), NOT the grouped shape ({title:, results:}), and the match appears
  # exactly once.
  test "status-grouped email search takes the flat path and never echoes per category" do
    person = person(:active_ranger)

    results = PersonSearch.execute(
      { query: person.email, search_fields: "callsign,name,fka", status_groups: true },
      can_view_email: true
    )

    assert results.any?, "a permitted email search must return the matching person"

    first = results.first
    assert first.key?(:field), "result must be the flat per-field shape (has :field)"
    assert_equal PersonSearch::FIELD_EMAIL, first[:field]
    refute first.key?(:title), "result must NOT be the status-grouped shape (no :title)"
    refute first.key?(:results), "result must NOT be the status-grouped shape (no :results)"

    # The matched person appears exactly once across the whole result set — not echoed
    # into multiple status buckets.
    matched = results.flat_map { |group| group[:people].to_a }.select { |p| p.id == person.id }
    assert_equal 1, matched.size, "the matched person must appear exactly once, not per status group"
  end

  # --- phone search ----------------------------------------------------------

  test "phone: prefix matches the digits anywhere in home or alternate phone" do
    # A home phone kept as typed, as some from before E.164 storage still are.
    home = build_person(callsign: "PhoneHome", first_name: "Hal", last_name: "Home")
    home.update_columns(home_phone: "(201) 555-0142")
    alt = build_person(callsign: "PhoneAlt", first_name: "Al", last_name: "Alt")
    alt.update_columns(alt_phone: "+12015550142")

    ["phone:201-555-0142", "phone:555.0142"].each do |q|
      people = people_for(PersonSearch.execute({ query: q }, can_view_phone: true)).index_by(&:id)

      assert_equal [alt.id, home.id].sort, people.keys.sort, q
      # Each row carries the number that matched, as stored.
      assert_equal "(201) 555-0142", people[home.id].phone_match, q
      assert_equal "+12015550142", people[alt.id].phone_match, q
    end
  end

  test "phone: finds nothing without permission or with fewer than two digits" do
    build_person(callsign: "PhoneGate", first_name: "Gia", last_name: "Gate") # home +17755550101

    assert_equal [], PersonSearch.execute({ query: "phone:7755550101" })
    # These strip to "" and "7": LIKE '%%' / '%7%' would match nearly everyone.
    assert_equal [], PersonSearch.execute({ query: "phone:abc" }, can_view_phone: true)
    assert_equal [], PersonSearch.execute({ query: "phone:7" }, can_view_phone: true)
  end
end
