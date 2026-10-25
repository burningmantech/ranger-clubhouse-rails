# frozen_string_literal: true

require "test_helper"

# The posts of a shift type: the form's rows of position and label, what a save,
# a delete and a move do, and that a post is only ever reached through its own
# shift type. The fixtures hold command (18 posts), echelon (3), hq and intercept.
class Admin::ShiftCoveragePositionsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper

  ROWS = "shift_coverage_position[row_position_ids][]"
  LABELS = "shift_coverage_position[row_labels][]"

  setup do
    Rails.cache.clear

    @admin = person(:auditor_ranger)
    @tech_ninja = person(:echelon_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @command = shift_coverage_group(:command)
    @echelon = shift_coverage_group(:echelon)
    @ts = shift_coverage_position(:command_ts)

    # The positions the Command TS post reads, with the ids it names.
    [[91, "Troubleshooter"], [127, "Troubleshooter Mentee"], [147, "Troubleshooter LEAL"]].each do |id, title|
      Position.find_or_create_by!(id:) { |position| position.title = title }
    end

    # After the setup that writes, so no audit row of its own stands in for the
    # one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ------------------------------------------------------------- the rows

  test "the new post form draws four rows, each control with a label of its own" do
    sign_in_as(@admin)

    get new_admin_shift_coverage_group_post_path(@echelon)

    assert_response :success
    assert_select "select[name=?]", ROWS, count: 4
    assert_select "input[name=?][maxlength=20]", LABELS, count: 4
    4.times do |row|
      assert_select "label[for=post-row-#{row}-position]", text: "Position #{row + 1}"
      assert_select "label[for=post-row-#{row}-label]", text: "Label #{row + 1}"
      assert_select "select#post-row-#{row}-position[aria-describedby=post-positions-help]"
    end
    assert_unique_dom_ids
  end

  test "the edit form draws the rows the post has, with their labels, and two blank ones" do
    sign_in_as(@admin)

    get edit_admin_shift_coverage_group_post_path(@command, @ts)

    assert_response :success
    assert_select "select[name=?]", ROWS, count: 5
    assert_select "select#post-row-0-position option[selected][value=91]"
    assert_select "select#post-row-1-position option[selected][value=127]"
    assert_select "input#post-row-1-label[value=Mentee]"
    assert_select "select#post-row-2-position option[selected][value=147]"
    assert_select "select#post-row-3-position option[selected]", count: 0
    assert_unique_dom_ids
  end

  test "the positions are offered once each, inactive ones marked, grouped by team" do
    inactive = Position.create!(title: "ZZ Retired", type: Position::TYPE_OTHER, active: false)
    sign_in_as(@admin)

    get new_admin_shift_coverage_group_post_path(@echelon)

    assert_select "select#post-row-0-position option[value=?]", inactive.id.to_s, text: "ZZ Retired (inactive)"
    assert_select "select#post-row-0-position optgroup"
  end

  # ------------------------------------------------------------- create

  test "creating a post stores its positions and labels, joins the end, and logs it" do
    sign_in_as(@admin)

    assert_difference "ShiftCoveragePosition.count", 1 do
      post admin_shift_coverage_group_posts_path(@command),
           params: form_params(title: "TS 2", ids: ["91", "127", ""], labels: ["", "Mentee", ""])
    end

    created = ShiftCoveragePosition.find_by!(title: "TS 2")
    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "Post created.", flash[:success]
    assert_equal [[91], [127, "Mentee"]], created.position_ids
    assert_not created.count_only
    assert_equal 19, created.sort_index
    assert_equal @command, created.shift_coverage_group
    assert_equal ["shift-coverage-position-create"], ActionLog.pluck(:event)
  end

  test "a headcount post is saved as one" do
    sign_in_as(@admin)

    post admin_shift_coverage_group_posts_path(@echelon),
         params: form_params(title: "Count", count_only: "1")

    assert ShiftCoveragePosition.find_by!(title: "Count").count_only
  end

  # ---------------------------------------------------------- validation

  test "a label with no position answers 422, keeps what was typed, and marks the row" do
    sign_in_as(@admin)

    assert_no_difference "ShiftCoveragePosition.count" do
      post admin_shift_coverage_group_posts_path(@command),
           params: form_params(ids: ["91", ""], labels: ["", "Mentee"])
    end

    assert_response :unprocessable_entity
    assert_select "fieldset div[role=alert]", text: /The label "Mentee" needs a position beside it\./
    assert_select "input#post-row-1-label[value=Mentee]"
    assert_select "select#post-row-1-position[aria-invalid=true]"
    assert_select "input#post-row-1-label[aria-invalid=true]"
    assert_select "select#post-row-0-position[aria-invalid]", count: 0
    assert_select "fieldset[aria-describedby~=post-positions-error]"
    assert_select "select#post-row-0-position option[selected][value=91]", message: "the rows come back as sent"
  end

  # Which row each one marks is the model test's; the label test above checks
  # that the marking reaches the page.
  test "rows that cannot be saved answer 422 and say why inside the Positions fieldset" do
    sign_in_as(@admin)

    { %w[91 91] => /Troubleshooter is listed twice\. List each position once\./,
      %w[999999999] => /Position #999999999 does not exist\./,
      ["", ""] => /Choose at least one position for the post\./ }.each do |ids, message|
      assert_no_difference "ShiftCoveragePosition.count" do
        post admin_shift_coverage_group_posts_path(@command), params: form_params(ids:)
      end

      assert_response :unprocessable_entity, ids.inspect
      assert_select "fieldset div[role=alert]", text: message
    end
  end

  test "a title that is missing, too long or already in the shift type answers 422 with its message" do
    sign_in_as(@admin)

    { "" => "Enter a title for the post.",
      "T" * 21 => "The post title is too long. Use 20 characters or fewer.",
      "OOD" => "This shift type already has a post with that title." }.each do |title, message|
      assert_no_difference "ShiftCoveragePosition.count" do
        post admin_shift_coverage_group_posts_path(@command),
             params: form_params(title:)
      end

      assert_response :unprocessable_entity, title
      assert_select "div[role=alert] span", text: message
    end
  end

  # ------------------------------------------------------ update, delete

  test "updating changes the title and what the post shows, and logs the change" do
    sign_in_as(@tech_ninja)

    patch admin_shift_coverage_group_post_path(@command, @ts),
          params: form_params(title: "TS Renamed", count_only: "1", ids: ["91", "127"], labels: ["", "Mentee"])

    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "Post updated.", flash[:success]
    @ts.reload
    assert_equal "TS Renamed", @ts.title
    assert @ts.count_only
    assert_equal [[91], [127, "Mentee"]], @ts.position_ids
    assert_equal ["shift-coverage-position-update"], ActionLog.pluck(:event)
  end

  test "a refused update names the post as stored, not as typed" do
    sign_in_as(@admin)

    patch admin_shift_coverage_group_post_path(@command, @ts),
          params: form_params(title: "")

    assert_response :unprocessable_entity
    assert_select "h1", text: "Edit Post: TS"
    assert_equal "TS", @ts.reload.title
  end

  test "deleting a post leaves its shift type, and says what it is removed from" do
    sign_in_as(@admin)

    assert_difference "ShiftCoveragePosition.count", -1 do
      assert_no_difference "ShiftCoverageGroup.count" do
        delete admin_shift_coverage_group_post_path(@command, @ts)
      end
    end

    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "\"TS\" deleted.", flash[:success]
  end

  test "the edit page's delete button asks first, in the error colour" do
    sign_in_as(@admin)

    get edit_admin_shift_coverage_group_post_path(@command, @ts)

    assert_select "main a[data-turbo-method=delete][data-turbo-confirm]", text: "Delete Post"
    confirm = css_select("main a[data-turbo-method=delete]").first["data-turbo-confirm"]
    assert_includes confirm, "Delete TS? It is removed from the Command report."
    assert_includes confirm, "btn-error"
  end

  # --------------------------------------------------------------- order

  test "moving a post down swaps it with its neighbour inside its own shift type" do
    sign_in_as(@admin)
    ood = shift_coverage_position(:command_ood)

    patch move_admin_shift_coverage_group_post_path(@command, ood, direction: "down")

    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "The post order has been updated.", flash[:success]
    assert_equal %w[DOOD OOD RSL], @command.shift_coverage_positions.first(3).map(&:title)
  end

  test "moving the first post up says it is already there and changes nothing" do
    sign_in_as(@admin)
    ood = shift_coverage_position(:command_ood)

    patch move_admin_shift_coverage_group_post_path(@command, ood, direction: "up")

    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "\"OOD\" is already at that end.", flash[:info]
    assert_equal "OOD", @command.shift_coverage_positions.first.title
  end

  # ------------------------------------------------------ reached through

  test "another shift type's post answers 404 under this one's path, and nothing is edited" do
    sign_in_as(@admin)
    other = shift_coverage_position(:echelon_lead)

    get edit_admin_shift_coverage_group_post_path(@command, other)
    assert_response :not_found

    patch admin_shift_coverage_group_post_path(@command, other),
          params: form_params(title: "Hijacked")
    assert_response :not_found
    assert_equal "Echelon Lead", other.reload.title

    assert_no_difference "ShiftCoveragePosition.count" do
      delete admin_shift_coverage_group_post_path(@command, other)
    end
    assert_response :not_found
  end

  test "a shift type that does not exist answers 404" do
    sign_in_as(@admin)

    get new_admin_shift_coverage_group_post_path(0)

    assert_response :not_found
  end

  # ------------------------------------------------------------- who may

  test "a tech ninja who is not an admin is admitted" do
    sign_in_as(@tech_ninja)

    get new_admin_shift_coverage_group_post_path(@echelon)

    assert_response :success
  end

  test "someone with neither role is turned away, on every action" do
    sign_in_as(@outsider)

    get new_admin_shift_coverage_group_post_path(@echelon)
    assert_redirected_to me_root_path

    assert_no_difference "ShiftCoveragePosition.count" do
      post admin_shift_coverage_group_posts_path(@echelon),
           params: form_params
      delete admin_shift_coverage_group_post_path(@command, @ts)
    end
    assert_redirected_to me_root_path
  end

  private

  # The form as the browser sends it: a position and a label for each row.
  def form_params(title: "Probe", count_only: "0", ids: ["91"], labels: ids.map { "" })
    { shift_coverage_position: { title:, count_only:, row_position_ids: ids, row_labels: labels } }
  end
end
