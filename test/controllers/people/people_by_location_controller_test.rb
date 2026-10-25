# frozen_string_literal: true

require "test_helper"

class People::PeopleByLocationControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  # A year the timesheet and slot fixtures leave alone.
  YEAR = 2022

  setup do
    Rails.cache.clear
    Current.reset

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TRAINER, "Trainer")
    ensure_role(Role::VC, "VC")
    ensure_role(Role::MENTOR, "Mentor")

    @admin = person(:active_ranger)
    @trainer = person(:echelon_ranger)
    @vc = person(:auditor_ranger)
    @outsider = person(:inactive_ranger)
    @mentor = person(:bonked_ranger)
    grant_role(@admin, Role::ADMIN)
    grant_role(@trainer, Role::TRAINER)
    grant_role(@vc, Role::VC)
    grant_role(@mentor, Role::MENTOR)

    # Two countries: one that breaks down into states, one that does not.
    @admin.update!(country: "US", state: "NV", city: "Gerlach", zip: "89412")
    @trainer.update!(country: "US", state: "CA", city: "Oakland", zip: "94601")
    @vc.update!(country: "DE", state: "", city: "Berlin", zip: "10115")
    # This fixture is an auditor, and the report hides that status. It stands
    # in for the country with no states, so it has to be someone shown.
    @vc.update_column(:status, Person::ACTIVE)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def add_timesheet(subject)
    Timesheet.create!(person: subject, position: positions(:ood_position),
                      on_duty: Time.zone.local(YEAR, 8, 20, 9, 0),
                      off_duty: Time.zone.local(YEAR, 8, 20, 11, 0),
                      additional_notes: "test entry")
  end

  # ---------------------------------------------------------------- access

  test "a reader with none of the four roles is turned away" do
    sign_in_as(@outsider)
    get people_by_location_path

    assert_redirected_to me_root_path
  end

  test "a trainer reaches the report" do
    sign_in_as(@trainer)
    get people_by_location_path

    assert_response :success
  end

  # The menu advertises this page to mentors, so the gate has to admit them.
  test "a mentor reaches the report" do
    sign_in_as(@mentor)
    get people_by_location_path

    assert_response :success
  end

  # ----------------------------------------------------------------- index

  test "the index lists the countries people live in" do
    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_select "a", text: /United States/
    assert_select "a", text: /Germany/
  end

  test "the index links each country to its own page, keeping the filters" do
    # The filter has to leave somebody standing, or there are no country rows
    # to carry it.
    add_timesheet(@admin)

    get people_by_location_path(year: YEAR, participation: PeopleByLocationReport::EITHER)

    assert_response :success
    assert_select "a[href*='#{people_by_location_country_path("US")}']" do |links|
      assert links.any? { |link| link["href"].include?("year=#{YEAR}") },
             "the country link should carry the year"
      assert links.any? { |link| link["href"].include?("participation=either") },
             "the country link should carry the filter"
    end
  end

  # Both headings render for almost any partition rule, so the test has to say
  # which countries landed under which, and in what order.
  test "the index sorts the four common countries into their own group" do
    get people_by_location_path(year: YEAR)

    assert_response :success
    body = response.body
    common = body.index("Common Countries")
    other = body.index("Everywhere Else")

    assert common && other, "both group headings should render"
    assert_operator common, :<, other, "the common countries should come first"
    assert_operator body.index("United States"), :<, other,
                    "the United States belongs to the common group"
    assert_operator other, :<, body.index("Germany"),
                    "Germany belongs to the everywhere-else group"
  end

  # Byte order files every accented name after Zimbabwe.
  test "countries sort by name with accents folded in" do
    @vc.update!(country: "AX")       # Åland Islands
    @outsider.update!(country: "ZW") # Zimbabwe

    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_operator response.body.index("Åland Islands"), :<,
                    response.body.index("Zimbabwe"),
                    "an accented name should sort by its letter, not after Z"
  end

  # A filter can empty either group, and a heading with nothing under it reads
  # as a country list that failed to load.
  test "a group with no one in it drops its heading too" do
    Person.update_all(country: "US")

    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_select "[role=heading]", text: "Common Countries"
    assert_select "[role=heading]", text: "Everywhere Else", count: 0
  end

  # --------------------------------------------------------------- country

  test "a country with states on file lists its states first" do
    get people_by_location_country_path("US", year: YEAR)

    assert_response :success
    assert_select "a", text: /Nevada/
    assert_select "a", text: /California/
    # Still the state list, not the people.
    assert_select "table", false
  end

  # Sorted by label it would sit between South Dakota and Tennessee, reading as
  # one more state.
  test "the people with no state on file sort after the real states" do
    @vc.update!(country: "US", state: "NV", city: "Reno", zip: "89501")
    # A US record needs a state to validate, so the blank goes in behind it.
    @vc.update_column(:state, "")

    get people_by_location_country_path("US", year: YEAR)

    assert_response :success
    assert_operator response.body.index("Nevada"), :<,
                    response.body.index("State not on file")
  end

  test "picking a state lists that state's people only" do
    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "table"
    assert_select "td,th", text: @admin.callsign
    assert_select "td,th", text: @trainer.callsign, count: 0
  end

  test "a country with no state breakdown goes straight to its people" do
    get people_by_location_country_path("DE", year: YEAR)

    assert_response :success
    assert_select "table"
    assert_select "td,th", text: @vc.callsign
  end

  test "a country no one lives in says so rather than failing" do
    get people_by_location_country_path("ZZ", year: YEAR)

    assert_response :success
    # Nothing was filtered, so the page must not blame a filter.
    assert_select "body", text: /No one has an address/
    assert_select "body", text: /matches these filters/, count: 0
  end

  test "an empty page blames the filters only when there are filters" do
    get people_by_location_country_path("US", state: "NV", year: YEAR,
                                        participation: PeopleByLocationReport::RANGERED)

    assert_response :success
    assert_select "body", text: /matches these filters/
  end

  # The state list is a stop on the way to the people, and a reader who wants
  # the whole country should not have to visit fifty states to assemble it.
  test "a country listing its states can still be exported whole" do
    get people_by_location_country_path("US", year: YEAR,
                                        participation: PeopleByLocationReport::EITHER)

    assert_response :success
    assert_select "a[href*='#{people_by_location_country_path("US", format: :csv)}']" do |links|
      assert links.any? { |link| link["href"].include?("participation=either") },
             "the country export should carry the filters"
      assert links.none? { |link| link["href"].include?("state=") },
             "the country export should not be pinned to a state"
    end
  end

  test "the people with no state on file export under their own name" do
    @admin.update_column(:state, "")

    get people_by_location_country_path("US", state: PeopleByLocationReport::NO_STATE,
                                        year: YEAR, format: :csv)

    assert_response :success
    assert_match "2022-people-by-location-us-no-state.csv",
                 response.headers["Content-Disposition"]
  end

  test "a country with no state on file anywhere gets no state column" do
    get people_by_location_country_path("DE", year: YEAR)

    assert_response :success
    assert_select "th", text: "State", count: 0
  end

  test "a country where some people do have a region shows it" do
    @vc.update!(state: "Bavaria")

    get people_by_location_country_path("DE", year: YEAR)

    assert_response :success
    assert_select "th", text: "State"
    assert_select "td", text: "Bavaria"
  end

  # The year selector submits a bare GET of its own, so anything not restated as
  # a hidden field is dropped the moment the reader changes year.
  test "changing the year keeps the state and every filter" do
    get people_by_location_country_path("US", state: "NV", year: YEAR,
                                        participation: PeopleByLocationReport::EITHER,
                                        statuses: [Person::RETIRED, Person::DECEASED])

    assert_response :success
    assert_select "form:has(select[name=year])" do
      assert_select "input[type=hidden][name=state][value=NV]"
      assert_select "input[type=hidden][name=participation][value=either]"
      # One field per status, named as a list -- a single field holding both
      # would arrive as the string an array prints as.
      assert_select "input[type=hidden][name='statuses[]'][value=retired]"
      assert_select "input[type=hidden][name='statuses[]'][value=deceased]"
    end
  end

  # ------------------------------------------------------------------ email

  test "a reader allowed to see addresses gets the email column" do
    sign_in_as(@vc)
    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "th", text: "Email"
  end

  test "a reader not allowed to see addresses gets no email column" do
    sign_in_as(@trainer)
    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "th", text: "Email", count: 0
    assert_select "body", text: /#{Regexp.escape(@admin.email)}/, count: 0
  end

  # ------------------------------------------------------------------- CSV

  test "the export carries the filtered rows and names the slice" do
    get people_by_location_country_path("US", state: "NV", year: YEAR, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "2022-people-by-location-us-nv.csv", response.headers["Content-Disposition"]

    lines = response.body.split("\n")
    assert_match(/\ACallsign,First Name,Last Name,Email,Status/, lines.first)
    assert lines.any? { |line| line.start_with?("#{@admin.callsign},") },
           "the Nevada export should hold the Nevada person"
    assert lines.none? { |line| line.start_with?("#{@trainer.callsign},") },
           "the Nevada export should not hold the California person"
  end

  test "the export leaves out email for a reader who may not see it" do
    sign_in_as(@trainer)
    get people_by_location_path(year: YEAR, format: :csv)

    assert_response :success
    assert_match(/\ACallsign,First Name,Last Name,Status/, response.body.split("\n").first)
    assert_no_match(/#{Regexp.escape(@admin.email)}/, response.body)
  end

  # ------------------------------------------------------- status advisory

  # The counts leave out a good part of the roster by default, so the page has
  # to say so where it is read, not only inside the collapsed filter panel.
  # Statuses are named exactly as a record spells them -- lower case.
  test "the page names every status it is leaving out" do
    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_select "body", text: /#{hidden_count} statuses hidden/
    named = Regexp.escape(PeopleByLocationReport::OPTIONAL_STATUSES.to_sentence)
    assert_select "body", text: /#{named} are left out/
  end

  test "the advisory separates what is hidden from what was added back" do
    get people_by_location_path(year: YEAR, statuses: [Person::RETIRED])

    assert_response :success
    assert_select "body", text: /#{hidden_count - 1} statuses hidden/
    assert_select "body", text: /retired is included/
  end

  test "the advisory says so when nothing is left out" do
    get people_by_location_path(year: YEAR,
                                statuses: PeopleByLocationReport::OPTIONAL_STATUSES)

    assert_response :success
    assert_select "body", text: /Every status is included/
    assert_select "body", text: /statuses hidden/, count: 0
  end

  test "the advisory rides along on a country page too" do
    get people_by_location_country_path("US", year: YEAR)

    assert_response :success
    assert_select "body", text: /#{hidden_count} statuses hidden/
  end

  def hidden_count = PeopleByLocationReport::OPTIONAL_STATUSES.size

  # --------------------------------------------------------------- filters

  test "a hidden status stays out of the report until it is asked for" do
    @outsider.update!(country: "US", state: "NV", city: "Reno", zip: "89501")
    @outsider.update_column(:status, Person::RETIRED)

    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "td,th", text: @outsider.callsign, count: 0

    get people_by_location_country_path("US", state: "NV", year: YEAR,
                                        statuses: [Person::RETIRED])

    assert_response :success
    assert_select "td,th", text: @outsider.callsign
  end

  test "a status the page does not hide is ignored rather than filtered on" do
    get people_by_location_path(year: YEAR, statuses: [Person::ACTIVE])

    assert_response :success
    # No chip, because nothing was actually filtered.
    assert_select "a[aria-label*='Remove filter']", count: 0
  end

  test "a nested statuses parameter is dropped instead of raising" do
    get people_by_location_path(year: YEAR, statuses: { bogus: "retired" })

    assert_response :success
  end

  # A state of the wrong shape used to reach url_for untouched, where a hash
  # raises and an array quietly claims the state is empty.
  test "a nested state parameter is dropped instead of raising" do
    get people_by_location_country_path("US", year: YEAR, state: { a: "b" })

    assert_response :success
  end

  # Asserted against the raw body: assert_select's text matcher compares the
  # unescaped text, so it never sees the escaped quotes this used to print.
  test "a state sent as a list is ignored rather than printed as a place" do
    get people_by_location_country_path("US", year: YEAR, state: ["NV"])

    assert_response :success
    assert_no_match(/NV&quot;\]/, response.body)
    # Ignored means the whole country, so the state list is what renders.
    assert_select "a", text: /Nevada/
  end

  # The status boxes only ever add people, so an empty page is never their doing.
  test "an empty page does not blame a filter that only adds people" do
    get people_by_location_country_path("ZZ", year: YEAR, statuses: [Person::RETIRED])

    assert_response :success
    assert_select "body", text: /No one has an address/
    assert_select "body", text: /matches these filters/, count: 0
  end

  # Every level shows addresses, and every reader of this page can see them.
  test "the privacy notice rides on both levels for every reader" do
    sign_in_as(@trainer)
    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_select "body", text: /Personal Information/

    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "body", text: /Personal Information/
  end

  test "the page title names the report, not just the place" do
    get people_by_location_country_path("US", state: "NV", year: YEAR)

    assert_response :success
    assert_select "title", text: /Nevada People by Location/
  end

  # The selector posts a bare GET, so the filters have to be restated here too.
  test "changing the year on the index keeps the filters" do
    get people_by_location_path(year: YEAR, participation: PeopleByLocationReport::EITHER,
                                statuses: [Person::RETIRED])

    assert_response :success
    assert_select "form:has(select[name=year])" do
      assert_select "input[type=hidden][name=participation][value=either]"
      assert_select "input[type=hidden][name='statuses[]'][value=retired]"
    end
  end

  # A punctuation-only state parameterizes to nothing, which used to name the
  # file after the whole country and overwrite that export.
  test "a punctuation-only state exports under its own name" do
    @admin.update_column(:state, "-")

    get people_by_location_country_path("US", state: "-", year: YEAR, format: :csv)

    assert_response :success
    disposition = response.headers["Content-Disposition"]

    assert_no_match(/"#{YEAR}-people-by-location-us\.csv"/, disposition)
    assert_match(/#{YEAR}-people-by-location-us-2d\.csv/, disposition)
  end

  test "people with no country on file get a page that loads" do
    @admin.update_column(:country, "")

    get people_by_location_path(year: YEAR)

    assert_response :success
    assert_select "a[href*='#{people_by_location_country_path(PeopleByLocationReport::NO_COUNTRY)}']"

    get people_by_location_country_path(PeopleByLocationReport::NO_COUNTRY, year: YEAR)

    assert_response :success
    assert_select "td,th", text: @admin.callsign
  end

  test "an unknown participation value is treated as no filter" do
    get people_by_location_path(year: YEAR, participation: "sideways")

    assert_response :success
    assert_select "a[aria-label*='Remove filter']", count: 0
  end
end
