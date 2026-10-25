# frozen_string_literal: true

require "test_helper"

class Hq::ShiftManageControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ActiveSupport::Testing::TimeHelpers
  include TimesheetAdminTestHelper

  setup do
    travel_to Time.zone.local(2026, 8, 30, 12, 0, 0)
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

    @subject.update_columns(on_site: true)

    sign_in_as(@viewer)
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
  end

  # --- Access gate ----------------------------------------------------------

  test "redirects away when the HQ Window Interface setting is off" do
    Setting.find_or_create_by(name: Setting::HQ_WINDOW_INTERFACE_ENABLED).update!(value: "false")

    get hq_shift_manage_path(@subject)

    assert_redirected_to person_path(@subject)
    assert_equal "The HQ Window Interface is not currently available.", flash[:error]
  end

  test "requires the admin or shift management permission" do
    sign_in_as(@subject)

    get hq_shift_manage_path(@viewer)

    assert_redirected_to me_root_path
  end

  test "renders the shift page with an unverified entry needing review" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_shift_manage_path(@subject)

    assert_response :success
    assert_select "details#hq-shift-section"
    assert_select "details#hq-assets-section"
    assert_select "details#hq-pogs-section"
    assert_select "details#hq-offsite-section"
    assert_select "tr[data-entry-id='#{entry.id}'][data-needs-review='true']"
    # Start Shift is withheld until the entry is reviewed or skipped.
    assert_select "div[data-hq-shift-target='startPanel'][hidden]"
  end

  # The "a different entry" actions sit below the current shift and OUTSIDE
  # #hq-verification. render_verification_update does
  # turbo_stream.update("hq-verification", ...), so anything left inside that
  # div is wiped the first time an entry is verified.
  test "the other-entry actions render outside the verification block" do
    create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_shift_manage_path(@subject)

    assert_response :success
    assert_select "a[href^=?]", hq_shift_manage_new_missing_request_path(@subject)
    assert_select "#hq-verification a[href^=?]",
                  hq_shift_manage_new_missing_request_path(@subject), count: 0
  end

  # --- Verification ---------------------------------------------------------

  test "verify marks the entry verified and the model writes the audit row" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    assert_difference -> { TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::VERIFY).count } do
      patch hq_shift_manage_verify_timesheet_path(@subject, entry.id)
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal Timesheet::STATUS_VERIFIED, entry.reload.review_status
    assert_match "hq-verification", response.body
    assert_match "hq-shift-signal", response.body
  end

  test "unverify marks the entry unverified and the model writes the audit row" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_VERIFIED)

    assert_difference -> { TimesheetLog.where(timesheet_id: entry.id, action: TimesheetLog::UNVERIFIED).count } do
      patch hq_shift_manage_unverify_timesheet_path(@subject, entry.id)
    end

    assert_response :success
    assert_equal Timesheet::STATUS_UNVERIFIED, entry.reload.review_status
  end

  # A just-verified entry stops being "needs review", so it only stays on screen
  # because its id rides along in `listed`. Without that the operator loses the
  # green banner and the Un-Verify button the moment they verify.
  test "a just-verified entry stays listed when its id rides along" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch hq_shift_manage_verify_timesheet_path(@subject, entry.id, listed: entry.id.to_s)

    assert_response :success
    assert_equal Timesheet::STATUS_VERIFIED, entry.reload.review_status
    assert_match(/data-entry-id="#{entry.id}"/, response.body,
                 "the verified entry must remain in the re-rendered list")
  end

  test "a verified entry drops off the list when it is not listed" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch hq_shift_manage_verify_timesheet_path(@subject, entry.id)

    assert_response :success
    assert_no_match(/data-entry-id="#{entry.id}"/, response.body)
  end

  # to_i read "#{id}x" as the id and kept that entry on the list.
  test "a listed value that is not an id keeps nothing on the list" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch hq_shift_manage_verify_timesheet_path(@subject, entry.id, listed: "abc,#{entry.id}x")

    assert_response :success
    assert_no_match(/data-entry-id="#{entry.id}"/, response.body)
  end

  # Guided flow folds a section down to its summary row, so that row is the only
  # thing the operator can see of it. Verifying the last entry also collapses the
  # shift section (the controller moves the flow on to Radios & Gear), so a row
  # left claiming "1 entry to review" would be the page's only visible statement
  # about a section — and it would be wrong.
  test "verifying an entry re-streams the section summary rows" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    patch hq_shift_manage_verify_timesheet_path(@subject, entry.id, listed: entry.id)

    assert_response :success
    assert_match "hq-shift-summary", response.body
    assert_match "hq-off-site-summary", response.body
    assert_no_match(/1 entry to review/, response.body,
                    "the summary must not still demand a review that just happened")
  end

  test "an entry still on duty cannot be verified" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED, off_duty: nil)

    patch hq_shift_manage_verify_timesheet_path(@subject, entry.id)

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal Timesheet::STATUS_UNVERIFIED, entry.reload.review_status
  end

  # --- Corrections ----------------------------------------------------------

  test "submitting a correction sets pending and the desired fields" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)
    desired = positions(:ood_position)

    patch hq_shift_manage_submit_correction_path(@subject, entry.id),
          params: { timesheet: { desired_position_id: desired.id,
                                 desired_off_duty: "2026-08-28 17:00:00",
                                 additional_notes: "Stayed the extra hour handling traffic." } }

    assert_redirected_to hq_shift_manage_path(@subject)
    entry.reload
    assert_equal Timesheet::STATUS_PENDING, entry.review_status
    assert_equal desired.id, entry.desired_position_id
  end

  test "the correction form renders as a modal turbo stream" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_shift_manage_correction_form_path(@subject, entry.id)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match 'turbo-stream action="update" target="modal"', response.body
    assert_match "hq-correction-modal", response.body
  end

  # --- Pogs -----------------------------------------------------------------

  test "creating a pog stamps the issuer and links the ended shift entry" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    assert_difference -> { PersonPog.count } do
      post hq_shift_manage_pogs_path(@subject),
           params: { person_pog: { pog: PersonPog::POG_MEAL, notes: "After the swing shift",
                                   timesheet_id: entry.id } }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    pog = PersonPog.order(:id).last
    assert_equal @subject.id, pog.person_id
    assert_equal @viewer.id, pog.issued_by_id
    assert_equal PersonPog::STATUS_ISSUED, pog.status
    assert_equal entry.id, pog.timesheet_id
    # The pog count also rides in the Meals & Showers summary row, which sits
    # outside #hq-pogs — without its own stream the folded row would still
    # claim "0 pogs recorded" after issuing one.
    assert_match "hq-pogs-summary", response.body
    assert_match "1 pog recorded", response.body
  end

  test "cancelling a pog requires a reason" do
    pog = PersonPog.create!(person_id: @subject.id, issued_by_id: @viewer.id,
                            pog: PersonPog::POG_MEAL)

    patch hq_shift_manage_update_pog_path(@subject, pog.id),
          params: { pog_op: "cancel", person_pog: { notes: "" } }

    assert_response :unprocessable_entity
    assert_equal PersonPog::STATUS_ISSUED, pog.reload.status

    patch hq_shift_manage_update_pog_path(@subject, pog.id),
          params: { pog_op: "cancel", person_pog: { notes: "Issued by accident" } }

    assert_response :success
    pog.reload
    assert_equal PersonPog::STATUS_CANCELLED, pog.status
    assert_equal "Issued by accident", pog.notes
  end

  test "only an issued half meal pog can be redeemed" do
    full = PersonPog.create!(person_id: @subject.id, issued_by_id: @viewer.id,
                             pog: PersonPog::POG_MEAL)

    patch hq_shift_manage_update_pog_path(@subject, full.id), params: { pog_op: "redeem" }

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal PersonPog::STATUS_ISSUED, full.reload.status

    half = PersonPog.create!(person_id: @subject.id, issued_by_id: @viewer.id,
                             pog: PersonPog::POG_HALF_MEAL)

    patch hq_shift_manage_update_pog_path(@subject, half.id), params: { pog_op: "redeem" }

    assert_response :success
    assert_equal PersonPog::STATUS_REDEEMED, half.reload.status
  end

  # The half-meal guard reads the setting, not an ivar: new_pog/create_pog never
  # run load_pogs, so keying off @half_pog_enabled made issuance always fail
  # while the button was on screen.
  test "a half meal pog can be issued while the setting is enabled" do
    Setting.find_or_create_by(name: Setting::MEAL_HALF_POG_ENABLED).update!(value: "true")
    Rails.cache.clear

    get hq_shift_manage_new_pog_path(@subject, pog: PersonPog::POG_HALF_MEAL)
    assert_response :success

    assert_difference "PersonPog.count", 1 do
      post hq_shift_manage_pogs_path(@subject),
           params: { person_pog: { pog: PersonPog::POG_HALF_MEAL, notes: "" } }
    end

    assert_equal PersonPog::POG_HALF_MEAL, PersonPog.order(:id).last.pog
  end

  test "a half meal pog is refused while the setting is disabled" do
    Setting.find_or_create_by(name: Setting::MEAL_HALF_POG_ENABLED).update!(value: "false")
    Rails.cache.clear

    assert_no_difference "PersonPog.count" do
      post hq_shift_manage_pogs_path(@subject),
           params: { person_pog: { pog: PersonPog::POG_HALF_MEAL, notes: "" } }
    end

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal "That pog type is not available right now. " \
                 "Reload the page and pick a pog button again.", flash[:error]
  end

  test "a non-hash person_pog param is refused like an empty one rather than raising" do
    assert_no_difference "PersonPog.count" do
      post hq_shift_manage_pogs_path(@subject), params: { person_pog: "x" }
    end
    assert_redirected_to hq_shift_manage_path(@subject)

    pog = PersonPog.create!(person_id: @subject.id, issued_by_id: @viewer.id, pog: PersonPog::POG_MEAL)

    patch hq_shift_manage_update_pog_path(@subject, pog.id), params: { person_pog: "x" }
    assert_response :unprocessable_entity

    patch hq_shift_manage_update_pog_path(@subject, pog.id), params: { pog_op: "cancel", person_pog: "x" }
    assert_response :unprocessable_entity
    assert_equal PersonPog::STATUS_ISSUED, pog.reload.status
  end

  # --- Missing timesheet request -------------------------------------------

  test "a missing timesheet request is created and stamped with the requester" do
    assert_difference "TimesheetMissing.count", 1 do
      post hq_shift_manage_missing_request_path(@subject), params: {
        timesheet_missing: {
          position_id: positions(:khaki_supervisor).id,
          on_duty: "2026-08-28 10:00:00", off_duty: "2026-08-28 16:00:00",
          additional_notes: "Forgot to sign in"
        }
      }
    end

    entry = TimesheetMissing.order(:id).last
    assert_equal @subject.id, entry.person_id
    assert_equal @viewer.id, entry.create_person_id
    assert_equal TimesheetMissing::STATUS_PENDING, entry.review_status
  end

  test "an invalid missing timesheet request re-renders the dialog" do
    assert_no_difference "TimesheetMissing.count" do
      post hq_shift_manage_missing_request_path(@subject), params: {
        timesheet_missing: {
          position_id: positions(:khaki_supervisor).id,
          on_duty: "2026-08-28 16:00:00", off_duty: "2026-08-28 10:00:00"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "modal", response.body
  end

  # --- Mark off site --------------------------------------------------------

  test "mark off site explicitly clears the flag" do
    assert_difference -> { PersonOnSite.where(person_id: @subject.id).count }, 1 do
      post hq_shift_manage_off_site_path(@subject)
    end

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal "#{@subject.callsign} is now marked off site.", flash[:success]
    assert_not @subject.reload.on_site
    row = PersonOnSite.where(person_id: @subject.id).last
    assert_equal PersonOnSite::OFF_SITE, row.action
    assert_equal @viewer.id, row.creator_person_id
  end

  # --- Asset checkout -------------------------------------------------------

  # Asset actions answer with a stream, never a redirect: the barcode field is
  # scanned repeatedly and a redirect would return the operator to the top of
  # the page, losing both the scroll position and the cursor, on every scan.
  test "checkout rejects an entity-assigned asset even with force" do
    asset = Asset.new(barcode: "HQENTITY1", type: Asset::TYPE_RADIO, year: 2026,
                      entity_assignment: "OSS Ops")
    asset.save!(validate: false)

    assert_no_difference -> { PersonAsset.count } do
      post hq_shift_manage_assets_path(@subject),
           params: { person_asset: { barcode: "HQENTITY1", force: "1" } },
           as: :turbo_stream
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "hq-assets-section", response.body
    assert_match(/assigned to OSS Ops/, response.body)
  end

  test "checking out a radio streams the section back and completes the radio task" do
    asset = Asset.create!(barcode: "HQRADIO1", type: Asset::TYPE_RADIO, year: Current.year,
                          perm_assign: false)

    assert_difference -> { PersonAsset.count }, 1 do
      post hq_shift_manage_assets_path(@subject),
           params: { person_asset: { barcode: "HQRADIO1" } },
           as: :turbo_stream
    end

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "hq-assets-section", response.body
    # The signal drives the checklist transition upstream applied in
    # onAssetCheckOut, and the barcode refocus the section replace destroyed.
    assert_match "hq-shift-signal", response.body
    assert_match "issue_radio", response.body
    assert_equal asset.id, PersonAsset.order(:id).last.asset_id
    # Guided flow folds every idle section, but the streamed one must come back
    # open: the barcode field lives inside it and the scan loop refocuses that
    # field after every checkout. A collapsed re-render would end the loop.
    assert_match(/<details[^>]+id="hq-assets-section"[^>]+open/, response.body)
  end

  test "checking a radio back in streams the section and completes the collect tasks" do
    asset = Asset.create!(barcode: "HQRADIO2", type: Asset::TYPE_RADIO, year: Current.year,
                          perm_assign: false)
    person_asset = PersonAsset.create!(person_id: @subject.id, asset_id: asset.id,
                                       checked_out: Current.time)

    patch hq_shift_manage_asset_check_in_path(@subject, person_asset), as: :turbo_stream

    assert_response :success
    assert_equal Mime[:turbo_stream], response.media_type
    assert_match "hq-assets-section", response.body
    assert_match "collect_radio", response.body
    assert_not_nil person_asset.reload.checked_in
  end

  # Upstream's onAssetCheckOut/onAssetCheckIn were both guarded on
  # `asset.type === TYPE_RADIO` and only ran after a successful write. The port
  # briefly signalled from the *current accounting* instead, so any asset action
  # on a person whose radios were all accounted for (collect_count == 0) marked
  # the collect tasks done — including "Collect Radio (if done rangering)" while
  # they still held an event radio.
  test "checking out a non-radio asset completes no radio task" do
    issue_event_radio!
    Asset.create!(barcode: "HQGEAR1", type: Asset::TYPE_GEAR, year: Current.year)

    post hq_shift_manage_assets_path(@subject),
         params: { person_asset: { barcode: "HQGEAR1" } },
         as: :turbo_stream

    assert_response :success
    assert_signals_completed ""
  end

  test "a failed barcode scan completes no radio task" do
    issue_event_radio!

    post hq_shift_manage_assets_path(@subject),
         params: { person_asset: { barcode: "NOSUCHBARCODE" } },
         as: :turbo_stream

    assert_response :success
    assert_match(/was not found/, response.body)
    assert_signals_completed ""
  end

  test "changing an attachment completes no radio task" do
    person_asset = issue_event_radio!

    patch hq_shift_manage_asset_update_attachment_path(@subject, person_asset),
          params: { person_asset: { attachment_id: "" } },
          as: :turbo_stream

    assert_response :success
    assert_signals_completed ""
  end

  # Checking a shift radio in while an event radio is still over the limit
  # leaves something to collect, so the collect chips must stay open.
  test "checking a radio in with collections outstanding completes no collect task" do
    @subject.update_columns(on_site: true)
    issue_event_radio!(barcode: "HQEVENT2")
    shift_radio = Asset.create!(barcode: "HQRADIO3", type: Asset::TYPE_RADIO,
                                year: Current.year, perm_assign: false)
    extra = Asset.create!(barcode: "HQRADIO4", type: Asset::TYPE_RADIO,
                          year: Current.year, perm_assign: false)
    PersonAsset.create!(person_id: @subject.id, asset_id: extra.id, checked_out: Current.time)
    person_asset = PersonAsset.create!(person_id: @subject.id, asset_id: shift_radio.id,
                                       checked_out: Current.time)

    patch hq_shift_manage_asset_check_in_path(@subject, person_asset), as: :turbo_stream

    assert_response :success
    assert_signals_completed ""
  end

  # --- Shift context round-trip (ctx_*) -------------------------------------

  # The Ember controller held the "a shift was just handled" state in memory;
  # the port carries it across the redirect in query params, so index must
  # re-validate every one of them against the database.
  test "start shift redirects back carrying the started context" do
    position = positions(:khaki_supervisor)
    PersonPosition.find_or_create_by!(person_id: @subject.id, position_id: position.id)

    # The fixture person has no training record, so check-in is blocked; the
    # forced path is the one HQ actually uses at the window, and it takes an
    # HQ Lead (Admin / Force Shift Start) to walk it.
    ensure_role(Role::CAN_FORCE_SHIFT, "Force Shift Start")
    grant_role(@viewer, Role::CAN_FORCE_SHIFT)

    post hq_shift_manage_shift_start_path(@subject),
         params: { position_id: position.id, force_sign_in: "1",
                   signin_force_reason: "HQ Lead override" }

    assert_redirected_to hq_shift_manage_path(@subject, ctx_shift: "started")
    assert Timesheet.where(person_id: @subject.id, off_duty: nil).exists?
  end

  # Only a successful transition may claim one happened. Keying the return path
  # off action_name meant a refused check-in still redirected with
  # ctx_shift=started — and when the refusal was "already on duty" the page then
  # showed the shift as freshly started, behind the error.
  test "a refused start shift does not redirect as though one had begun" do
    position = positions(:khaki_supervisor)
    PersonPosition.find_or_create_by!(person_id: @subject.id, position_id: position.id)
    create_timesheet!(review_status: Timesheet::STATUS_VERIFIED, off_duty: nil)

    post hq_shift_manage_shift_start_path(@subject), params: { position_id: position.id }

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal "#{@subject.callsign} is already on duty.", flash[:error]
  end

  test "a refused end shift does not redirect as though one had ended" do
    post hq_shift_manage_shift_end_path(@subject)

    assert_redirected_to hq_shift_manage_path(@subject)
    assert_equal "#{@subject.callsign} is not on duty.", flash[:error]
  end

  # Regression: the too-short interstitial dropped submit_correction, so
  # "End Shift & Submit Correction" on a short entry ended the shift with no
  # correction modal — exactly when a time correction is most likely.
  test "the too short modal carries the submit correction intent through" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_VERIFIED,
                              on_duty: 5.minutes.ago, off_duty: nil)

    post hq_shift_manage_shift_end_path(@subject),
         params: { entry_id: entry.id, submit_correction: 1 }

    assert_response :success
    assert_match "shift-too-short-modal", response.body
    assert_match(/submit_correction=1/, response.body,
                 "the confirm-and-end link must keep the correction intent")
  end

  test "the too short modal omits submit correction for a plain end shift" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_VERIFIED,
                              on_duty: 5.minutes.ago, off_duty: nil)

    post hq_shift_manage_shift_end_path(@subject), params: { entry_id: entry.id }

    assert_response :success
    assert_match "shift-too-short-modal", response.body
    assert_no_match(/submit_correction/, response.body)
  end

  test "the started context completes the start shift chip once the person is on duty" do
    create_timesheet!(review_status: Timesheet::STATUS_VERIFIED, off_duty: nil)

    get hq_shift_manage_path(@subject, ctx_shift: "started")

    assert_response :success
    assert_select "div[data-task='start_shift'][data-completed='true']"
  end

  # A hand-edited or stale URL must never claim a shift was handled.
  test "the started context is ignored when the person is not on duty" do
    get hq_shift_manage_path(@subject, ctx_shift: "started")

    assert_response :success
    assert_select "div[data-task='start_shift'][data-completed='true']", false,
                  "ctx_shift=started must not be trusted without an open entry"
    assert_select "div[data-task='start_shift'][data-completed='false']"
  end

  test "the ended context resolves the entry and completes the end shift chip" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_VERIFIED)

    get hq_shift_manage_path(@subject, ctx_shift: "ended", ctx_entry: entry.id)

    assert_response :success
    assert_select "div[data-task='end_shift'][data-completed='true']"
  end

  test "an ended context naming another person's entry is ignored" do
    other = Timesheet.new(person_id: @viewer.id, position_id: positions(:khaki_supervisor).id,
                          on_duty: Time.zone.local(2026, 8, 28, 10, 0, 0),
                          off_duty: Time.zone.local(2026, 8, 28, 16, 0, 0),
                          review_status: Timesheet::STATUS_VERIFIED)
    other.save!(validate: false)

    get hq_shift_manage_path(@subject, ctx_shift: "ended", ctx_entry: other.id)

    assert_response :success
    assert_select "div[data-task='end_shift'][data-completed='true']", false,
                  "ctx_entry must be scoped to the subject person"
  end

  test "an ended context with a correction flag opens the correction dialog inline" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_UNVERIFIED)

    get hq_shift_manage_path(@subject, ctx_shift: "ended", ctx_entry: entry.id,
                                       ctx_correction: "1")

    assert_response :success
    assert_select "#hq-correction-modal"
  end

  # Every in-page action targets a URL carrying the ctx params, so the operator's
  # visit state survives a barcode scan or a pog issued mid-review.
  test "in-page actions preserve the shift context in their targets" do
    entry = create_timesheet!(review_status: Timesheet::STATUS_VERIFIED)
    asset = Asset.create!(barcode: "HQCTX1", type: Asset::TYPE_RADIO, year: Current.year,
                          perm_assign: false)
    person_asset = PersonAsset.create!(person_id: @subject.id, asset_id: asset.id,
                                       checked_out: Current.time)

    get hq_shift_manage_path(@subject, ctx_shift: "ended", ctx_entry: entry.id)

    assert_response :success
    check_in = hq_shift_manage_asset_check_in_path(@subject, person_asset,
                                                   ctx_shift: "ended", ctx_entry: entry.id)
    assert_includes response.body, CGI.escapeHTML(check_in)
    assert_includes response.body,
                    CGI.escapeHTML(hq_shift_manage_new_pog_path(@subject, pog: PersonPog::POG_MEAL,
                                                                          ctx_shift: "ended",
                                                                          ctx_entry: entry.id))
  end

  private

  def issue_event_radio!(barcode: "HQEVENT1")
    asset = Asset.create!(barcode:, type: Asset::TYPE_RADIO, year: Current.year,
                          perm_assign: true)
    PersonAsset.create!(person_id: @subject.id, asset_id: asset.id, checked_out: Current.time)
  end

  # The signal beacon carries the completed chips as a comma-joined data-complete
  # attribute; "" means the action completed nothing.
  def assert_signals_completed(expected)
    assert_match(/id="hq-shift-signal"/, response.body)
    assert_match(/data-complete="#{Regexp.escape(expected)}"/, response.body,
                 "expected the signal to complete #{expected.presence || "nothing"}")
  end

  def create_timesheet!(review_status:,
                        position: positions(:khaki_supervisor),
                        on_duty: Time.zone.local(2026, 8, 28, 10, 0, 0),
                        off_duty: Time.zone.local(2026, 8, 28, 16, 0, 0))
    entry = Timesheet.new(person_id: @subject.id, position_id: position.id,
                          on_duty:, off_duty:, review_status:)
    entry.save!(validate: false)
    entry
  end
end
