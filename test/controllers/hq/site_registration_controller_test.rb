# frozen_string_literal: true

require "test_helper"

# Covers the On-Site Registration wizard (Ember port/templates/hq/site-checkin.hbs):
# the HQ gates, the already-on-site lockout, the camp/emergency step saves and
# their advance signals, the server-side emergency-contact authorization, the
# radio-check interstitial branches, and marking the person on site.
class Hq::SiteRegistrationControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @viewer = person(:active_ranger)
    @subject = person(:ranger_with_custom_gender)

    ensure_role(Role::SHIFT_MANAGEMENT, "Shift Management")
    grant_role(@viewer, Role::SHIFT_MANAGEMENT)

    # The HQ shell loads PersonEventInfo, whose training lookup falls back to
    # Position.find(Position::TRAINING) — the fixtures do not pin that id.
    Position.find_or_create_by!(id: Position::TRAINING) do |position|
      position.title = "In-Person Training"
      position.type = Position::TYPE_TRAINING
      position.active = true
    end

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # --- Gates ---------------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_site_registration_path(@subject)

    assert_redirected_to person_path(@subject)
    assert_equal "The HQ Window Interface is not currently available.", flash[:error]
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject)

    get hq_site_registration_path(@viewer)

    assert_redirected_to me_root_path
  end

  # --- Landing page + wizard rendering -------------------------------------

  test "renders the landing sections and all four wizard steps" do
    get hq_site_registration_path(@subject)

    assert_response :success
    assert_match "On-Site Registration", response.body
    assert_match "Begin On-Site Registration", response.body
    assert_match "Provisions Summary", response.body
    assert_match "Vehicle Use Protocol", response.body

    assert_select "turbo-frame#site-registration-wizard"
    assert_select "[data-controller=?]", "hq-wizard"
    # The steps present as one modal dialog — upstream's ui-wizard-step
    # renders each active step inside a ModalDialog.
    assert_select "dialog[data-hq-wizard-target=dialog] .modal-box " \
                  "section[data-hq-wizard-target=step]", count: 4
    assert_match "Step 1 of 4 — Verify Camp Information", response.body
    assert_match "Step 3 of 4 — Radios", response.body
    assert_match "Step 4 of 4 — Mark Person as On Site", response.body
    assert_select "form[action=?]", hq_site_registration_camp_info_path(@subject)
  end

  test "skips the radios step for an alpha and shows the hat rack copy" do
    alpha = person(:alpha_ranger)

    get hq_site_registration_path(alpha)

    assert_response :success
    assert_select "section[data-hq-wizard-target=step]", count: 3
    assert_no_match "— Radios", response.body
    assert_match "Step 3 of 3 — Mark Person as On Site", response.body
    assert_match "Do not hand over a Ranger field guide", response.body
  end

  # The checkout form must post to this controller's own endpoint. Pointing it
  # at shift-manage would redirect out of the "site-registration-wizard" turbo
  # frame, which the response cannot match — the operator gets a spurious error
  # and loses their wizard position even though the asset was issued.
  test "the radios step posts checkout to the site-registration endpoint when authorized" do
    authorize_subject_for_event_radios(item_count: 2)

    get hq_site_registration_path(@subject)

    assert_response :success
    assert_match "Authorized for 2 Event Radios", response.body
    assert_select "form[action=?]", hq_site_registration_assets_path(@subject)
    assert_select "form[action=?]", hq_shift_manage_assets_path(@subject), false
  end

  test "checking out a radio streams the radios step back instead of redirecting" do
    authorize_subject_for_event_radios(item_count: 2)
    asset = Asset.create!(barcode: "SR-101", type: Asset::TYPE_RADIO, year: Current.year,
                          perm_assign: false)

    assert_difference "PersonAsset.count", 1 do
      post hq_site_registration_assets_path(@subject),
           params: { person_asset: { barcode: "SR-101" } },
           as: :turbo_stream
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    # Targets the step region, so the wizard's client-side step index survives.
    assert_match "hq-step-radios", response.body
    assert_equal @subject.id, PersonAsset.order(:id).last.person_id
    assert_equal asset.id, PersonAsset.order(:id).last.asset_id
  end

  test "an unknown barcode streams the error without leaving the wizard" do
    authorize_subject_for_event_radios(item_count: 2)

    assert_no_difference "PersonAsset.count" do
      post hq_site_registration_assets_path(@subject),
           params: { person_asset: { barcode: "NOPE-404" } },
           as: :turbo_stream
    end

    assert_response :success
    assert_match "hq-step-radios", response.body
    assert_match "was not found", response.body
  end

  # --- Already-on-site lockout ---------------------------------------------

  test "an on-site person sees the success state with a disabled begin button" do
    @subject.update_columns(on_site: true)

    get hq_site_registration_path(@subject)

    assert_response :success
    assert_match "#{@subject.callsign} Marked On Site", response.body
    assert_select "a[href=?]", hq_shift_manage_path(@subject), text: "Start Shift Check-In"
    assert_select "button[disabled]", text: "Begin On-Site Registration"
    assert_select "section[data-hq-wizard-target=step]", count: 0
  end

  test "step saves are refused once the person is on site" do
    @subject.update_columns(on_site: true, camp_location: "Original camp")

    patch hq_site_registration_camp_info_path(@subject),
          params: { person: { camp_location: "New camp" } }

    assert_redirected_to hq_site_registration_path(@subject)
    assert_match "already marked on site", flash[:info]
    assert_equal "Original camp", @subject.reload.camp_location

    post hq_site_registration_on_site_path(@subject)

    assert_redirected_to hq_site_registration_path(@subject)
    assert_match "already marked on site", flash[:info]
  end

  # --- Camp information step -----------------------------------------------

  test "a successful camp info save streams the step and the advance signal" do
    patch hq_site_registration_camp_info_path(@subject),
          params: { person: { camp_location: "Camp Specificity, 9:15 & D, Mountainside" } }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'target="hq-step-camp-info"', response.body
    assert_match 'target="hq-wizard-signal"', response.body
    assert_match "data-hq-wizard-target=\"advance\"", response.body
    assert_match "Saved the camp information.", response.body
    assert_equal "Camp Specificity, 9:15 & D, Mountainside", @subject.reload.camp_location
  end

  test "a failed camp info save re-renders the step without advancing" do
    original = @subject.camp_location

    patch hq_site_registration_camp_info_path(@subject),
          params: { person: { camp_location: "x" * 201 } }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'target="hq-step-camp-info"', response.body
    assert_no_match 'target="hq-wizard-signal"', response.body
    assert_equal original, @subject.reload.camp_location
  end

  # --- Emergency contact step ----------------------------------------------

  test "the emergency contact step hides the field from unauthorized operators" do
    get hq_site_registration_path(@subject)

    assert_response :success
    assert_match "Emergency Contact Info Is Off Limits During the Off Season", response.body
    assert_select "textarea[name=?]", "person[emergency_contact]", count: 0
    assert_select "form[action=?]", hq_site_registration_emergency_contact_path(@subject), count: 0
  end

  test "an emergency contact save is refused without the authorization" do
    original = @subject.emergency_contact

    patch hq_site_registration_emergency_contact_path(@subject),
          params: { person: { emergency_contact: "Someone New, Friend, 555-1234" } }

    assert_redirected_to hq_site_registration_path(@subject)
    assert_equal "You cannot update emergency contact information right now. " \
                 "Ranger operations must be running on playa.", flash[:error]
    assert_equal original, @subject.reload.emergency_contact
  end

  test "an operator with the edit emergency contact role can save the step" do
    ensure_role(Role::EDIT_EMERGENCY_CONTACT, "Edit Emergency Contact")
    grant_role(@viewer, Role::EDIT_EMERGENCY_CONTACT)

    patch hq_site_registration_emergency_contact_path(@subject),
          params: { person: { emergency_contact: "Someone New, Friend, 555-1234" } }

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'target="hq-step-emergency-contact"', response.body
    assert_match 'target="hq-wizard-signal"', response.body
    assert_match "Saved the emergency contact information.", response.body
    assert_equal "Someone New, Friend, 555-1234", @subject.reload.emergency_contact
  end

  # --- Radio check interstitial --------------------------------------------

  test "radio check confirms when an event radio is allowed but none is out" do
    authorize_subject_for_event_radios

    get hq_site_registration_radio_check_path(@subject), as: :turbo_stream

    assert_response :success
    assert_match 'target="modal"', response.body
    assert_match "No Event Radios Checked Out", response.body
    assert_match "data-hq-wizard-confirm", response.body
    assert_no_match 'target="hq-wizard-signal"', response.body
  end

  test "radio check advances when a radio is already checked out" do
    authorize_subject_for_event_radios
    PersonAsset.create!(person_id: @subject.id, asset_id: asset(:radio_current_year).id,
                        checked_out: Current.time)

    get hq_site_registration_radio_check_path(@subject), as: :turbo_stream

    assert_response :success
    assert_match 'target="hq-wizard-signal"', response.body
    assert_match "data-hq-wizard-target=\"advance\"", response.body
    assert_no_match "No Event Radios Checked Out", response.body
  end

  test "radio check advances when the person is not allowed an event radio" do
    get hq_site_registration_radio_check_path(@subject), as: :turbo_stream

    assert_response :success
    assert_match 'target="hq-wizard-signal"', response.body
    assert_no_match "No Event Radios Checked Out", response.body
  end

  # --- Mark on site ---------------------------------------------------------

  test "marking on site sets the flag and redirects to the success state" do
    assert_not @subject.on_site

    assert_difference -> { PersonOnSite.where(person_id: @subject.id).count }, 1 do
      post hq_site_registration_on_site_path(@subject)
    end

    assert_redirected_to hq_site_registration_path(@subject)
    assert_equal "#{@subject.callsign} is now marked on site.", flash[:success]
    assert @subject.reload.on_site
    row = PersonOnSite.where(person_id: @subject.id).last
    assert_equal PersonOnSite::ON_SITE, row.action
    assert_equal @viewer.id, row.creator_person_id
  end

  private

  # Makes @subject radio-eligible with the Radio Checkout Agreement signed:
  # radio info posted, a usable event-radio provision, and asset_authorized on
  # the person event (upstream allowedEventRadio inputs).
  def authorize_subject_for_event_radios(item_count: 1)
    Setting.find_or_create_by(name: Setting::RADIO_INFO_AVAILABLE).update!(value: "true")
    Provision.create!(person_id: @subject.id, type: Provision::EVENT_RADIO,
                      status: Provision::AVAILABLE, is_allocated: false,
                      item_count: item_count, source_year: Current.year,
                      expires_on: "#{Current.year}-09-15")
    PersonEvent.first_or_new_for_person_year(@subject.id, Current.year)
               .update!(asset_authorized: true)
  end
end
