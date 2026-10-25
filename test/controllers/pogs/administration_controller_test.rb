# frozen_string_literal: true

require "test_helper"

class Pogs::AdministrationControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include EscapedMarkupTestHelper
  include PersonTestFactory
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @pog_manager = person(:echelon_ranger)
    # The realistic wrong role: it owns Person › Pogs and the HQ pog flow.
    @event_manager = person(:auditor_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::POG_MANAGEMENT, "Pog Management")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@admin, Role::ADMIN)
    grant_role(@pog_manager, Role::POG_MANAGEMENT)
    grant_role(@event_manager, Role::EVENT_MANAGEMENT)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  test "admin and pog management may view the page" do
    [@admin, @pog_manager].each do |viewer|
      sign_in_as(viewer)
      get pogs_administration_path
      assert_response :success, "#{viewer.callsign} should be allowed in"
    end
  end

  test "event management alone is turned away" do
    sign_in_as(@event_manager)
    get pogs_administration_path

    assert_redirected_to me_root_path
    assert_equal "Admin or Pog Management role required to administer pog records.", flash[:error]
  end

  # A pog belongs to the year it was issued in, not the year its row was written.
  test "a year holds the pogs issued in it" do
    pog = PersonPog.create!(person: @event_manager, issued_by: @admin, pog: PersonPog::POG_MEAL,
                            issued_at: Time.local(2025, 8, 27, 12))
    pog.update_column(:created_at, Time.local(2026, 1, 5, 12))
    sign_in_as(@pog_manager)

    get pogs_administration_path(year: 2025)
    assert_response :success
    assert_select ".empty-state", count: 0

    get pogs_administration_path(year: 2026)
    assert_select ".empty-state", text: "No pogs were issued in 2026."
  end

  test "each filter narrows the year's pogs, and they combine" do
    seed_three_pogs

    # Newest first: pog-c was issued an hour after pog-b, a day after pog-a.
    { { person_callsign: @event_manager.callsign } => %w[pog-c pog-a],
      { issued_by_id: @pog_manager.id } => %w[pog-c pog-b],
      { day: "2025-08-28" } => %w[pog-c pog-b],
      { pog: PersonPog::POG_SHOWER } => %w[pog-b],
      { status: PogFilterForm::STATUS_ISSUED } => %w[pog-b pog-a],
      { status: PogFilterForm::STATUS_CANCELLED } => %w[pog-c],
      { issued_by_id: @pog_manager.id, day: "2025-08-28", pog: PersonPog::POG_MEAL } => %w[pog-c] }
      .each do |filter, expected|
        get pogs_administration_path(year: 2025, filter:)
        assert_equal expected, listed_notes, filter.inspect
      end
  end

  # Dropping the filter would quietly list everyone's pogs under a chip naming one person.
  test "a callsign no one holds lists nothing and keeps its chip" do
    seed_three_pogs

    get pogs_administration_path(year: 2025, filter: { person_callsign: "NoSuchRanger" })

    assert_empty listed_notes
    assert_select ".empty-state", text: "No pogs match the current filters."
    assert_select "a[aria-label=?]", "Remove filter: Recipient: NoSuchRanger"
  end

  # "all" is the selects' sentinel, but typed as a callsign it is a callsign:
  # it filters, so it must show, and ride along with the year.
  test "a callsign of all is a filter like any other" do
    seed_three_pogs

    get pogs_administration_path(year: 2025, filter: { person_callsign: "all" })

    assert_empty listed_notes
    assert_select "a[aria-label=?]", "Remove filter: Recipient: all"
    assert_select "input[type=hidden][name=?][value=?]", "filter[person_callsign]", "all", minimum: 1
  end

  # Person.find_id_by_callsign would pick one of the two at random.
  test "a callsign finds its holder, never another whose callsign reads alike" do
    hyphen = create_person("Fire-Fly", email: "fire-fly@example.com")
    space = create_person("Fire Fly", email: "fire-fly-2@example.com")
    PersonPog.create!(person: hyphen, issued_by: @admin, pog: PersonPog::POG_MEAL, notes: "hyphen",
                      issued_at: Time.local(2025, 8, 27, 12))
    PersonPog.create!(person: space, issued_by: @admin, pog: PersonPog::POG_MEAL, notes: "space",
                      issued_at: Time.local(2025, 8, 27, 13))
    sign_in_as(@pog_manager)

    { "Fire Fly" => %w[space], "fire-fly" => %w[hyphen], "firefly" => %w[space hyphen] }.each do |callsign, expected|
      get pogs_administration_path(year: 2025, filter: { person_callsign: callsign })
      assert_equal expected, listed_notes, callsign
    end
  end

  test "a value the year does not hold filters nothing and draws no chip" do
    seed_three_pogs

    get pogs_administration_path(year: 2025, filter: { issued_by_id: 999_999, day: "2025-13-45",
                                                       pog: PersonPog::POG_HALF_MEAL, status: "bogus" })

    assert_equal %w[pog-a pog-b pog-c], listed_notes.sort
    assert_select "a[aria-label^='Remove filter']", count: 0
  end

  # A choice that can only come back empty is not offered.
  test "the type and status selects offer only what the year holds" do
    seed_three_pogs

    get pogs_administration_path(year: 2025)

    assert_equal %w[all meal shower], option_values("filter[pog]")
    assert_equal %w[all issued cancelled], option_values("filter[status]")
  end

  # Its person row is gone, but its pogs are not: the select must still hold it,
  # or the next Apply would drop the filter.
  test "an issuer whose person row is gone keeps an option" do
    seed_three_pogs
    PersonPog.insert_all([{ person_id: @admin.id, issued_by_id: 999_999, pog: PersonPog::POG_MEAL,
                            status: PersonPog::STATUS_ISSUED, notes: "pog-d", issued_at: Time.local(2025, 8, 29, 12) }])

    get pogs_administration_path(year: 2025, filter: { issued_by_id: 999_999 })

    assert_equal %w[pog-d], listed_notes
    assert_select "select[name='filter[issued_by_id]'] option[value='999999'][selected]", text: "Deleted #999999"
  end

  test "the year selector carries the filters" do
    seed_three_pogs

    get pogs_administration_path(year: 2025, filter: { pog: PersonPog::POG_SHOWER })

    # Only the year selector's forms carry it hidden; the filter bar shows it as a select.
    assert_select "input[type=hidden][name=?][value=?]", "filter[pog]", PersonPog::POG_SHOWER, minimum: 1
  end

  # The pager is where an unfiltered list's total reads.
  test "a single page still shows the pager and its total" do
    seed_three_pogs

    get pogs_administration_path(year: 2025)

    assert_select "p", text: "Page 1 of 1 · 3 pogs", minimum: 1
  end

  test "a page holds a hundred pogs, newest first" do
    PersonPog.insert_all((1..101).map do |minute|
      { person_id: @event_manager.id, issued_by_id: @admin.id, pog: PersonPog::POG_MEAL,
        status: PersonPog::STATUS_ISSUED, notes: "n#{minute}", issued_at: Time.local(2025, 8, 27, 10) + minute.minutes }
    end)
    sign_in_as(@pog_manager)

    get pogs_administration_path(year: 2025)
    assert_equal 100, listed_notes.size
    assert_equal "n101", listed_notes.first

    get pogs_administration_path(year: 2025, filter: { page: 2 })
    assert_equal ["n1"], listed_notes
  end

  # Delete lives on the edit page: a confirmation per row is a dialog per row.
  test "the list offers edit only, and the edit page's delete is marked destructive" do
    seed_three_pogs
    pog = PersonPog.find_by!(notes: "pog-b")

    get pogs_administration_path(year: 2025)
    assert_select "main a[data-turbo-method=delete]", count: 0
    assert_no_escaped_markup

    get pogs_edit_record_path(pog, year: 2025)
    dialog = Nokogiri::HTML5.fragment(css_select("main a[data-turbo-method=delete]").sole["data-turbo-confirm"])
    confirm = dialog.at_css("#turbo-confirm-button")
    assert_equal "Delete Pog", confirm.text.strip
    assert_includes confirm["class"], "btn-error"
    assert_includes dialog.text, "issued to #{@admin.callsign} on #{pog.issued_at.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)}?"
  end

  test "an edit saves, is audited, and returns to the same page of the same list" do
    seed_three_pogs
    pog = PersonPog.find_by!(notes: "pog-b")
    back = { year: 2025, filter: { pog: PersonPog::POG_SHOWER } }

    get pogs_administration_path(back)
    assert_select "a[href=?]", pogs_edit_record_path(pog, back)

    get pogs_edit_record_path(pog, back)
    assert_select "form[action=?]", pogs_record_path(pog, back)
    # The time renders as datetime_format's span, tooltip and all, never as its markup.
    assert_includes css_select("main").sole.text.squish,
                    "Issued #{pog.issued_at.strftime(DateTimeHelper::MONTH_DAY_TIME_YEAR)} by #{@pog_manager.callsign}."
    assert_no_escaped_markup

    assert_difference -> { ActionLog.where(event: "person-pog-update").count } do
      patch pogs_record_path(pog, back),
            params: { person_pog: { pog: PersonPog::POG_MEAL, status: PersonPog::STATUS_CANCELLED,
                                    notes: "Issued by mistake" } }
    end
    assert_redirected_to pogs_administration_path(back)
    assert_equal [PersonPog::POG_MEAL, PersonPog::STATUS_CANCELLED, "Issued by mistake"],
                 pog.reload.attributes.values_at("pog", "status", "notes")
  end

  test "a status the model refuses re-renders the form" do
    seed_three_pogs
    pog = PersonPog.find_by!(notes: "pog-a")

    patch pogs_record_path(pog, year: 2025), params: { person_pog: { status: "bogus" } }

    assert_response :unprocessable_entity
    assert_equal PersonPog::STATUS_ISSUED, pog.reload.status
  end

  test "a delete removes the pog, is audited, and returns to the same list" do
    seed_three_pogs
    pog = PersonPog.find_by!(notes: "pog-c")
    back = { year: 2025, filter: { issued_by_id: @pog_manager.id.to_s } }

    assert_difference -> { ActionLog.where(event: "person-pog-delete").count } do
      delete pogs_record_path(pog, back)
    end
    assert_redirected_to pogs_administration_path(back)
    assert_not PersonPog.exists?(pog.id)
  end

  test "event management may neither change nor delete a pog" do
    seed_three_pogs
    pog = PersonPog.find_by!(notes: "pog-a")
    sign_in_as(@event_manager)

    patch pogs_record_path(pog, year: 2025), params: { person_pog: { notes: "changed" } }
    assert_redirected_to me_root_path
    delete pogs_record_path(pog, year: 2025)
    assert_redirected_to me_root_path
    assert_equal "pog-a", pog.reload.notes
  end

  private

  # Notes name each pog, so a test can read which rows the list holds. Time.local:
  # the Day filter reads the date as stored, on the process's clock, so these
  # land on the same day whatever zone the machine runs in.
  def seed_three_pogs
    PersonPog.create!(person: @event_manager, issued_by: @admin, pog: PersonPog::POG_MEAL,
                      notes: "pog-a", issued_at: Time.local(2025, 8, 27, 12))
    PersonPog.create!(person: @admin, issued_by: @pog_manager, pog: PersonPog::POG_SHOWER,
                      notes: "pog-b", issued_at: Time.local(2025, 8, 28, 12))
    PersonPog.create!(person: @event_manager, issued_by: @pog_manager, pog: PersonPog::POG_MEAL,
                      status: PersonPog::STATUS_CANCELLED, notes: "pog-c",
                      issued_at: Time.local(2025, 8, 28, 13))
    sign_in_as(@pog_manager)
  end

  def listed_notes
    css_select("td[data-label=Notes]").map { |cell| cell.text.strip }
  end

  def option_values(name)
    css_select("select[name='#{name}'] option").map { |option| option["value"] }
  end
end
