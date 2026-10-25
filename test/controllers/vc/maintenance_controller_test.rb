# frozen_string_literal: true

require "test_helper"

class Vc::MaintenanceControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  DENY_MESSAGE = "Admin or Volunteer Coordinator role required to run maintenance tasks."

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @vc = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)

    # The applicant pipeline the reset sweeps -- one fixture per in-scope status.
    # (Person::PROSPECTIVE_WAITLIST is deliberately unrepresented: it is not a
    # member of the person.status enum, so no row can carry it any more.)
    @alpha = person(:alpha_ranger)                       # Alpha Newbie / AlphaNewbie
    @bonked = person(:bonked_ranger)                     # Bonked Person / BonkedTest
    @prospective = person(:prospective_ranger)           # Prospect Newbie / ProspectiveNewbie
    @past_prospective = person(:past_prospective_ranger) # Past Prospective / PastProspective
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # The generated handle is LastFirstYY, and YY follows Current.year -- assert
  # against the clock the app reads, not the year this test was written in.
  def yy
    (Current.year % 100).to_s
  end

  # reset_callsign gives up only after ten generated handles are all taken, and
  # standing up ten colliding accounts is far more machinery than the case is
  # worth. Minitest 6 dropped Object#stub, so swap the class method by hand and
  # remove the override in ensure -- Person.exists? is inherited from
  # ActiveRecord::Querying, so removing the singleton definition restores it.
  def with_every_callsign_taken
    Person.define_singleton_method(:exists?) { |*| true }
    yield
  ensure
    Person.singleton_class.remove_method(:exists?)
  end

  # --- authorization -------------------------------------------------------

  test "admin can open the maintenance page" do
    sign_in_as(@admin)

    get vc_maintenance_path

    assert_response :success
    assert_match "Volunteer Coordinator Maintenance Functions", response.body
  end

  test "volunteer coordinator can open the maintenance page" do
    sign_in_as(@vc)

    get vc_maintenance_path

    assert_response :success
  end

  # The preview page is the confirmation step, so the index must hold nothing
  # but links to it -- a mutating form on the index would run a reset without
  # the operator ever seeing who it touches.
  test "the index only links to the previews and holds no mutating forms" do
    sign_in_as(@admin)

    get vc_maintenance_path

    assert_select "a[href=?]", vc_maintenance_preview_pnvs_path
    assert_select "a[href=?]", vc_maintenance_preview_past_prospectives_path
    assert_select "form[action=?]", vc_maintenance_reset_pnvs_path, false
    assert_select "form[action=?]", vc_maintenance_reset_past_prospectives_path, false
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)

    get vc_maintenance_path

    assert_redirected_to me_root_path
    assert_equal DENY_MESSAGE, flash[:error]
  end

  # The gate is declared once for the class, but the tasks are the destructive
  # half -- an accidental skip_before_action there is the expensive mistake.
  test "the tasks themselves are behind the same gate" do
    sign_in_as(@outsider)

    post vc_maintenance_reset_pnvs_path

    assert_redirected_to me_root_path
    assert_equal "ProspectiveNewbie", @prospective.reload.callsign
    assert_equal Person::PROSPECTIVE, @prospective.status

    post vc_maintenance_reset_past_prospectives_path

    assert_redirected_to me_root_path
    assert_equal "PastProspective", @past_prospective.reload.callsign
  end

  # --- previews ------------------------------------------------------------

  test "the pnv preview lists every affected account without changing anything" do
    sign_in_as(@admin)

    get vc_maintenance_preview_pnvs_path

    assert_response :success
    assert_match "3 accounts", response.body
    assert_select "th[scope=row] a[href=?]", person_path(@alpha), text: "AlphaNewbie"
    assert_select "td", text: "NewbieA#{yy}"
    assert_select "td", text: "PersonB#{yy}B" # the bonked suffix previews too
    assert_select "td", text: Person::ALPHA

    # The commit form and a way out, exactly as reviewed.
    assert_select "form[action=?] input[type=submit][value=?]",
                  vc_maintenance_reset_pnvs_path, "Reset All 3 Accounts"
    assert_select "a[href=?]", vc_maintenance_path, text: /Cancel/

    { @alpha => ["AlphaNewbie", Person::ALPHA],
      @bonked => ["BonkedTest", Person::BONKED],
      @prospective => ["ProspectiveNewbie", Person::PROSPECTIVE] }.each do |person, (callsign, status)|
      person.reload
      assert_equal callsign, person.callsign, "preview must not save"
      assert_equal status, person.status, "preview must not save"
    end
  end

  # Nothing is saved during a preview, so Person.exists? cannot see a collision
  # between two handles generated in the same batch -- only the taken set passed
  # through reset_callsigns can. Drop it and both rows show the same handle.
  test "the preview numbers colliding handles the way the real run will" do
    sign_in_as(@admin)
    # Give two applicants the same last name and first initial.
    @alpha.update_columns(first_name: "Paula", preferred_name: "")

    get vc_maintenance_preview_pnvs_path

    assert_response :success
    assert_select "td", text: "NewbieP#{yy}"  # @alpha, first in callsign order
    assert_select "td", text: "Newbie2P#{yy}" # @prospective gets the numbered variant
  end

  test "the past prospective preview lists approved callsigns with their status" do
    sign_in_as(@admin)
    @past_prospective.update_column(:callsign_approved, true)

    get vc_maintenance_preview_past_prospectives_path

    assert_response :success
    assert_match "1 account", response.body
    assert_select "th[scope=row] a[href=?]", person_path(@past_prospective), text: "PastProspective"
    assert_select "td", text: "ProspectiveP#{yy}"
    assert_select "td", text: Person::PAST_PROSPECTIVE
    assert_select "form[action=?] input[type=submit][value=?]",
                  vc_maintenance_reset_past_prospectives_path, "Reset All 1 Account"
    assert_equal "PastProspective", @past_prospective.reload.callsign
    assert @past_prospective.callsign_approved?, "preview must not save"
  end

  # No fixture has an approved callsign by default, so this preview is empty.
  test "an empty preview offers no commit button" do
    sign_in_as(@admin)

    get vc_maintenance_preview_past_prospectives_path

    assert_response :success
    assert_match "No Past Prospectives with approved callsigns found", response.body
    assert_select "form[action=?]", vc_maintenance_reset_past_prospectives_path, false
  end

  # The previews leak the whole applicant roster, so they sit behind the same
  # gate as the tasks.
  test "the previews are behind the same gate" do
    sign_in_as(@outsider)

    [vc_maintenance_preview_pnvs_path, vc_maintenance_preview_past_prospectives_path].each do |path|
      get path

      assert_redirected_to me_root_path
    end
  end

  # --- reset applicants to past prospective --------------------------------

  # Both tasks render their ledger on the POST and answer 422 on purpose --
  # Turbo drops a 200 form response, and disabling Turbo on the form would take
  # the confirmation modal with it. A 200 here means the ledger stopped
  # rendering in the browser.
  test "reset pnvs moves the whole applicant pipeline to past prospective" do
    sign_in_as(@admin)

    post vc_maintenance_reset_pnvs_path

    assert_response :unprocessable_entity

    [@alpha, @bonked, @prospective].each do |applicant|
      applicant.reload
      assert_equal Person::PAST_PROSPECTIVE, applicant.status, "#{applicant.callsign} kept its old status"
      assert_not applicant.callsign_approved?, "#{applicant.callsign} kept an approved callsign"
    end

    assert_equal "NewbieA#{yy}", @alpha.callsign
    assert_equal "NewbieP#{yy}", @prospective.callsign

    # No one outside the pipeline is swept up.
    assert_equal "TestRanger", @admin.reload.callsign
    assert_equal "InactiveRanger", @outsider.reload.callsign
  end

  test "the results page is a before-and-after ledger of every account changed" do
    sign_in_as(@admin)

    post vc_maintenance_reset_pnvs_path

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "Reset Applicants to Past Prospective", response.body
    assert_match "3 applicants", response.body
    # The handle they were known by, linked back to the account...
    assert_select "th[scope=row] a[href=?]", person_path(@alpha), text: "AlphaNewbie"
    # ...the handle they now answer to, and the status they came from.
    assert_select "td", text: "NewbieA#{yy}"
    assert_select "td", text: Person::ALPHA
  end

  # reset_callsign reads the CURRENT status to pick its suffix, so it has to run
  # before the status is flipped to past prospective. Reorder those two lines and
  # the B silently disappears from every bonked applicant's new handle.
  test "a bonked applicant keeps the B suffix on the generated callsign" do
    sign_in_as(@admin)

    post vc_maintenance_reset_pnvs_path

    assert_equal "PersonB#{yy}B", @bonked.reload.callsign
    assert_equal Person::PAST_PROSPECTIVE, @bonked.status
  end

  test "a generated callsign that is already taken gets the numbered variant" do
    sign_in_as(@admin)
    # Someone already answers to the handle @prospective is about to be given.
    person(:retired_ranger).update_column(:callsign, "NewbieP#{yy}")

    post vc_maintenance_reset_pnvs_path

    assert_response :unprocessable_entity
    assert_equal "Newbie2P#{yy}", @prospective.reload.callsign
  end

  test "an account whose callsign cannot be generated is reported and left alone" do
    sign_in_as(@admin)

    # Every candidate handle reads as taken, so reset_callsign really does
    # exhaust its ten tries and give up.
    with_every_callsign_taken do
      post vc_maintenance_reset_pnvs_path
    end

    assert_response :unprocessable_entity
    assert_match "Cannot reset callsign", response.body

    @prospective.reload
    assert_equal "ProspectiveNewbie", @prospective.callsign
    assert_equal Person::PROSPECTIVE, @prospective.status
  end

  # --- reset past prospectives ---------------------------------------------

  test "reset past prospectives rewrites approved callsigns without touching status" do
    sign_in_as(@admin)
    @past_prospective.update_column(:callsign_approved, true)

    post vc_maintenance_reset_past_prospectives_path

    assert_response :unprocessable_entity
    assert_select "[data-controller=scroll-to-top]"
    assert_match "Reset Past Prospectives", response.body

    @past_prospective.reload
    assert_equal "ProspectiveP#{yy}", @past_prospective.callsign
    assert_not @past_prospective.callsign_approved?
    assert_equal Person::PAST_PROSPECTIVE, @past_prospective.status
  end

  test "reset past prospectives skips unapproved callsigns and everyone else" do
    sign_in_as(@admin)
    unapproved = @outsider
    unapproved.update_columns(status: Person::PAST_PROSPECTIVE, callsign_approved: false)
    # The applicant pipeline belongs to the other task, not this one.
    @prospective.update_column(:callsign_approved, true)

    post vc_maintenance_reset_past_prospectives_path

    assert_response :unprocessable_entity
    assert_equal "InactiveRanger", unapproved.reload.callsign
    assert_equal "ProspectiveNewbie", @prospective.reload.callsign
    assert_equal Person::PROSPECTIVE, @prospective.status
  end
end
