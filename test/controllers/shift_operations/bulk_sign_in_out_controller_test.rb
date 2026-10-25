# frozen_string_literal: true

require "test_helper"

class ShiftOperations::BulkSignInOutControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers

  YEAR = 2031

  setup do
    Rails.cache.clear
    Current.reset

    @now = Time.zone.local(YEAR, 8, 26, 12, 0, 0)
    travel_to @now

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TIMESHEET_MANAGEMENT, "Timesheet Management")

    @admin = person(:active_ranger)
    @ranger = person(:echelon_ranger)
    grant_role(@admin, Role::ADMIN)

    @position = positions(:ood_position)
    PersonPosition.find_or_create_by!(person_id: @ranger.id, position_id: @position.id)

    sign_in_as(@admin)
  end

  teardown do
    travel_back
    Current.reset
    Rails.cache.clear
  end

  def line(text) = { lines: text }

  def signed_in_line = "#{@ranger.callsign},#{@position.title}"

  # ---------------------------------------------------------------- access

  test "admin may open the page" do
    get shift_operations_bulk_sign_in_out_path

    assert_response :success
  end

  test "timesheet management may open the page" do
    grant_role(@ranger, Role::TIMESHEET_MANAGEMENT)
    sign_in_as(@ranger)

    get shift_operations_bulk_sign_in_out_path

    assert_response :success
  end

  test "a Ranger with neither role is turned away" do
    sign_in_as(@ranger)

    get shift_operations_bulk_sign_in_out_path

    assert_redirected_to me_root_path
  end

  test "a Ranger with neither role cannot commit either" do
    sign_in_as(@ranger)

    assert_no_difference "Timesheet.count" do
      post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)
    end

    assert_redirected_to me_root_path
  end

  # ------------------------------------------------------------------ form

  test "the form offers the line formats" do
    get shift_operations_bulk_sign_in_out_path

    assert_response :success
    assert_select "textarea[name=lines]"
    assert_select "*", text: /Supported Line Formats/
  end

  # --------------------------------------------------------------- preview

  test "preview shows what would happen and writes nothing" do
    assert_no_difference "Timesheet.count" do
      post shift_operations_preview_bulk_sign_in_out_path, params: line(signed_in_line)
    end

    assert_response :unprocessable_entity
    assert_select "*", text: /Nothing has been saved/
    assert_select "*", text: /#{Regexp.escape(@ranger.callsign)}/
  end

  test "the review row names the action inferred from the line's shape" do
    # The whole premise of this page is reading the action off the column
    # shapes, and nothing else asserts that the reader is shown which one it
    # picked. The row id comes from the view.
    Timesheet.create!(person: @ranger, position: @position, on_duty: @now - 3.hours,
                      additional_notes: "on duty")

    post shift_operations_preview_bulk_sign_in_out_path, params: line("#{@ranger.callsign},1130")

    assert_select "#preview-entry-0", text: /sign out/
  end

  test "preview names the problem on a bad line" do
    post shift_operations_preview_bulk_sign_in_out_path, params: line("nosuchranger,#{@position.title}")

    assert_response :unprocessable_entity
    assert_select "*", text: /callsign 'nosuchranger' not found/
  end

  test "preview refuses an empty list" do
    post shift_operations_preview_bulk_sign_in_out_path, params: line("")

    assert_response :unprocessable_entity
    assert_select "*", text: /Enter at least one line/
  end

  test "preview refuses a list of nothing but blank lines" do
    post shift_operations_preview_bulk_sign_in_out_path, params: line("\n   \n")

    assert_response :unprocessable_entity
    assert_select "*", text: /Enter at least one line/
  end

  # assert_select does not substitute a Regexp into an attribute selector -- it
  # matches the pattern's source as a literal and quietly finds nothing, which
  # makes the absence assertion below pass whether or not the button is there.
  # Both of these read the values instead.
  def submit_values = css_select("input[type=submit]").map { |element| element["value"] }

  test "a list with a problem offers no commit button" do
    post shift_operations_preview_bulk_sign_in_out_path, params: line("nosuchranger,#{@position.title}")

    assert_response :unprocessable_entity
    assert_not submit_values.any? { |value| value.start_with?("Create") },
               "all-or-nothing: a batch with a problem cannot be committed"
    assert_includes submit_values, "Go Back and Edit"
  end

  test "a clean list offers the commit button" do
    post shift_operations_preview_bulk_sign_in_out_path, params: line(signed_in_line)

    assert_response :unprocessable_entity
    assert_includes submit_values, "Create 1 timesheet entry"
  end

  # ----------------------------------------------------------------- apply

  test "apply creates the timesheet entry" do
    assert_difference "Timesheet.count", 1 do
      post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)
    end

    assert_response :unprocessable_entity
    entry = Timesheet.find_person_on_duty(@ranger.id)
    assert_not_nil entry
    assert_equal @position.id, entry.position_id
  end

  test "apply records the batch in the admin log" do
    assert_difference "ActionLog.where(event: 'bulk-sign-in-out').count", 1 do
      post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)
    end
  end

  test "the admin log records ids, not a copy of every Ranger in the batch" do
    post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)

    data = ActionLog.where(event: "bulk-sign-in-out").last.data.to_json
    processed = ActionLog.where(event: "bulk-sign-in-out").last.data["processed"].first

    assert_equal @ranger.id, processed["person_id"], "the id is what an audit trail needs"
    assert_not data.include?(@ranger.email),
               "an entry carries its Person so the table can link it -- serializing that " \
               "object would copy email, address and emergency contact into the log"
  end

  test "apply reports the outcome and clears the box" do
    post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)

    assert_select "*", text: /1 line applied/
    assert_select "textarea[name=lines]", text: ""
  end

  test "apply writes nothing at all when any line has a problem" do
    # The good line is deliberately first: a partial commit would create it
    # before reaching the bad one.
    lines = "#{signed_in_line}\nnosuchranger,#{@position.title}"

    assert_no_difference "Timesheet.count" do
      post shift_operations_apply_bulk_sign_in_out_path, params: line(lines)
    end

    assert_response :unprocessable_entity
    assert_select "*", text: /Nothing Has Been Saved/
  end

  test "apply re-checks the list rather than trusting the preview" do
    # Signed in between the preview and the commit, which is exactly the race a
    # re-parse at apply time exists to catch.
    post shift_operations_preview_bulk_sign_in_out_path, params: line(signed_in_line)
    Timesheet.create!(person: @ranger, position: @position, on_duty: @now - 1.hour,
                      additional_notes: "signed in elsewhere")

    assert_no_difference "Timesheet.count" do
      post shift_operations_apply_bulk_sign_in_out_path, params: line(signed_in_line)
    end

    assert_select "*", text: /is on duty/
  end

  test "apply refuses an empty list" do
    post shift_operations_apply_bulk_sign_in_out_path, params: line("")

    assert_response :unprocessable_entity
    assert_select "*", text: /Enter at least one line/
  end

  # ------------------------------------------------------------------ edit

  test "going back to edit keeps the pasted list" do
    post shift_operations_edit_bulk_sign_in_out_path, params: line(signed_in_line)

    assert_response :unprocessable_entity
    assert_select "textarea[name=lines]", text: signed_in_line
  end
end
