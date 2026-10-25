# frozen_string_literal: true

require "test_helper"

class Vc::ApplicationsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include ReportCardTestHelper # assert_report_card
  include ActiveSupport::Testing::TimeHelpers

  setup do
    travel_to Time.zone.local(2026, 4, 16, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @vc = person(:auditor_ranger)
    @plain = person(:ranger_with_custom_gender)
    @application = prospective_application(:pending_qualified)

    ensure_role(Role::VC, "Volunteer Coordinator")
    grant_role(@vc, Role::VC)

    ActionMailer::Base.deliveries.clear
  end

  teardown do
    Current.reset
    travel_back
    Rails.cache.clear
    ActionMailer::Base.deliveries.clear
  end

  test "requires the VC or Admin role" do
    sign_in_as(@plain)

    get vc_applications_path
    assert_redirected_to me_root_path

    get vc_application_path(@application)
    assert_redirected_to me_root_path
  end

  test "index lists the year's applications with dashboard counts" do
    sign_in_as(@vc)

    get vc_applications_path(year: 2026)

    assert_response :success
    assert_select "body", text: /Alice Applicant/
    assert_select "body", text: /Prospective Applications/
    # The index only filters, exports and links to an application: a report.
    assert_report_card
  end

  # The fixtures' applications are 2025's and 2026's.
  test "index says so for a year with no applications" do
    sign_in_as(@vc)

    get vc_applications_path(year: 2024)

    assert_response :success
    assert_select ".empty-state", text: "No applications have been imported for 2024."
  end

  test "a non-hash filter param is ignored rather than raising" do
    sign_in_as(@vc)

    ["filter=x", "filter[]=a&filter[]=b", "filter"].each do |query|
      get "#{vc_applications_path(year: 2026)}&#{query}"

      assert_response :success
      assert_select "body", text: /Alice Applicant/
    end
  end

  test "index filters by status group" do
    sign_in_as(@vc)

    get vc_applications_path(year: 2026, filter: { status: "_callsign" })

    assert_response :success
    assert_select "body", text: /Casey Callsign/
    assert_select "tbody", text: /Alice Applicant/, count: 0
  end

  test "index exports the applications it shows as CSV" do
    sign_in_as(@vc)
    pat = prospective_application(:pending_unqualified)

    # All statuses, under 18 only: the one 2026 applicant who is under 18.
    get vc_applications_path(year: 2026, filter: { status: "all", age: "young" })
    export_url = assert_select("a[href*='.csv']", count: 1).first["href"]

    get export_url

    assert_response :success
    assert_match "2026-prospective-applications.csv", response.headers["Content-Disposition"]
    assert_equal [
      "Application,Status,First Name,Last Name,Email,Assigned To,18 or Older,BRC Events,BRC Qualified,Last Updated",
      "A-#{pat.id},Awaiting Review,Pat,Pandemic,pat.pandemic@example.com,Unassigned,N,\"2020, 2021\",N,"
    ], response.body.split("\n")
  end

  test "show accepts an A- prefixed id" do
    sign_in_as(@vc)

    get vc_application_path("A-#{@application.id}")

    assert_response :success
    assert_select "body", text: /Alice Applicant/
    assert_select "body", text: /Looks solid so far/
    # Decision actions are native <details> dropdowns, one per group.
    assert_select "details.dropdown > summary", text: /Reject/
    assert_select "details.dropdown > summary", text: /Hold/
    assert_select "details.dropdown > summary", text: /Assign/
    assert_select "details.dropdown > summary", text: /Handle Actions/
  end

  test "show redirects with an error for an unknown application" do
    sign_in_as(@vc)

    get vc_application_path(999_999)

    assert_redirected_to vc_applications_path
  end

  test "update assigns the application and stamps the updater" do
    sign_in_as(@vc)

    patch vc_application_path(@application),
          params: { prospective_application: { assigned_person_id: @vc.id } }

    assert_redirected_to vc_application_path(@application)
    @application.reload
    assert_equal @vc.id, @application.assigned_person_id
    assert_equal @vc.id, @application.updated_by_person_id
  end

  test "update converts event year checkboxes into events_attended" do
    sign_in_as(@vc)

    patch vc_application_path(@application),
          params: { section: "details",
                    prospective_application: { event_years: ["2019", "2024"], is_over_18: "1" } }

    assert_redirected_to vc_application_path(@application)
    assert_equal [2019, 2024], @application.reload.all_events
  end

  test "personal info edit enforces required fields" do
    sign_in_as(@vc)

    patch vc_application_path(@application),
          params: { section: "personal_info",
                    prospective_application: { first_name: "Alice", last_name: "Applicant",
                                               email: "alice.applicant@example.com",
                                               street: "", city: "Example City", state: "NV",
                                               postal_code: "99999", country: "US",
                                               phone: "775 555 0100" } }

    assert_response :unprocessable_entity
    assert_equal "1 Example St", @application.reload.street
  end

  test "status endpoint records rejections and emails for more-handles" do
    sign_in_as(@vc)

    assert_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"], 1 do
      post status_vc_application_path(@application),
           params: { status: ProspectiveApplication::STATUS_MORE_HANDLES, message: "None were usable" }
    end

    assert_redirected_to vc_application_path(@application)
    @application.reload
    assert_equal ProspectiveApplication::STATUS_MORE_HANDLES, @application.status
    assert_equal "", @application.handles
    assert_equal ["Dusty Dawn", "Sparkle Pony"], @application.rejected_handles.first["handles"]
  end

  test "status endpoint sets the approved handle when approving" do
    sign_in_as(@vc)
    application = prospective_application(:handle_check)

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      post status_vc_application_path(application),
           params: { status: ProspectiveApplication::STATUS_APPROVED, approved_handle: "Moonbeam" }
    end

    application.reload
    assert_equal ProspectiveApplication::STATUS_APPROVED, application.status
    assert_equal "Moonbeam", application.approved_handle
    assert_includes ActionMailer::Base.deliveries.last.subject, "your Ranger Radio Handle has been approved!"
  end

  test "adjust status via update sends no email" do
    sign_in_as(@vc)

    assert_no_difference "ActionMailer::Base.deliveries.size" do
      patch vc_application_path(@application),
            params: { prospective_application: { status: ProspectiveApplication::STATUS_DUPLICATE } }
    end

    assert_equal ProspectiveApplication::STATUS_DUPLICATE, @application.reload.status
  end

  test "problem_review flags the paragraph and records a comment" do
    sign_in_as(@vc)

    assert_difference -> { @application.notes.count }, 1 do
      post problem_review_vc_application_path(@application), params: { message: "Single sentence only" }
    end

    @application.reload
    assert_equal ProspectiveApplication::WHY_VOLUNTEER_REVIEW_PROBLEM, @application.why_volunteer_review
    note = @application.notes.order(:created_at).last
    assert_equal ProspectiveApplicationNote::TYPE_VC_COMMENT, note.type
    assert_equal "Why Ranger Review: Single sentence only", note.note
  end

  test "preview_email renders the status email" do
    sign_in_as(@vc)

    get preview_email_vc_application_path(@application, status: ProspectiveApplication::STATUS_HOLD_AGE_ISSUE)

    assert_response :success
    assert_includes response.body, "under 18 years old"
  end

  test "send_email delivers a raw email and logs it" do
    sign_in_as(@vc)

    assert_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"], 1 do
      post send_email_vc_application_path(@application),
           params: { subject: "Hey Alice, question", message: "Just checking in." }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal "Hey Alice, question", mail.subject
    assert_equal ["alice.applicant@example.com"], mail.to
  end

  # The subject field has no limit and the mail log's column holds 255
  # characters. The email goes once with all of it, the audit entry keeps all
  # of it, and the mail log row keeps it cut.
  test "send_email with a subject longer than the mail log's column sends it once and logs it cut" do
    sign_in_as(@vc)
    subject = "x" * 300

    assert_difference ["MailLog.count", "ActionMailer::Base.deliveries.size"], 1 do
      post send_email_vc_application_path(@application), params: { subject:, message: "Just checking in." }
    end

    assert_equal subject, ActionMailer::Base.deliveries.last.subject
    assert_equal "#{"x" * 252}...", MailLog.where(prospective_application_id: @application.id).sole.subject
    emailed = ProspectiveApplicationLog.where(prospective_application_id: @application.id,
                                              action: ProspectiveApplicationLog::ACTION_EMAILED).sole
    assert_equal subject, emailed.data["subject"]
    assert_redirected_to vc_application_path(@application)
    assert_equal "Email sent.", flash[:success]
  end

  test "notes can be created, updated, and deleted" do
    sign_in_as(@vc)

    assert_difference -> { @application.notes.count }, 1 do
      post vc_application_notes_path(@application),
           params: { note: "New comment", type: ProspectiveApplicationNote::TYPE_VC_COMMENT }
    end

    note = @application.notes.order(:created_at).last
    patch vc_application_note_path(@application, note), params: { note: "Edited comment" }
    assert_equal "Edited comment", note.reload.note

    assert_difference -> { @application.notes.count }, -1 do
      delete vc_application_note_path(@application, note)
    end
  end

  test "destroy removes the application and its dependents" do
    sign_in_as(@vc)
    id = @application.id

    delete vc_application_path(@application)

    assert_redirected_to vc_applications_path(year: 2026)
    assert_not ProspectiveApplication.exists?(id)
    assert_equal 0, ProspectiveApplicationNote.where(prospective_application_id: id).count
    assert_equal 0, ProspectiveApplicationLog.where(prospective_application_id: id).count
  end

  test "search requires at least 3 characters" do
    sign_in_as(@vc)

    get search_vc_applications_path(query: "ab")

    assert_redirected_to vc_applications_path
  end

  test "search finds applications across years" do
    sign_in_as(@vc)

    get search_vc_applications_path(query: "alice.applicant@example.com")

    assert_response :success
    assert_select "body", text: /Alice Applicant/
  end

  test "extract_handles renders the review dialog with flagged handles" do
    sign_in_as(@vc)

    with_stubbed_extraction([["Dusty Dawn", []], ["Merde", ["French profanity."]]]) do
      post extract_handles_vc_application_path(@application)
    end

    assert_response :success
    assert_select "turbo-frame#modal"
    assert_includes response.body, "Dusty Dawn"
    assert_includes response.body, "French profanity."
  end

  test "a non-hash prospective_application param is refused rather than raising" do
    sign_in_as(@vc)

    patch vc_application_path(@application), params: { prospective_application: "x" }

    assert_response :bad_request
  end

  test "update persists problem handles submitted as JSON" do
    sign_in_as(@vc)

    patch vc_application_path(@application),
          params: { prospective_application: {
            handles: "Dusty Dawn\nMerde",
            problem_handles: [["Merde", ["French profanity."]]].to_json
          } }

    assert_redirected_to vc_application_path(@application)
    assert_equal [["Merde", ["French profanity."]]], @application.reload.problem_handles
  end

  test "problem handles that are not a JSON list are ignored rather than raising" do
    flagged = [["Merde", ["French profanity."]]]
    sign_in_as(@vc)
    patch vc_application_path(@application),
          params: { prospective_application: { handles: "Merde", problem_handles: flagged.to_json } }

    # A list or hash in place of the JSON string, then JSON that is not a list.
    [["x"], { a: "b" }, "5", "\"text\""].each do |value|
      patch vc_application_path(@application),
            params: { prospective_application: { handles: "Merde", problem_handles: value } }

      assert_redirected_to vc_application_path(@application), value.inspect
    end
    assert_equal flagged, @application.reload.problem_handles

    get vc_application_path(@application)
    assert_response :success
  end

  test "dialogs render into the modal frame" do
    sign_in_as(@vc)

    get dialog_vc_application_path(@application, dialog: "send_email")

    assert_response :success
    assert_select "turbo-frame#modal"
    assert_select "dialog"
  end

  private

  # Replace the Gemini call with a canned result for the duration of the block.
  def with_stubbed_extraction(result)
    original = AiHandlesExtract.method(:execute)
    AiHandlesExtract.define_singleton_method(:execute) { |_text| result }
    yield
  ensure
    AiHandlesExtract.define_singleton_method(:execute, original)
  end

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id: id)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id: role_id)
    RoleManager.purge_person(person.id.to_s)
  end
end
