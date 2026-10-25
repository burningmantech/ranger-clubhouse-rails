# frozen_string_literal: true

require "test_helper"

# Mentoring > Convert Alphas: who lands in each of the two sections, the
# verdict-to-outcome pairing the POST enforces, and the conversions themselves --
# the status flip, the positions granted and stripped, the audit trail, and the
# 422 render that keeps the just-converted people on screen.
class Mentoring::AlphasConvertControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include PersonTestFactory
  include DomIdTestHelper
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2026
  DENY_MESSAGE = "Admin or Mentor role required to convert Alphas."

  setup do
    travel_to Time.zone.local(YEAR, 9, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    # Both are granted or stripped by PersonStatusManagement on the way through,
    # and PersonPosition's belongs_to blows up without the rows.
    Position.create!(id: Position::ALPHA, title: "Alpha", type: Position::TYPE_FRONTLINE, active: true)
    Position.create!(id: Position::DIRT_SHINY_PENNY, title: "Dirt - Shiny Penny",
                     type: Position::TYPE_FRONTLINE, active: true)

    @mentor_one = create_person("Firecracker")
    @mentor_two = create_person("HotShot")

    @passed = create_alpha("Zebra", PersonMentor::STATUS_PASS, mentors: [@mentor_one, @mentor_two])
    @also_passed = create_alpha("DustBunny", PersonMentor::STATUS_PASS)
    @bonked = create_alpha("Mirage", PersonMentor::STATUS_BONK)
    @self_bonked = create_alpha("Whiteout", PersonMentor::STATUS_SELF_BONK)

    # None of these four may be offered.
    @walking = create_alpha("Halcyon", PersonMentor::STATUS_PENDING)
    @unjudged = create_person("Turnstile", status: Person::ALPHA)
    @last_year = create_alpha("Moonwrench", PersonMentor::STATUS_PASS, year: YEAR - 1)
    @already_active = create_alpha("Quartz", PersonMentor::STATUS_PASS, status: Person::ACTIVE)

    @admin = person(:auditor_ranger)
    @mentor = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@mentor, Role::MENTOR)
    grant_role(@outsider, Role::VC)

    Current.person = @admin
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- authorization -------------------------------------------------------

  test "a mentor can view the page" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_match "Convert Alphas", response.body
  end

  test "an admin can view the page" do
    sign_in_as(@admin)

    get mentoring_alphas_convert_path

    assert_response :success
  end

  test "a role outside the gate is turned away" do
    sign_in_as(@outsider)

    get mentoring_alphas_convert_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  test "the convert action is behind the same gate" do
    sign_in_as(@outsider)

    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [@passed.id] }

    assert_redirected_to me_root_path
    assert_equal Person::ALPHA, @passed.reload.status
  end

  # --- the roster ----------------------------------------------------------

  test "a passing verdict lands in the mint section and a bonk in the bonk section" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#mint-person-#{@passed.id}"
    assert_select "#mint-person-#{@also_passed.id}"
    assert_select "#bonk-person-#{@bonked.id}"
    assert_select "#bonk-person-#{@self_bonked.id}"

    # Neither section may offer the other's people.
    assert_select "#bonk-person-#{@passed.id}", false
    assert_select "#mint-person-#{@bonked.id}", false
  end

  # Upstream's HAVING drops both pending verdicts and Alphas with no mentor row
  # at all; Alpha Status is the page that chases those.
  test "alphas still walking, unjudged, stale, or no longer alpha are not offered" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    [@walking, @unjudged, @last_year, @already_active].each do |person|
      assert_select "#mint-person-#{person.id}", false
      assert_select "#bonk-person-#{person.id}", false
      assert_no_match(/#{person.callsign}/, response.body)
    end
  end

  test "the mentors who walked with each alpha are named" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_match "#{@mentor_one.callsign} and #{@mentor_two.callsign}", response.body
  end

  # A mentor account that no longer exists must not take the page down with it:
  # person_mentor has no foreign key, so a dangling mentor_id is reachable.
  test "a deleted mentor is named as such rather than blowing up the page" do
    sign_in_as(@mentor)
    orphan = create_alpha("Kestrel", PersonMentor::STATUS_PASS, mentors: [@mentor_two])
    Person.where(id: @mentor_two.id).delete_all

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#mint-person-#{orphan.id}"
    assert_match "Deleted ##{@mentor_two.id}", response.body
  end

  # House wording, not upstream's raw "pass"/"self-bonk" database values. Scoped
  # to the row's own badge: "Bonked" also appears in the section heading "N
  # Bonked Alphas", so a bare assert_match would pass with no badge rendered.
  test "verdicts are named in sentence case" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#mint-row-#{@passed.id} .badge", text: "Passed"
    assert_select "#bonk-row-#{@bonked.id} .badge", text: "Bonked"
    assert_select "#bonk-row-#{@self_bonked.id} .badge", text: "Self-bonked"
  end

  test "the page ignores a year parameter" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path(year: 2019)

    assert_response :success
    assert_select "#mint-person-#{@passed.id}"
  end

  test "an empty roster says so instead of rendering two bare forms" do
    sign_in_as(@mentor)
    PersonMentor.where(mentor_year: YEAR).delete_all

    get mentoring_alphas_convert_path

    assert_response :success
    assert_match "there is no one to convert", response.body
    assert_select "input[name='person_ids[]']", false
  end

  test "a section with no one in it says so while the other still works" do
    sign_in_as(@mentor)
    PersonMentor.where(mentor_year: YEAR,
                       status: [PersonMentor::STATUS_BONK, PersonMentor::STATUS_SELF_BONK]).delete_all

    get mentoring_alphas_convert_path

    assert_response :success
    assert_match "No Alpha was bonked or self-bonked in #{YEAR}.", response.body
    assert_select "#mint-person-#{@passed.id}"
  end

  # The stat boxes count who is still waiting; the section titles count the rows
  # on screen. Those two disagree by design once something has been converted,
  # and a just-converted person must fall out of the first but not the second.
  # A stat box renders its value and label as adjacent divs, so the container's
  # text reads "2Ready to mint".
  test "the counts describe who is still waiting, not the rows on screen" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path
    assert_select "div.text-center", text: /2\s*Ready to Mint/
    assert_select "div.text-center", text: /2\s*Ready to Bonk/

    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [@passed.id] }

    assert_select "div.text-center", text: /1\s*Ready to Mint/
    assert_select "#mint-row-#{@passed.id}"
    assert_match "2 Shiny Penny candidates", response.body
    assert_select "#mint-section .badge", text: "Converted"
  end

  # An irreversible action must not lose its confirmation to a careless edit:
  # neither the modal nor the disable-until-checked wiring shows up in any other
  # assertion, so removing either would otherwise pass silently.
  test "each section keeps its own confirm dialog and disabled-until-checked submit" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#mint-section [type=submit][data-turbo-confirm*=?]", "Mint Shiny Pennies"
    assert_select "#bonk-section [type=submit][data-turbo-confirm*=?]", "Bonk Alphas"
    assert_select "#mint-section [type=submit][data-checkbox-select-all-target=submit]"
    assert_select "#bonk-section [type=submit][data-checkbox-select-all-target=submit]"
  end

  # Two bulk-select groups on one page: the select-all checkbox takes its id
  # from its name, and so does the hidden target field, so both have to be
  # named per section or Turbo silently drops one form's fields.
  test "the two forms do not collide" do
    sign_in_as(@mentor)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_unique_dom_ids
    assert_select "#target-mint[value=?]", Person::ACTIVE
    assert_select "#target-bonk[value=?]", Person::BONKED
    assert_select "input[name=select_all_mint]"
    assert_select "input[name=select_all_bonk]"
  end

  # --- minting -------------------------------------------------------------

  test "minting makes an active ranger and grants the shiny penny position" do
    sign_in_as(@mentor)
    PersonPosition.create!(person_id: @passed.id, position_id: Position::ALPHA)

    post mentoring_alphas_convert_path,
         params: { target: Person::ACTIVE, person_ids: [@passed.id, @also_passed.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ACTIVE, @passed.reload.status
    assert_equal Person::ACTIVE, @also_passed.reload.status
    assert PersonPosition.exists?(person_id: @passed.id, position_id: Position::DIRT_SHINY_PENNY)
    # PersonStatusManagement strips the Alpha position on the way out.
    assert_not PersonPosition.exists?(person_id: @passed.id, position_id: Position::ALPHA)
  end

  test "minting writes the upstream audit reason to the status history" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [@passed.id] }

    row = PersonStatus.where(person_id: @passed.id).order(:created_at).last
    assert_equal Person::ALPHA, row.old_status
    assert_equal Person::ACTIVE, row.new_status
    assert_equal AlphaConversion::AUDIT_REASON, row.reason
    assert_equal @mentor.id, row.person_source_id
  end

  # --- bonking -------------------------------------------------------------

  test "bonking sets bonked status and strips every position" do
    sign_in_as(@mentor)
    PersonPosition.create!(person_id: @bonked.id, position_id: Position::ALPHA)

    post mentoring_alphas_convert_path,
         params: { target: Person::BONKED, person_ids: [@bonked.id, @self_bonked.id] }

    assert_response :unprocessable_entity
    assert_equal Person::BONKED, @bonked.reload.status
    assert_equal Person::BONKED, @self_bonked.reload.status
    assert_empty PersonPosition.where(person_id: @bonked.id)
  end

  # --- the verdict-to-outcome pairing --------------------------------------

  # Upstream's endpoint takes an id and a status and asks nothing else, so any
  # person could be flipped either way. Here the verdict has to agree.
  test "a passing alpha cannot be bonked through the bonk form" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::BONKED, person_ids: [@passed.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @passed.reload.status
    assert_match "could not be converted", response.body
  end

  test "a bonked alpha cannot be minted through the mint form" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [@bonked.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ALPHA, @bonked.reload.status
    assert_match "could not be converted", response.body
  end

  # The submitted list is stale by definition: another mentor may have acted
  # since the page was drawn, so every id is re-checked before it is trusted.
  test "an id that is no longer an alpha is skipped and reported" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path,
         params: { target: Person::ACTIVE, person_ids: [@passed.id, @already_active.id, @unjudged.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ACTIVE, @passed.reload.status
    assert_equal Person::ALPHA, @unjudged.reload.status
    assert_match "could not be converted", response.body
  end

  # The skipped count is a subtraction, so a repeated id would otherwise be
  # reported as a person who could not be converted.
  test "the same id sent twice is not reported as a failure" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path,
         params: { target: Person::ACTIVE, person_ids: [@passed.id, @passed.id] }

    assert_response :unprocessable_entity
    assert_equal Person::ACTIVE, @passed.reload.status
    assert_no_match(/could not be converted/, response.body)
  end

  # to_i read "abc" as person 0, reported as someone who could not be
  # converted, and "#{id}x" as that person, who was minted.
  test "ids that are not ids check no one" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path,
         params: { target: Person::ACTIVE, person_ids: ["", "abc", "#{@passed.id}x"] }

    assert_redirected_to mentoring_alphas_convert_path
    assert_equal "Check at least one Shiny Penny candidate to mint.", flash[:alert]
    assert_equal Person::ALPHA, @passed.reload.status
  end

  test "an outcome this page does not offer is refused" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::UBERBONKED, person_ids: [@passed.id] }

    assert_redirected_to mentoring_alphas_convert_path
    assert_equal "Use one of this page's own buttons to convert Alphas.", flash[:alert]
    assert_equal Person::ALPHA, @passed.reload.status
  end

  test "converting no one says which section was empty" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::BONKED, person_ids: [] }

    assert_redirected_to mentoring_alphas_convert_path
    assert_equal "Check at least one Alpha to bonk.", flash[:alert]
  end

  # --- the results render --------------------------------------------------

  # The results cannot be re-derived by a GET: the converted people are not
  # Alphas any more, and so off the roster the page is drawn from.
  test "the minted people stay on the page with the results" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [@passed.id] }

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "Minted 1 Shiny Penny", response.body
    assert_select "#mint-row-#{@passed.id}"
    # Converted, so no longer offered...
    assert_select "#mint-person-#{@passed.id}", false
    # ...while everyone left keeps their checkbox.
    assert_select "#mint-person-#{@also_passed.id}"
  end

  test "the bonked people stay on the page with the results" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path, params: { target: Person::BONKED, person_ids: [@bonked.id] }

    assert_response :unprocessable_entity
    assert_match "Bonked 1 Alpha", response.body
    assert_select "#bonk-row-#{@bonked.id}"
    assert_select "#bonk-person-#{@bonked.id}", false
  end

  test "minting several reads as a plural" do
    sign_in_as(@mentor)

    post mentoring_alphas_convert_path,
         params: { target: Person::ACTIVE, person_ids: [@passed.id, @also_passed.id] }

    assert_match "Minted 2 Shiny Pennies", response.body
  end

  # --- verdicts that disagree with themselves ------------------------------

  # Upstream picks one of a year's rows arbitrarily (GROUP BY status LIMIT 1),
  # so which verdict it reports can change between reads. The pick here is
  # repeatable, and lands on the cautious side of the disagreement.
  test "an alpha whose verdicts disagree is listed as bonked, repeatably" do
    sign_in_as(@mentor)
    conflicted = create_alpha("Cinder", PersonMentor::STATUS_PASS)
    PersonMentor.create!(person_id: conflicted.id, mentor_id: @mentor_two.id,
                         mentor_year: YEAR, status: PersonMentor::STATUS_BONK)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#bonk-person-#{conflicted.id}"
    assert_select "#mint-person-#{conflicted.id}", false
  end

  # The other direction, which a smallest-value pick gets backwards: "pass"
  # sorts before "self-bonk", so a MIN would offer this Alpha for minting.
  test "a pass alongside a self-bonk is not offered for minting" do
    sign_in_as(@mentor)
    conflicted = create_alpha("Ember", PersonMentor::STATUS_PASS)
    PersonMentor.create!(person_id: conflicted.id, mentor_id: @mentor_two.id,
                         mentor_year: YEAR, status: PersonMentor::STATUS_SELF_BONK)

    get mentoring_alphas_convert_path

    assert_select "#bonk-person-#{conflicted.id}"
    assert_select "#mint-person-#{conflicted.id}", false

    # ...and the POST agrees with the page: minting them is refused.
    post mentoring_alphas_convert_path, params: { target: Person::ACTIVE, person_ids: [conflicted.id] }

    assert_equal Person::ALPHA, conflicted.reload.status
  end

  # Upstream's arbitrary pick may land on the pending row, and its HAVING then
  # drops the person entirely -- a recorded verdict no one can act on.
  test "a recorded verdict is offered even alongside a pending row" do
    sign_in_as(@mentor)
    half_recorded = create_alpha("Pigment", PersonMentor::STATUS_PENDING)
    PersonMentor.create!(person_id: half_recorded.id, mentor_id: @mentor_two.id,
                         mentor_year: YEAR, status: PersonMentor::STATUS_PASS)

    get mentoring_alphas_convert_path

    assert_response :success
    assert_select "#mint-person-#{half_recorded.id}"
  end

  private

  def create_alpha(callsign, verdict, mentors: nil, year: YEAR, status: Person::ALPHA)
    person = create_person(callsign, status: status)
    (mentors || [@mentor_one]).each do |mentor|
      PersonMentor.create!(person_id: person.id, mentor_id: mentor.id, mentor_year: year, status: verdict)
    end
    person
  end
end
