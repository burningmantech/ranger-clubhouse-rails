# frozen_string_literal: true

require "test_helper"

class Autocomplete::PersonAdapterTest < ActiveSupport::TestCase
  setup do
    @person = person(:active_ranger)
    Current.person = @person
    Current.roles_manager = RoleManager.retrieve(@person)
  end

  test "returns empty response for blank results" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "zzzzzzzzzzz_no_match",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert_equal [], result[:items]
    assert_equal [], result[:groups]
    assert_equal [], result[:flat_item_ids]
  end

  test "returns items with required fields" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    # active_ranger (callsign "TestRanger") deterministically matches, so this is
    # unconditional — not gated on a vacuous `if result[:items].any?`.
    assert result[:items].any?, "TestRanger must match the active_ranger fixture"
    item = result[:items].first
    assert item[:id].present?
    assert item[:value].present?
    assert item[:label].present?
    assert item[:html].present?
    assert item[:meta].is_a?(Hash)
  end

  test "person result items link to the person manage page" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert result[:items].any?, "TestRanger must match the active_ranger fixture"
    item = result[:items].first
    assert_equal Rails.application.routes.url_helpers.person_path(item[:meta][:id]), item[:url]
  end

  test "items contain person metadata" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert result[:items].any?, "TestRanger must match the active_ranger fixture"
    meta = result[:items].first[:meta]
    assert meta[:id].present?
    assert meta[:status].present?
    assert meta[:callsign].present?
  end

  test "hq mode restricts to callsign search across HQ statuses" do
    # The hq adapter branch is dormant (the controller short-circuits mode=hq), but
    # the branch itself must search callsign-only across HQ_STATUSES with no status
    # grouping. active_ranger ("TestRanger", active) is within HQ_STATUSES, so it is
    # found and lands in a single "callsign" group with no filter chips.
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "hq",
      limit: 5
    )

    result = adapter.search

    assert result[:items].any?, "an active callsign must match under HQ_STATUSES"
    assert_equal ["callsign"], result[:groups].map { |g| g[:key] }.uniq,
                 "hq mode searches the callsign field only"
    assert_equal [], result[:filters], "hq mode produces no status-group filter chips"
    assert_includes result[:items].map { |i| i[:meta][:callsign] }, "TestRanger"
  end

  test "hq mode excludes statuses outside HQ_STATUSES" do
    # retired_ranger (callsign "RetiredRanger") is RETIRED, which is NOT in HQ_STATUSES,
    # so an hq callsign search must not return it.
    adapter = Autocomplete::PersonAdapter.new(
      query: "RetiredRanger",
      mode: "hq",
      limit: 5
    )

    result = adapter.search

    assert_empty result[:items], "a retired person is outside HQ_STATUSES"
  end

  test "person_manage mode uses status groups" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    # person_manage should use status_groups which may produce filters
    assert result.key?(:filters)
    assert result.key?(:groups)
  end

  test "item ids are strings" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert result[:items].any?, "TestRanger must match the active_ranger fixture"
    result[:items].each do |item|
      assert item[:id].is_a?(String)
      assert item[:value].is_a?(String)
    end
  end

  test "item html contains person information" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert result[:items].any?, "TestRanger must match the active_ranger fixture"
    html = result[:items].first[:html]
    assert_includes html, "TestRanger"
  end

  test "flat_item_ids matches items" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search
    item_ids = result[:items].map { |i| i[:id] }

    assert result[:flat_item_ids].any?, "TestRanger must produce at least one flat id"
    assert_equal item_ids.sort, result[:flat_item_ids].sort,
                 "flat_item_ids must be exactly the union of item ids"
    result[:flat_item_ids].each do |id|
      assert_includes item_ids, id
    end
  end

  test "filtered person_manage still includes status_group filter definition" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25,
      filters: { "status_group" => "active_current" }
    )

    result = adapter.search

    assert result[:filters].is_a?(Array)
    assert result[:filters].length > 0, "filtered response must still include filter model"
    filter = result[:filters].first
    assert_equal "status_group", filter[:key]
    assert_equal false, filter[:multi]

    # Exactly one option should be active
    active_options = filter[:options].select { |o| o[:active] }
    assert_equal 1, active_options.length, "exactly one filter option should be active"
    assert_equal "active_current", active_options.first[:value]
  end

  test "non-hash filters do not crash adapter" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 5,
      filters: ["x"]
    )

    # Should not raise TypeError
    result = adapter.search
    assert result.is_a?(Hash)
    assert result.key?(:items)
  end

  test "unfiltered person_manage marks first filter option as active by default" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    # A grouped person_manage response always carries the status_group filter model,
    # so this is unconditional (was a vacuous `if result[:filters].any?`).
    assert result[:filters].any?, "grouped person_manage response must carry the filter model"
    filter = result[:filters].first
    active_options = filter[:options].select { |o| o[:active] }
    assert_equal 1, active_options.length, "exactly one default filter option should be active"
  end

  test "single status category sets the showing-results banner" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    # active_ranger is the only TestRanger and is Active/Current -> one category.
    assert_match(/\AShowing results for .* status\(es\)\z/, result[:banner])
  end

  test "unfiltered search shows only the first status category and chips for the rest" do
    # Several "*Ranger" fixtures share the last name "Ranger" across distinct statuses:
    #   active_ranger (active) + inactive_ranger (inactive) -> Active/Current
    #   deceased fixtures (deceased)                        -> Deceased
    #   retired_ranger (retired)                            -> Resigned/Retired
    # Only ONE status category is shown at a time. With no chip selected, the default
    # (first non-empty) category — Active/Current — is shown; the other categories
    # appear only as chips and contribute their counts, not their rows.
    adapter = Autocomplete::PersonAdapter.new(
      query: "Ranger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    # Exactly one group is rendered, and it is the default Active/Current category.
    assert_equal ["active_current"], result[:groups].map { |g| g[:key] }
    shown_callsigns = result[:items].map { |i| i[:meta][:callsign] }
    assert_includes shown_callsigns, "TestRanger"
    assert_includes shown_callsigns, "InactiveRanger"

    # Other categories' people are NOT in the shown results...
    assert_not_includes shown_callsigns, "DeceasedRanger", "only the active category's rows are shown"
    assert_not_includes shown_callsigns, "RetiredRanger", "only the active category's rows are shown"

    # ...but they DO appear as chips with positive counts, and Active/Current is active.
    options = result[:filters].first[:options]
    keyed = options.index_by { |o| o[:value] }
    assert keyed["deceased"][:count].positive?, "Deceased chip must carry its real count"
    assert keyed["resigned_retired"][:count].positive?, "Resigned/Retired chip must carry its real count"
    assert keyed["active_current"][:active], "the shown category's chip is the active one"
    assert_equal 1, options.count { |o| o[:active] }, "exactly one chip is active"
  end

  test "field-tag search is grouped into status categories with counted chips" do
    # Regression: a field-tag prefix ("last:Ranger") must behave like the default
    # search — bucket matches into status categories, show ONE category, and give the
    # chips real counts. It previously fell to the flat path, rendering every status
    # chip with no count and never grouping rows by status. "last:Ranger" matches four
    # fixtures across three groups: active + inactive (Active/Current), deceased
    # (Deceased), retired (Resigned/Retired).
    adapter = Autocomplete::PersonAdapter.new(
      query: "last:Ranger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    # One status group is shown (default Active/Current), not a flat field group.
    assert_equal ["active_current"], result[:groups].map { |g| g[:key] }
    shown_callsigns = result[:items].map { |i| i[:meta][:callsign] }
    assert_includes shown_callsigns, "TestRanger"
    assert_includes shown_callsigns, "InactiveRanger"
    assert_not_includes shown_callsigns, "DeceasedRanger", "only the active category's rows are shown"

    # Every chip carries a positive count (the bug showed all chips with none) and
    # zero-match categories are dropped.
    options = result[:filters].first[:options]
    assert options.all? { |o| o[:count].to_i.positive? }, "every chip must carry a positive count"
    keyed = options.index_by { |o| o[:value] }
    assert keyed["deceased"][:count].positive?, "Deceased chip must carry its real count"
    assert keyed["resigned_retired"][:count].positive?, "Resigned/Retired chip must carry its real count"
    assert keyed["active_current"][:active], "the shown category's chip is active"
    assert_equal 1, options.count { |o| o[:active] }, "exactly one chip is active"
  end

  test "status_group filter restricts results to the selected category only" do
    # Filtering to "deceased" must return ONLY deceased people, no Active/Current.
    adapter = Autocomplete::PersonAdapter.new(
      query: "Ranger",
      mode: "person_manage",
      limit: 25,
      filters: { "status_group" => "deceased" }
    )

    result = adapter.search
    statuses = result[:items].map { |i| i[:meta][:status] }.uniq

    assert_includes result[:items].map { |i| i[:meta][:callsign] }, "DeceasedRanger"
    assert_equal [Person::DECEASED], statuses,
                 "a status_group filter must restrict results to that category's statuses"
    assert_not_includes result[:items].map { |i| i[:meta][:callsign] }, "TestRanger"
  end

  test "blank results carry the context-specific empty_text" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "zzzzzzzzzzz_no_match",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert_equal "No people were found matching callsign, name, or FKA", result[:empty_text]
  end

  test "email empty_text reflects permission when email cannot be viewed" do
    # active_ranger has no roles in the test DB -> cannot view email.
    assert_not Current.can_view_email?

    adapter = Autocomplete::PersonAdapter.new(
      query: "no one@example.com",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert_equal "You do not have permission to search by email", result[:empty_text]
    # An email query is status-agnostic, so no status chip bar is emitted even on the
    # no-permission/empty path.
    assert_equal [], result[:filters], "an email search must never carry status chips"
  end

  test "field-tag empty_text names the searched field" do
    adapter = Autocomplete::PersonAdapter.new(
      query: "last:zzzznomatch",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search

    assert_equal "No people matched that last name", result[:empty_text]
  end

  test "fka search renders the matched fka in the item html" do
    # active_ranger gains an FKA so the fka group renders a matched-FKA line.
    @person.person_fka.create!(fka: "Glitterhoof")

    adapter = Autocomplete::PersonAdapter.new(
      query: "fka:Glitterhoof",
      mode: "person_manage",
      limit: 5
    )

    result = adapter.search
    html = result[:items].map { |i| i[:html] }.join

    assert_includes html, "FKA: Glitterhoof"
    # Name line is rendered for the fka group too (status + name).
    assert_includes html, @person.last_name
  end

  test "status-group filter chips omit categories with zero matches" do
    # "TestRanger" matches only active_ranger (Active/Current), so the chip bar must
    # contain just that category and no zero-count chips for the empty categories.
    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    options = result[:filters].first[:options]
    assert options.all? { |o| o[:count].to_i.positive? }, "no zero-count chip may be shown"
    assert_equal ["active_current"], options.map { |o| o[:value] }
  end

  test "a person matching multiple fields collapses to one row carrying the FKA" do
    # active_ranger matches the callsign field ("TestRanger") and also gains an FKA
    # the same query hits, so callsign + fka both match. The adapter must return ONE
    # item for this person, with the matched FKA merged onto the surviving row.
    @person.person_fka.create!(fka: "TestRangerLegacy")

    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    matches = result[:items].select { |i| i[:meta][:callsign] == "TestRanger" }
    assert_equal 1, matches.length, "callsign + fka match must collapse to a single row"

    # The surviving row keeps the higher-priority callsign identity, and the matched
    # FKA is merged onto it.
    assert_equal "p#{@person.id}_callsign", matches.first[:id]
    assert_includes matches.first[:html], "FKA: TestRangerLegacy"

    # No dangling id for the dropped fka duplicate; flat_item_ids stays consistent.
    refute_includes result[:flat_item_ids], "p#{@person.id}_fka"
    assert_equal result[:items].map { |i| i[:id] }.sort, result[:flat_item_ids].sort
  end

  test "an active status_group filter still dedups multi-field matches and keeps real-count chips" do
    # A status_group filter must route through the grouped (deduping) search, not a
    # flat per-field search. Previously the filtered path returned the callsign and
    # fka matches as two rows and a full no-count chip bar. active_ranger matches the
    # callsign and an FKA on the same query, so the filtered Active/Current response
    # must collapse to ONE row and the chip bar must carry only non-zero counts.
    @person.person_fka.create!(fka: "TestRangerLegacy")

    adapter = Autocomplete::PersonAdapter.new(
      query: "TestRanger",
      mode: "person_manage",
      limit: 25,
      filters: { "status_group" => "active_current" }
    )

    result = adapter.search

    matches = result[:items].select { |i| i[:meta][:callsign] == "TestRanger" }
    assert_equal 1, matches.length, "a filtered response must still collapse callsign + fka to one row"
    assert_includes matches.first[:html], "FKA: TestRangerLegacy"

    # Only the selected category's rows are emitted.
    assert_equal [Person::ACTIVE], result[:items].map { |i| i[:meta][:status] }.uniq

    # Chip bar carries real counts and drops zero-match categories even when filtered.
    options = result[:filters].first[:options]
    assert options.all? { |o| o[:count].to_i.positive? }, "filtered chip bar must not show zero-count chips"
    assert(options.find { |o| o[:value] == "active_current" }[:active], "the filtered category chip is active")
  end

  test "a permitted email search returns no status chips and one row" do
    grant_view_role(@person, Role::VIEW_EMAIL, "View Email")
    target = person(:active_ranger)

    adapter = Autocomplete::PersonAdapter.new(
      query: target.email,
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    # An email query is status-agnostic: a flat Email list, no chip bar.
    assert_equal [], result[:filters], "an email search must never carry status chips"
    assert result[:items].any?, "a permitted email search must return the matching person"
    assert_not_equal "Multiple status categories found", result[:banner],
                     "an email search must not render the multi-category banner"

    matched = result[:items].select { |i| i[:meta][:id] == target.id }
    assert_equal 1, matched.size, "the matched person must appear exactly once"
  end

  test "a permitted old-email search returns no status chips and one row" do
    grant_view_role(@person, Role::VIEW_EMAIL, "View Email")
    owner = person(:retired_ranger)
    old_email = email_history(:retired_old_email).email

    adapter = Autocomplete::PersonAdapter.new(
      query: old_email,
      mode: "person_manage",
      limit: 25
    )

    result = adapter.search

    assert_equal [], result[:filters], "an old-email search must never carry status chips"
    assert result[:items].any?, "a permitted old-email search must resolve the owner"
    assert_not_equal "Multiple status categories found", result[:banner],
                     "an old-email search must not render the multi-category banner"

    matched = result[:items].select { |i| i[:meta][:id] == owner.id }
    assert_equal 1, matched.size, "the matched person must appear exactly once"
  end

  test "phone search shows the number that matched" do
    grant_view_role(@person, Role::VIEW_PII, "View PII")
    @person.update_columns(alt_phone: "+12015550142")

    result = Autocomplete::PersonAdapter.new(query: "phone:+1-201-555-0142", mode: "person_manage").search

    assert_includes result[:items].map { |i| i[:html] }.join, "Phone: (201) 555-0142"
  end

  test "phone empty_text reflects permission when phones cannot be viewed" do
    # active_ranger has no roles in the test DB -> cannot view PII.
    assert_not Current.can_view_pii?

    result = Autocomplete::PersonAdapter.new(query: "phone:+1-201-555-0142", mode: "person_manage").search

    assert_equal "You do not have permission to search by phone number", result[:empty_text]
  end

  private

  # Grant a role to a person and rebuild Current.roles_manager so the adapter's
  # Current.can_view_email? / can_view_pii? gates see it. Mirrors the role-grant
  # pattern in test/controllers/person_controller_test.rb.
  def grant_view_role(person, role_id, title)
    role = Role.find_or_initialize_by(id: role_id)
    role.title = title
    role.new_user_eligible = false
    role.save!

    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
    Current.roles_manager = RoleManager.retrieve(person)
  end
end
