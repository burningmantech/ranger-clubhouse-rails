# frozen_string_literal: true

require "test_helper"

# The shift types the Shift Coverage report offers: who may manage them, what
# the pages show, and what a save, a delete and a move do. The fixtures hold
# four of the twelve: command, echelon, hq and intercept, in that order.
class Admin::ShiftCoverageGroupsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper

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
    @position = Position.create!(title: "ZZ Probe Position", type: Position::TYPE_OTHER)

    # After the setup that writes, so no audit row of its own stands in for the
    # one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ----------------------------------------------------------- who may

  test "an admin sees the shift types in menu order, command first" do
    sign_in_as(@admin)

    get admin_shift_coverage_groups_path

    assert_response :success
    assert_select "h1", text: /Shift Coverage Management/
    assert_equal ["Command", "Echelon", "HQ Window", "Intercept"],
                 css_select("td[data-label='Shift Type'] a").map { |link| link.text.strip }
    assert_select "td[data-label='Period Positions']", text: "Position #2Position #120Position #142", count: 1
  end

  test "a tech ninja who is not an admin is admitted" do
    sign_in_as(@tech_ninja)

    get admin_shift_coverage_groups_path

    assert_response :success
  end

  test "someone with neither role is turned away, on every action" do
    sign_in_as(@outsider)

    get admin_shift_coverage_groups_path
    assert_redirected_to me_root_path
    assert_equal "Admin or Tech Ninja role required to manage shift coverage.", flash[:error]

    assert_no_difference "ShiftCoverageGroup.count" do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "probe", title: "Probe", base_position_ids: [@position.id] } }
      delete admin_shift_coverage_group_path(@command)
    end
    assert_redirected_to me_root_path
  end

  test "signed out, the page asks for a sign-in" do
    get admin_shift_coverage_groups_path

    assert_redirected_to root_path
  end

  # --------------------------------------------------------------- pages

  # A move button is btn-square, as wide as it is tall (36px), so the arrow of a
  # first or last row lines up with the rest instead of sitting 5px off.
  test "the index offers a move button to every row that has somewhere to go" do
    sign_in_as(@admin)

    get admin_shift_coverage_groups_path

    assert_select "a[title='Move down'].btn-square", count: 3, message: "all but the last"
    assert_select "a[title='Move up'].btn-square", count: 3, message: "all but the first"
  end

  test "the index says so when no shift type has been set up" do
    ShiftCoveragePosition.delete_all
    ShiftCoverageGroup.delete_all
    sign_in_as(@admin)

    get admin_shift_coverage_groups_path

    assert_response :success
    assert_select "*", text: /No shift types yet\. The Shift Coverage report has nothing to show/
  end

  test "a shift type's page lists its posts in column order, labels beside their positions" do
    [[91, "Troubleshooter"], [127, "Troubleshooter Mentee"], [147, "Troubleshooter LEAL"]].each do |id, title|
      Position.find_or_create_by!(id:) { |position| position.title = title }
    end
    sign_in_as(@admin)

    get admin_shift_coverage_group_path(@command)

    assert_response :success
    assert_select "h1", text: "Command"
    assert_select "dd", text: "Position #2Position #120Position #142"
    titles = css_select("td[data-label=Post]").map { |cell| cell.text.strip }
    assert_equal 18, titles.size
    assert_equal ["OOD", "Burn"], [titles.first, titles.last]
    assert_select "td[data-label=Positions]", text: /Troubleshooter Mentee\s*\(Mentee\)/
    assert_select "td[data-label=Shows]", text: /Headcount/, count: 4
  end

  # The report prints a number for a headcount post, never a label, so the page
  # that sets the post up does not show one either. The label stays stored.
  test "a headcount post's labels are not shown, though they are kept" do
    shift_coverage_position(:command_ts).update_columns(count_only: true)
    sign_in_as(@admin)

    get admin_shift_coverage_group_path(@command)

    assert_response :success
    assert_select "td[data-label=Positions]", text: /TSLEAL/, count: 0
    assert_equal [[91], [127, "Mentee"], [147, "TSLEAL"]], shift_coverage_position(:command_ts).reload.position_ids
  end

  # A position can be gone from a database without the page that lets an admin
  # fix the list failing with it.
  test "a position that is not in this database reads as its number" do
    sign_in_as(@admin)

    get admin_shift_coverage_group_path(@command)

    assert_response :success
    assert_select "td[data-label=Positions]", text: /Position #10\b/
  end

  # The form posts a blank ahead of its boxes, so that clearing every one still
  # arrives (and is refused) instead of reading as nothing sent.
  test "the form lists every position, inactive ones marked, behind a blank that survives a cleared list" do
    retired = Position.create!(title: "ZZ Retired", type: Position::TYPE_OTHER, active: false)
    sign_in_as(@admin)

    get new_admin_shift_coverage_group_path

    assert_response :success
    assert_select "input[type=hidden][name='shift_coverage_group[base_position_ids][]'][value='']", count: 1
    assert_select "label[for=base-position-#{@position.id}]", text: /ZZ Probe Position/
    assert_select "label[for=base-position-#{retired.id}]", text: /ZZ Retired \(inactive\)/
    assert_select "fieldset[aria-describedby=base-positions-help]", count: 1
  end

  test "a shift type's page offers Add Post by a name that holds its words, and edit and move per post" do
    sign_in_as(@admin)

    get admin_shift_coverage_group_path(@command)

    assert_select "a[href=?][aria-label='Add Post to Command']", new_admin_shift_coverage_group_post_path(@command),
                  text: "Add Post"
    assert_select "a[aria-label='Edit post OOD'][href=?]",
                  edit_admin_shift_coverage_group_post_path(@command, shift_coverage_position(:command_ood))
    assert_select "td[data-label=Actions] a[title='Move down'].btn-square", count: 17, message: "all but the last"
    assert_select "td[data-label=Actions] a[title='Move up'].btn-square", count: 17, message: "all but the first"
  end

  test "a shift type with no posts says so and points at Add Post" do
    ShiftCoveragePosition.where(shift_coverage_group_id: @command.id).delete_all
    sign_in_as(@admin)

    get admin_shift_coverage_group_path(@command)

    assert_response :success
    assert_select "*", text: /No posts in this shift type yet\. Add the first one\./
    assert_select "a[aria-label='Add Post to Command']"
  end

  test "the page carries no duplicate DOM ids" do
    sign_in_as(@admin)

    [admin_shift_coverage_groups_path, admin_shift_coverage_group_path(@command),
     new_admin_shift_coverage_group_path, edit_admin_shift_coverage_group_path(@command)].each do |path|
      get path

      assert_response :success, path
      assert_unique_dom_ids
    end
  end

  # ------------------------------------------------------------- create

  test "creating a shift type puts it last, stores its positions as integers and logs it" do
    sign_in_as(@admin)

    assert_difference "ShiftCoverageGroup.count", 1 do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "new-type", title: "New Type",
                                             base_position_ids: ["", @position.id.to_s] } }
    end

    group = ShiftCoverageGroup.find_by!(slug: "new-type")
    assert_redirected_to admin_shift_coverage_group_path(group)
    assert_equal "Shift type created.", flash[:success]
    assert_equal 8, group.sort_index
    assert_equal [@position.id], group.base_position_ids
    assert_equal ["shift-coverage-group-create"], ActionLog.pluck(:event)
  end

  # ---------------------------------------------------------- validation

  test "a slug of the wrong shape answers 422 with the reason and saves nothing" do
    sign_in_as(@admin)

    assert_no_difference "ShiftCoverageGroup.count" do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "Sneaky-Slug", title: "Probe", base_position_ids: [@position.id] } }
    end

    assert_response :unprocessable_entity
    assert_select "div[role=alert] span",
                  text: "The slug may hold only lowercase letters, numbers and single dashes between them."
  end

  test "a slug already in use answers 422" do
    sign_in_as(@admin)

    assert_no_difference "ShiftCoverageGroup.count" do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "command", title: "Again", base_position_ids: [@position.id] } }
    end

    assert_response :unprocessable_entity
    assert_select "div[role=alert] span", text: "Another shift type already uses that slug."
  end

  # The sentinel that arrives with every box cleared must reach the validation,
  # and the refusal is printed inside the Period Positions fieldset, where the
  # reader is looking, as well as in the summary above the form.
  test "every box cleared answers 422 and says so inside the fieldset" do
    sign_in_as(@admin)

    assert_no_difference "ShiftCoverageGroup.count" do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "empty", title: "Empty", base_position_ids: [""] } }
    end

    assert_response :unprocessable_entity
    assert_select "fieldset div[role=alert]", text: /Choose at least one period position\./
    assert_select "fieldset[aria-describedby~=base-positions-error]"
  end

  test "an id that is not an id is refused, not saved as an empty list" do
    sign_in_as(@admin)

    assert_no_difference "ShiftCoverageGroup.count" do
      post admin_shift_coverage_groups_path,
           params: { shift_coverage_group: { slug: "junk", title: "Junk", base_position_ids: ["abc"] } }
    end

    assert_response :unprocessable_entity
    assert_select "fieldset div[role=alert]", text: /Period position "abc" is not a position id\./
  end

  test "the form keeps what was ticked when a save is refused" do
    sign_in_as(@admin)

    post admin_shift_coverage_groups_path,
         params: { shift_coverage_group: { slug: "Bad Slug", title: "Kept Title", base_position_ids: [@position.id] } }

    assert_response :unprocessable_entity
    assert_select "input[name='shift_coverage_group[title]'][value='Kept Title']"
    assert_select "input[type=checkbox][id=base-position-#{@position.id}][checked]"
  end

  # ------------------------------------------------------ update, delete

  test "updating redirects to the shift type and logs the change" do
    sign_in_as(@tech_ninja)

    patch admin_shift_coverage_group_path(@command),
          params: { shift_coverage_group: { title: "Command Post", slug: "command",
                                            base_position_ids: [@position.id] } }

    assert_redirected_to admin_shift_coverage_group_path(@command)
    assert_equal "Command Post", @command.reload.title
    assert_equal [@position.id], @command.base_position_ids
    assert_equal ["shift-coverage-group-update"], ActionLog.pluck(:event)
  end

  test "a refused update names the shift type as stored, not as typed" do
    sign_in_as(@admin)

    patch admin_shift_coverage_group_path(@command),
          params: { shift_coverage_group: { title: "", slug: "command", base_position_ids: [@position.id] } }

    assert_response :unprocessable_entity
    assert_select "h1", text: "Edit Shift Type: Command"
    assert_equal "Command", @command.reload.title
  end

  test "deleting a shift type takes its posts with it" do
    sign_in_as(@admin)

    assert_difference({ "ShiftCoverageGroup.count" => -1, "ShiftCoveragePosition.count" => -18 }) do
      delete admin_shift_coverage_group_path(@command)
    end

    assert_redirected_to admin_shift_coverage_groups_path
    assert_equal "\"Command\" and its posts deleted.", flash[:success]
  end

  test "the edit page's delete button asks first and names what goes with the shift type" do
    sign_in_as(@admin)

    get edit_admin_shift_coverage_group_path(@command)

    assert_response :success
    # Within main: the navbar's logout link is a delete with a confirm of its own.
    assert_select "main a[data-turbo-method=delete][data-turbo-confirm]", text: "Delete Shift Type"
    confirm = css_select("main a[data-turbo-method=delete]").first["data-turbo-confirm"]
    assert_includes confirm, "Delete Command and its 18 posts?"
    assert_includes confirm, "btn-error", "the button that does the damage does not look like the safe default"
  end

  # --------------------------------------------------------------- order

  test "moving a shift type down swaps it with its neighbour" do
    sign_in_as(@admin)

    patch move_admin_shift_coverage_group_path(@command, direction: "down")

    assert_redirected_to admin_shift_coverage_groups_path
    assert_equal "The shift type order has been updated.", flash[:success]
    assert_equal %w[echelon command hq intercept], ShiftCoverageGroup.ordered.pluck(:slug)
  end

  test "moving the last shift type down says it is already there and changes nothing" do
    sign_in_as(@admin)

    patch move_admin_shift_coverage_group_path(shift_coverage_group(:intercept), direction: "down")

    assert_redirected_to admin_shift_coverage_groups_path
    assert_equal "\"Intercept\" is already at that end.", flash[:info]
    assert_equal %w[command echelon hq intercept], ShiftCoverageGroup.ordered.pluck(:slug)
  end
end
