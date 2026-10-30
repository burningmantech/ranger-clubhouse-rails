# frozen_string_literal: true

require "test_helper"

class PersonControllerTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include AuthenticationTestHelper
  include EmailSuppressionTestHelper
  include PersonTestFactory

  setup do
    Rails.cache.clear

    @target = person(:active_ranger)
    @pii_viewer = person(:auditor_ranger)
    @limited_viewer = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VIEW_PII, "View PII")
    ensure_role(Role::VIEW_EMAIL, "View Email")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    ensure_role(Role::MENTOR, "Mentor")
    ensure_role(Role::TRAINER, "Trainer")

    grant_role(@pii_viewer, Role::ADMIN)
    grant_role(@pii_viewer, Role::VIEW_PII)
    grant_role(@limited_viewer, Role::TRAINER)

    grant_role(@target, Role::EVENT_MANAGEMENT)
    grant_role(@target, Role::VIEW_EMAIL)
  end

  teardown do
    travel_back
    Rails.cache.clear
  end

  test "shows the summary strip and collapsible sections for pii-capable viewers" do
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_response :success
    assert_select "#person-summary-strip", count: 1
    assert_select "#person-summary-strip", text: /Email/
    assert_select "#person-summary-strip", text: /Phone/
    assert_select "#person-summary-strip", text: /Last Seen/
    assert_select "#person-summary-strip", text: /Created/

    assert_select "[role='heading']", text: /Contact Information/, count: 0
    assert_select "[role='heading']", text: /Account Info/, count: 0
    assert_select "[role='heading']", text: /^Status$/, count: 0
    assert_select "[role='heading']", text: /^Photo$/, count: 0

    # Callsign details now live inside the Overview summary strip
    assert_select "#person-summary-strip", text: /Callsign/
    assert_select "#person-summary-strip", text: /Former callsigns/
    assert_select "[role='heading']", text: /Contact Details/, count: 1
    assert_select "[role='heading']", text: /Teams & Positions/, count: 1
    assert_select "[role='heading']", text: /Permissions/, count: 1

    assert_select "details.collapse", count: 3
    assert_select "details summary", text: /Positions \(3 positions\)/
    assert_select "details summary", text: /2 active permissions, 0 inactive/
    assert_select "th", text: "Granted Through"
    assert_select "td", text: /Granted manually/, count: 2
  end

  test "a permission behind unmet position conditions is listed as inactive with the reasons" do
    training = Position.create!(id: Position::TRAINING, title: "In-Person Training",
                                type: Position::TYPE_TRAINING, active: true)
    position = Position.create!(title: "Gated Position", type: Position::TYPE_FRONTLINE, active: true,
                                require_training_for_roles: true, training_position_id: training.id,
                                require_signin_for_roles: true)
    ensure_role(Role::SURVEY_MANAGEMENT_TRAINING, "Survey Management Training")
    PositionRole.create!(position_id: position.id, role_id: Role::SURVEY_MANAGEMENT_TRAINING)
    PersonPosition.create!(person_id: @target.id, position_id: position.id)
    RoleManager.purge_person(@target.id)
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_select "details summary", text: /2 active permissions, 1 inactive/
    assert_select "td", text: /Position: Gated Position/
    assert_select "td", text: /Has not passed or taught In-Person Training in #{Current.year}/
    assert_select "td", text: /Not signed in to Gated Position/
    assert_select "td .badge", text: "deactivated"
  end

  test "an unsigned NDA shows one callout and marks every permission inactive" do
    create_nda
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_select "[role='alert']", text: /All permissions are off because #{@target.callsign} has not signed/
    assert_select "a.tap-target-link[href='#{person_agreements_path(@target)}']", text: "View Agreements"
    assert_select "details summary", text: /0 active permissions, 2 inactive/
  end

  # Person::AgreementsController admits only Admin and Event Management.
  test "the NDA callout offers the agreements link only to viewers who can open it" do
    create_nda
    sign_in_as(@limited_viewer)

    get person_path(@target)

    assert_select "[role='alert']", text: /All permissions are off because #{@target.callsign} has not signed/
    assert_select "a[href='#{person_agreements_path(@target)}']", count: 0
  end

  test "shows the manage account banners action for event-management admins" do
    grant_role(@pii_viewer, Role::EVENT_MANAGEMENT)
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_response :success
    assert_select "details.dropdown > summary", text: /Actions/
    assert_select "ul.dropdown-content.dropdown-panel a[href='#{person_banners_path(@target)}']",
                  text: /Manage Account Banners/
  end

  # =========================================================================
  # The email banner (EmailSuppression)
  # =========================================================================

  test "the email banner says the address bounced, and when it last did" do
    travel_to(Time.zone.local(2026, 9, 1, 8, 0, 0)) { suppress_email(@target.email, message_id: "ses-1") }
    travel_to(Time.zone.local(2026, 10, 9, 14, 30, 0)) { suppress_email(@target.email, message_id: "ses-2") }
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_select "#email-suppression-banner[role='alert']",
                  text: /Email to this account's address bounced on\s+Fri Oct 9, 2026 @ 14:30\./
  end

  test "the email banner says the address reported a Clubhouse email as spam" do
    suppress_email(@target.email, reason: EmailSuppression::COMPLAINT)
    sign_in_as(@limited_viewer)

    get person_path(@target)

    assert_select "#email-suppression-banner", text: /Email to this account's address was reported as spam on/
  end

  # The banner reaches roles that may not see contact details, the confirmation included.
  test "the email banner never prints the address" do
    suppress_email(@target.email, reason: EmailSuppression::COMPLAINT)
    sign_in_as(@pii_viewer)

    get person_path(@target)

    banner = css_select("#email-suppression-banner").first
    assert banner
    assert_not_includes banner.to_html, @target.email
    assert_not_includes CGI.unescapeHTML(banner.to_html), @target.email
  end

  test "no email banner shows without a row for the person's address" do
    suppress_email("someone-else@example.com")
    sign_in_as(@pii_viewer)

    get person_path(@target)

    assert_response :success
    assert_select "#email-suppression-banner", count: 0
    assert_not_includes response.body, "Email address is bouncing"
  end

  test "hides PII and contact details without pii or email access" do
    sign_in_as(@limited_viewer)

    get person_path(@target)

    assert_response :success

    # Summary strip renders but without PII fields
    assert_select "#person-summary-strip", count: 1
    assert_select "#person-summary-strip", text: /Email/, count: 0
    assert_select "#person-summary-strip", text: /Phone/, count: 0

    assert_select "[role='heading']", text: /Contact Details/, count: 0

    assert_select "#person-summary-strip", text: /Callsign/
    assert_select "[role='heading']", text: /Teams & Positions/, count: 1
    assert_select "[role='heading']", text: /Permissions/, count: 1
  end

  test "offers the teams and positions history to every viewer and the editor to team managers" do
    sign_in_as(@limited_viewer)

    get person_path(@target)

    assert_response :success
    assert_select "a[href=?]", person_membership_history_path(@target), text: /View History/, count: 1
    assert_select "a[href=?]", edit_person_membership_path(@target), count: 0

    TeamManager.create!(person_id: @limited_viewer.id, team_id: teams(:council_cadre).id)
    get person_path(@target)

    assert_response :success
    assert_select "a[href=?]", person_membership_history_path(@target), text: /View History/, count: 1
    assert_select "a[href=?]", edit_person_membership_path(@target), count: 1
  end

  test "toggling on site records the change and who made it" do
    subject = person(:echelon_ranger)
    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@target, Role::SHIFT_MANAGEMENT)
    sign_in_as(@target)

    assert_difference -> { PersonOnSite.where(person_id: subject.id).count }, 1 do
      post person_toggle_onsite_path(subject)
    end

    assert_redirected_to person_path(subject)
    assert subject.reload.on_site
    row = PersonOnSite.where(person_id: subject.id).last
    assert_equal PersonOnSite::ON_SITE, row.action
    assert_equal @target.id, row.creator_person_id
  end

  # Clubhouse 2 keeps on_site in PersonFilter's EVENT_FIELDS: Shift Management or Admin.
  test "every page role without Admin or Shift Management is refused the on-site toggle and offered no button" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")

    (PersonConcern::VIEW_ROLES - [Role::ADMIN, Role::SHIFT_MANAGEMENT]).each do |role_id|
      ensure_role(role_id, "Role #{role_id}")
      viewer = create_person("Viewer#{role_id}")
      grant_role(viewer, role_id)
      sign_in_as(viewer)

      get person_path(@target)
      assert_response :success, "role #{role_id} should open the page"
      assert_select "a", text: /Mark (On|Off) Site/, count: 0

      assert_no_changes -> { [@target.reload.on_site, PersonOnSite.where(person_id: @target.id).count] },
                        "role #{role_id} toggled on site" do
        post person_toggle_onsite_path(@target)
      end
      assert_redirected_to person_path(@target)
      assert_equal "Admin or Shift Management role required to mark a person on or off site.", flash[:error]
    end
  end

  test "an Admin without Shift Management is offered the toggle and marks on site" do
    sign_in_as(@pii_viewer) # holds Admin

    get person_path(@target)
    assert_select "a", text: /Mark (On|Off) Site/, count: 1

    assert_changes -> { @target.reload.on_site } do
      post person_toggle_onsite_path(@target)
    end
    assert_redirected_to person_path(@target)
  end

  # Clubhouse 2's PersonPolicy#delete admits Tech Ninja alone -- Admin included, no
  # page role carries it.
  test "every page role without Tech Ninja is refused the delete and offered no menu item" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")

    PersonConcern::VIEW_ROLES.each do |role_id|
      ensure_role(role_id, "Role #{role_id}")
      viewer = create_person("Viewer#{role_id}")
      grant_role(viewer, role_id)
      sign_in_as(viewer)

      get person_path(@target)
      assert_response :success, "role #{role_id} should open the page"
      assert_select "ul.dropdown-content a", text: "Delete Account", count: 0

      assert_no_difference -> { Person.where(id: @target.id).count }, "role #{role_id} deleted the account" do
        delete person_path(@target)
      end
      assert_redirected_to person_path(@target)
      assert_equal "Tech Ninja role required to delete an account.", flash[:error]
    end
  end

  # Mentor, not Admin, opens the page, so the delete rides on Tech Ninja alone.
  test "a Tech Ninja is offered Delete Account and deletes the account" do
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    ninja = create_person("Ninja")
    grant_role(ninja, Role::MENTOR)
    grant_role(ninja, Role::TECH_NINJA)
    sign_in_as(ninja)

    get person_path(@target)
    assert_select "ul.dropdown-content a[href='#{person_path(@target)}']", text: "Delete Account", count: 1

    assert_difference -> { Person.where(id: @target.id).count }, -1 do
      delete person_path(@target)
    end
    assert_redirected_to me_root_path
    assert_equal "Account deleted.", flash[:success]
  end

  # Queued, so the job that sends it has nobody signed in: whoever asked
  # travels with it, for the mail log. @pii_viewer holds Admin and no VC.
  test "resending the welcome email queues it in the name of whoever asked" do
    prospective = person(:prospective_ranger)
    sign_in_as(@pii_viewer)

    assert_enqueued_email_with WelcomeMailer, :notify, params: { sender_id: @pii_viewer.id },
                                                       args: ->(args) { args.first[:person] == prospective } do
      post person_resend_welcome_path(prospective)
    end
  end

  # As long as Create Prospectives' first link, and as Clubhouse 2's resend.
  test "a VC resends the welcome message with a link that lasts 14 days" do
    prospective = person(:prospective_ranger)
    vc = create_vc
    sign_in_as(vc)
    freeze_time
    token = nil

    assert_enqueued_email_with WelcomeMailer, :notify, params: { sender_id: vc.id },
                                                       args: ->(args) { token = args.first[:invite_token] } do
      post person_resend_welcome_path(prospective)
    end
    assert_redirected_to person_path(prospective)
    assert_equal "Welcome message resent.", flash[:success]

    assert_equal prospective, Person.find_by_token_for(:invitation, token)
    travel Person::PNV_INVITATION_EXPIRE.seconds - 1.second
    assert_equal prospective, Person.find_by_token_for(:invitation, token), "the link lasts the full 14 days"
    travel 2.seconds
    assert_nil Person.find_by_token_for(:invitation, token), "and not a moment longer"
  end

  # The token is signed, not stored, so a link already sent is not disturbed by
  # a resend: both open until their own 14 days are up, or the password is set.
  test "a resend leaves an earlier link working" do
    prospective = person(:prospective_ranger)
    earlier = prospective.generate_token_for(:invitation)
    sign_in_as(create_vc)

    post person_resend_welcome_path(prospective)

    assert_equal prospective, Person.find_by_token_for(:invitation, earlier)
  end

  # Nothing is saved: the token is signed from the record as it stands, so a
  # record that would fail validation still gets its email, untouched.
  test "a resend sends for a record that fails validation, and changes nothing" do
    prospective = person(:prospective_ranger)
    prospective.update_columns(home_phone: "")
    assert_not prospective.valid?
    untouched = prospective.reload.attributes
    sign_in_as(create_vc)

    assert_enqueued_emails 1 do
      post person_resend_welcome_path(prospective)
    end
    assert_redirected_to person_path(prospective)
    assert_equal untouched, prospective.reload.attributes
  end

  # Clubhouse 2's PersonPolicy#sendWelcomeEmail admits Admin or VC.
  test "every page role without Admin or VC is refused the resend and offered no menu item" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    prospective = person(:prospective_ranger)

    (PersonConcern::VIEW_ROLES - [Role::ADMIN, Role::VC]).each do |role_id|
      ensure_role(role_id, "Role #{role_id}")
      viewer = create_person("Viewer#{role_id}")
      grant_role(viewer, role_id)
      sign_in_as(viewer)

      get person_path(prospective)
      assert_response :success, "role #{role_id} should open the page"
      assert_select "a[href='#{person_resend_welcome_path(prospective)}']", count: 0

      assert_no_enqueued_emails do
        post person_resend_welcome_path(prospective)
      end
      assert_redirected_to person_path(prospective)
      assert_equal "Admin or Volunteer Coordinator role required to resend the welcome message.", flash[:error]
    end
  end

  test "a VC is offered Resend Welcome Message on a prospective, and not on an active Ranger" do
    prospective = person(:prospective_ranger)
    sign_in_as(create_vc)

    get person_path(prospective)
    assert_select "ul.dropdown-content a[href='#{person_resend_welcome_path(prospective)}']",
                  text: "Resend Welcome Message", count: 1

    get person_path(@target)
    assert_select "a[href='#{person_resend_welcome_path(@target)}']", count: 0
  end

  # When TestRanger took the first-sign-in tour, in the tests below.
  TOUR_TAKEN = Time.zone.local(2026, 4, 1, 9, 0, 0)

  # Clearing the tour timestamp shows the person the first-sign-in tour again.
  # The write skips validations, as the resend's token save does, and
  # audit_model logs who reset whose.
  test "a VC resets the onboarding tour, and the audit log names who and whose" do
    @target.update_columns(on_boarded_at: TOUR_TAKEN, home_phone: "")
    assert_not @target.valid?
    vc = create_vc
    sign_in_as(vc)

    get person_path(@target)
    assert_select "ul.dropdown-content a[href='#{person_reset_onboarding_path(@target)}']",
                  text: "Reset Onboarding Tour", count: 1

    assert_difference -> { ActionLog.count }, 1 do
      post person_reset_onboarding_path(@target)
    end

    assert_redirected_to person_path(@target)
    assert_equal "#{@target.callsign} will see the onboarding tour at their next visit to the dashboard.",
                 flash[:success]
    assert_nil @target.reload.on_boarded_at
    log = ActionLog.find_by!(event: "person-update")
    assert_equal [vc.id, @target.id], [log.person_id, log.target_person_id]
    assert_nil log.data.fetch("on_boarded_at").last
  end

  test "every page role without Admin or VC is refused the reset and offered no menu item" do
    Setting.find_or_initialize_by(name: Setting::EVENT_MANAGEMENT_ON_PLAYA_ENABLED).update!(value: "true")
    @target.update_column(:on_boarded_at, TOUR_TAKEN)

    (PersonConcern::VIEW_ROLES - [Role::ADMIN, Role::VC]).each do |role_id|
      ensure_role(role_id, "Role #{role_id}")
      viewer = create_person("Viewer#{role_id}")
      grant_role(viewer, role_id)
      sign_in_as(viewer)

      get person_path(@target)
      assert_response :success, "role #{role_id} should open the page"
      assert_select "a[href='#{person_reset_onboarding_path(@target)}']", count: 0

      assert_no_difference -> { ActionLog.count } do
        post person_reset_onboarding_path(@target)
      end
      assert_redirected_to person_path(@target)
      assert_equal "Admin or Volunteer Coordinator role required to reset the onboarding tour.", flash[:error]
      assert_equal TOUR_TAKEN, @target.reload.on_boarded_at, "role #{role_id} cleared the tour"
    end
  end

  # @pii_viewer holds Admin and no VC.
  test "an admin is offered Reset Onboarding Tour once the tour is taken, sees when, and resets it" do
    sign_in_as(@pii_viewer)

    get person_path(@target)
    assert_select "a[href='#{person_reset_onboarding_path(@target)}']", count: 0
    assert_select "#person-summary-strip", text: /Onboarding Tour\s+Not yet taken/

    @target.update_column(:on_boarded_at, TOUR_TAKEN)
    get person_path(@target)
    assert_select "ul.dropdown-content a[href='#{person_reset_onboarding_path(@target)}'][data-turbo-confirm]",
                  text: "Reset Onboarding Tour", count: 1
    assert_select "#person-summary-strip", text: /Onboarding Tour\s+Wed Apr 1, 2026 @ 09:00/

    post person_reset_onboarding_path(@target)
    assert_redirected_to person_path(@target)
    assert_nil @target.reload.on_boarded_at
  end

  private

  # Creating the document writes an audit row, which needs someone acting.
  def create_nda
    Current.person = @pii_viewer
    Document.create!(tag: Document::DEPT_NDA_TAG, description: "Department NDA", body: "body",
                     person_create_id: @pii_viewer.id, person_update_id: @pii_viewer.id)
    Current.person = nil
    RoleManager.purge_person(@target.id)
  end

  # A viewer holding the Volunteer Coordinator role and nothing else.
  def create_vc
    ensure_role(Role::VC, "Volunteer Coordinator")
    vc = create_person("Coordinator")
    grant_role(vc, Role::VC)
    vc
  end

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
    RoleManager.purge_person(person.id.to_s)
  end
end
