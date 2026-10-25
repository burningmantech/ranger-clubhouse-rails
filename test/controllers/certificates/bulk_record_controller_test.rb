# frozen_string_literal: true

require "test_helper"

class Certificates::BulkRecordControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include DomIdTestHelper

  setup do
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @outsider = person(:inactive_ranger)
    @target = person(:auditor_ranger)
    @cert = certification(:cpr)

    ensure_role(Role::ADMIN, "Admin")
    grant_role(@admin, Role::ADMIN)

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  def cert_action(name = :cpr) = "cert-#{certification(name).id}"

  def preview_params(records, action: cert_action, reason: nil)
    { bulk_action: action, records:, reason: }.compact
  end

  # An existing record for the target, with all three fields already filled in
  # so a partial line has something to leave alone.
  def existing_record(**overrides)
    PersonCertification.create!({ person_id: @target.id,
                                  certification_id: @cert.id,
                                  card_number: "OLD-1",
                                  issued_on: "2020-01-01",
                                  trained_on: "2019-12-01" }.merge(overrides))
  end

  def recorded_for(person) = PersonCertification.find_by(person_id: person.id, certification_id: @cert.id)

  # ---------------------------------------------------------------- access

  test "an admin reaches the form" do
    get certificates_bulk_record_path

    assert_response :success
    assert_select "h1", /Bulk Record Certifications/
    assert_unique_dom_ids
  end

  test "someone without the admin role is turned away" do
    sign_in_as(@outsider)

    get certificates_bulk_record_path

    assert_redirected_to me_root_path
    assert_match(/admin role required/i, flash[:error])
  end

  # The list is built from the certification table rather than frozen in the
  # class, so the select is the only place that can prove it was.
  test "every certification is offered once, in title order" do
    get certificates_bulk_record_path

    assert_select "select[name=bulk_action] option[value=?]", cert_action(:cpr),
                  text: "Record/Update CPR cert."

    labels = css_select("select[name=bulk_action] option[value^='cert-']").map(&:text)
    assert_equal ["Record/Update CPR cert.",
                  "Record/Update Ham Radio License cert.",
                  "Record/Update Wilderness First Aid cert."], labels
  end

  # --------------------------------------------------------------- preview

  test "preview writes nothing" do
    assert_no_difference "PersonCertification.count" do
      post certificates_preview_bulk_record_path,
           params: preview_params("#{@target.callsign},2026-05-01,CARD-9,2026-04-01")
    end

    assert_response :unprocessable_entity
    assert_select "h1", /Record\/Update CPR cert\./
    assert_select "tbody tr", 1
    assert_unique_dom_ids
  end

  test "preview reports a certification no one holds yet as a change" do
    post certificates_preview_bulk_record_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will be applied/
  end

  test "preview names the fields and the values an existing record will have replaced" do
    existing_record

    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01,CARD-9")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Will replace/
    # The values, not just the field names: a column that landed in the wrong
    # field is only catchable if the row says what it read.
    assert_select "tbody tr td",
                  /Certification already exists\. Card number CARD-9 and issued on date 2026-05-01 will be updated\./
  end

  # Date.parse answers 2012-12-10 for "12345" rather than raising, so a card
  # number one dropped column away from its own advertised format used to be
  # recorded as an issue date, and the card number was never recorded at all.
  test "preview refuses a bare card number in the issued on column" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},12345")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Invalid issued on date/
    assert_select "tbody tr td", { text: /2012/, count: 0 }
  end

  test "preview still takes a compact ISO date" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},20260501")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Records issued on date 2026-05-01\./
  end

  test "preview reports a callsign-only line against an existing record as no change" do
    existing_record

    post certificates_preview_bulk_record_path, params: preview_params(@target.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Certification already exists\. Nothing to update\./
  end

  test "preview marks an unknown callsign as a problem" do
    post certificates_preview_bulk_record_path, params: preview_params("NotARealCallsign")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Callsign not found/
    # No confirm button: nothing on the list can be changed.
    assert_select "input[type=submit]", 1
  end

  test "preview marks a locked account as a problem and never writes to it" do
    locked = person(:deceased_ranger)

    post certificates_preview_bulk_record_path, params: preview_params(locked.callsign)

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /account is locked/i
    assert_select "input[type=submit]", 1
  end

  # ---------------------------------------------------- unusable line data

  test "preview refuses a bad issued on date" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},not-a-date")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Invalid issued on date/
    assert_select "input[type=submit]", 1
  end

  test "preview refuses a bad trained on date" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01,CARD-9,not-a-date")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Invalid trained on date/
  end

  test "preview refuses a line carrying a fourth field" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01,CARD-9,2026-04-01,extra")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /at most three fields/
  end

  # A blank column means "leave that field alone", so a line that is nothing but
  # separators is a bare callsign and not three empty fields.
  test "preview reads a line of empty columns as a callsign on its own" do
    existing_record

    post certificates_preview_bulk_record_path, params: preview_params("#{@target.callsign},,,")

    assert_response :unprocessable_entity
    assert_select "tbody tr td", /Nothing to update/
  end

  test "preview counts a callsign listed twice once" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign}\n#{@target.callsign}")

    assert_response :unprocessable_entity
    assert_select "tbody tr", 2
    assert_select "tbody tr td", /Listed more than once/
  end

  test "preview re-posts everything the apply needs" do
    post certificates_preview_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01", reason: "spring class roster")

    assert_select "input[name=bulk_action][value=?]", cert_action(:cpr)
    assert_select "input[name=records][value=?]", "#{@target.callsign},2026-05-01"
    assert_select "input[name=reason][value=?]", "spring class roster"
  end

  test "preview refuses an empty list" do
    post certificates_preview_bulk_record_path, params: preview_params("   \n  ")

    assert_response :unprocessable_entity
    assert_match(/at least one callsign/i, flash[:error])
  end

  test "preview refuses an action the page does not offer" do
    post certificates_preview_bulk_record_path,
         params: preview_params(@target.callsign, action: "sandman_affidavit")

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # The handler raises on a certification that is not there, and this is why
  # that raise cannot be reached from a browser: the page only answers to ids
  # from the list it just built.
  test "preview refuses a certification id that does not exist" do
    post certificates_preview_bulk_record_path,
         params: preview_params(@target.callsign, action: "cert-999999")

    assert_response :unprocessable_entity
    assert_match(/choose an action/i, flash[:error])
  end

  # ----------------------------------------------------------------- apply

  test "apply creates the record and names who recorded it" do
    post certificates_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01,CARD-9,2026-04-01")

    assert_response :unprocessable_entity
    record = recorded_for(@target)
    assert_equal Date.new(2026, 5, 1), record.issued_on
    assert_equal "CARD-9", record.card_number
    assert_equal Date.new(2026, 4, 1), record.trained_on
    assert_equal @admin.id, record.recorder_id

    assert_select "[data-controller=scroll-to-top]"
    assert_select "body", /applied to 1 person/
    # The list survives the apply so a correction does not mean re-typing it.
    assert_select "textarea[name=records]", text: "#{@target.callsign},2026-05-01,CARD-9,2026-04-01"
  end

  test "apply updates only the fields the line supplied" do
    existing = existing_record(recorder_id: person(:echelon_ranger).id)

    post certificates_bulk_record_path, params: preview_params("#{@target.callsign},2026-05-01")

    record = recorded_for(@target)
    assert_equal existing.id, record.id
    assert_equal Date.new(2026, 5, 1), record.issued_on
    # Neither was on the line, so neither may be touched -- nothing on this page
    # can clear a value that is already recorded.
    assert_equal "OLD-1", record.card_number
    assert_equal Date.new(2019, 12, 1), record.trained_on
    assert_equal person(:echelon_ranger).id, record.recorder_id
  end

  test "apply writes nothing for a line with nothing to update" do
    existing_record

    assert_no_difference "PersonCertification.count" do
      post certificates_bulk_record_path, params: preview_params(@target.callsign)
    end

    assert_select "body", /Nothing was changed/
  end

  test "apply leaves a locked account alone" do
    locked = person(:deceased_ranger)

    post certificates_bulk_record_path, params: preview_params("#{@target.callsign}\n#{locked.callsign}")

    assert_nil recorded_for(locked)
    assert_select "body", /applied to 1 person/
  end

  test "apply logs one commit row naming every result" do
    post certificates_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01", reason: "spring class roster")

    log = ActionLog.where(event: "bulk-upload").last
    assert_equal "spring class roster", log.data["reason"]
    assert_equal cert_action(:cpr), log.data["action"]
    assert_equal @target.callsign, log.data["results"].first["callsign"]
    assert_equal "success", log.data["results"].first["status"]
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the list and the chosen certification" do
    post certificates_edit_bulk_record_path,
         params: preview_params("#{@target.callsign},2026-05-01", reason: "spring class roster")

    assert_response :unprocessable_entity
    assert_select "textarea[name=records]", text: "#{@target.callsign},2026-05-01"
    assert_select "select[name=bulk_action] option[selected][value=?]", cert_action(:cpr)
    assert_select "input[name=reason][value=?]", "spring class roster"
  end
end
