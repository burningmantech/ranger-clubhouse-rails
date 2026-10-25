# frozen_string_literal: true

require "test_helper"

# BMID > Badge Titles: who may look, the CRUD around the list, and the Set BMID
# Titles preview and commit.
#
# BmidTitleAssignmentTest owns which badge gets which title; these tests cover
# the page around it -- the form's shape, and that what the admin picked is what
# gets written.
class Bmid::TitlesControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role
  include ActiveSupport::Testing::TimeHelpers
  include TicketingTestHelper

  YEAR = 2026

  setup do
    travel_to Time.zone.local(YEAR, 4, 8, 12, 0, 0)
    Rails.cache.clear
    Current.reset

    @admin = person(:active_ranger)
    @badger = person(:echelon_ranger)
    @outsider = person(:inactive_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::EDIT_BMIDS, "Edit BMIDs")
    grant_role(@admin, Role::ADMIN)
    grant_role(@badger, Role::EDIT_BMIDS)

    Bmid.delete_all
    BmidTitle.delete_all
    AccessDocument.delete_all
    PersonSlot.delete_all
    Slot.delete_all
    PersonPosition.delete_all

    @shift_lead = badge_title(Position::RSC_SHIFT_LEAD, line: 1, sort: 1, title: "Shift Lead")
    @double_oh = badge_title(Position::DOUBLE_OH_7, line: 3, sort: 1, title: "007")

    sign_in_as(@admin)
  end

  teardown do
    Current.reset
    Rails.cache.clear
    travel_back
  end

  # --- who may look ---------------------------------------------------------

  test "the list renders for an admin, one table per badge line" do
    get bmid_titles_path

    assert_response :success
    assert_match "Shift Lead", response.body
    # Lines 1 and 3 have a title; line 2 is empty and shows a table-less section.
    assert_select "table", 2
    assert_select "#bmid-title-line-1 tbody tr", 1
    assert_select "#bmid-title-line-2 table", 0
    assert_select "#bmid-title-line-3 tbody tr", 1
    assert_match "Nothing prints on this line yet", response.body
  end

  test "the list renders with only the edit BMIDs role" do
    sign_in_as(@badger)

    get bmid_titles_path

    assert_response :success
    assert_match "Shift Lead", response.body
  end

  test "every action is refused without the admin or edit BMIDs role" do
    sign_in_as(@outsider)

    [bmid_titles_path, new_bmid_title_path, edit_bmid_title_path(@shift_lead),
     set_bmid_titles_path].each do |path|
      get path

      assert_redirected_to me_root_path
      assert_equal "Admin or Edit BMIDs role required to manage BMIDs.", flash[:error]
    end

    post apply_bmid_titles_path
    assert_redirected_to me_root_path

    patch move_bmid_title_path(@shift_lead, direction: BmidTitle::MOVE_UP)
    assert_redirected_to me_root_path
    assert_equal 1, @shift_lead.reload.sort_index
  end

  # --- the list's CRUD ------------------------------------------------------

  test "a title is created" do
    post bmid_titles_path, params: {
      bmid_title: { title: "Department Manager", title_line: 1, sort_index: 2,
                    position_id: position_for(Position::DEPARTMENT_MANAGER).id }
    }

    assert_redirected_to bmid_titles_path
    title = BmidTitle.find_by(title: "Department Manager")
    assert_equal 1, title.title_line
    assert_equal 2, title.sort_index
  end

  test "a title that duplicates a position's line is refused with the form back" do
    post bmid_titles_path, params: {
      bmid_title: { title: "Second Helping", title_line: 1, sort_index: 9,
                    position_id: @shift_lead.position_id }
    }

    assert_response :unprocessable_entity
    assert_match "already earns a title on this line", response.body
    assert_nil BmidTitle.find_by(title: "Second Helping")
  end

  test "a title is updated" do
    patch bmid_title_path(@shift_lead), params: {
      bmid_title: { title: "Shift Lead", title_line: 1, sort_index: 7,
                    position_id: @shift_lead.position_id }
    }

    assert_redirected_to bmid_titles_path
    assert_equal 7, @shift_lead.reload.sort_index
  end

  test "a title is deleted" do
    delete bmid_title_path(@double_oh)

    assert_redirected_to bmid_titles_path
    assert_nil BmidTitle.find_by(id: @double_oh.id)
  end

  test "an empty list offers every line anyway" do
    BmidTitle.delete_all

    get bmid_titles_path

    assert_response :success
    assert_select "table", 0
    assert_select "#bmid-title-line-1, #bmid-title-line-2, #bmid-title-line-3", 3
  end

  # --- reordering a line ----------------------------------------------------

  test "a title is moved down its line" do
    second = badge_title(Position::OOD, line: 1, sort: 2, title: "Officer of the Day")

    patch move_bmid_title_path(@shift_lead, direction: BmidTitle::MOVE_DOWN)

    assert_redirected_to bmid_titles_path(anchor: "bmid-title-#{@shift_lead.id}")
    assert_equal ["Officer of the Day", "Shift Lead"], BmidTitle.where(title_line: 1).ordered.map(&:title)
    assert_equal 1, second.reload.sort_index
    assert_equal 2, @shift_lead.reload.sort_index
  end

  test "a title is moved up its line" do
    second = badge_title(Position::OOD, line: 1, sort: 2, title: "Officer of the Day")

    patch move_bmid_title_path(second, direction: BmidTitle::MOVE_UP)

    assert_equal ["Officer of the Day", "Shift Lead"], BmidTitle.where(title_line: 1).ordered.map(&:title)
  end

  test "moving past the end of a line just re-renders the list" do
    patch move_bmid_title_path(@shift_lead, direction: BmidTitle::MOVE_UP)

    assert_redirected_to bmid_titles_path(anchor: "bmid-title-#{@shift_lead.id}")
    assert_equal 1, @shift_lead.reload.sort_index
  end

  test "an unknown move direction changes nothing" do
    patch move_bmid_title_path(@shift_lead, direction: "sideways")

    assert_redirected_to bmid_titles_path
    assert_equal "A badge title can only be moved up or down.", flash[:alert]
    assert_equal 1, @shift_lead.reload.sort_index
  end

  test "the arrows stop at the ends of a line" do
    badge_title(Position::OOD, line: 1, sort: 2, title: "Officer of the Day")

    get bmid_titles_path

    # Two rows on line 1: the first cannot go up, the last cannot go down.
    assert_select "#bmid-title-line-1 a[href*=?]", "direction=up", 1
    assert_select "#bmid-title-line-1 a[href*=?]", "direction=down", 1
    # Line 3 has a single title, so it has no arrows to offer at all.
    assert_select "#bmid-title-line-3 a[href*=?]", "direction=", 0
  end

  # --- the Set BMID Titles preview ------------------------------------------

  test "the preview offers a picker per badge line, with the earned title chosen" do
    candidate

    get set_bmid_titles_path

    assert_response :success
    assert_select "tbody tr", 1
    assert_select "select[name=?]", "titles[#{@admin.id}-1]" do
      assert_select "option[selected][value=?]", "Shift Lead"
    end
    assert_select "select[name=?]", "titles[#{@admin.id}-2]"
    assert_select "select[name=?]", "titles[#{@admin.id}-3]"
    assert_select "input[name=?]", "custom_titles[#{@admin.id}-1]"
  end

  test "the preview marks titles the person does not hold" do
    candidate

    get set_bmid_titles_path

    assert_select "select[name=?]", "titles[#{@admin.id}-3]" do
      assert_select "option", text: /007 .*not held/
    end
  end

  test "the preview says so when no one qualifies" do
    get set_bmid_titles_path

    assert_response :success
    assert_match "No one holds a title-earning position", response.body
  end

  test "the preview says so when no titles are defined" do
    BmidTitle.delete_all

    get set_bmid_titles_path

    assert_response :success
    assert_match "No badge titles are defined", response.body
  end

  # --- the commit -----------------------------------------------------------

  test "the previewed titles are written and the results render at 422" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@admin.id}-1" => "Shift Lead", "#{@admin.id}-2" => "", "#{@admin.id}-3" => "" }
    }

    # Turbo drops a 200 form response, and a GET cannot re-derive the results.
    assert_response :unprocessable_entity
    assert_match "BMID Titles Set", response.body
    assert_equal "Shift Lead", Bmid.find_for_person_year(@admin.id, YEAR).title1
  end

  test "a custom title is taken from the box beside its picker" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@admin.id}-1" => Bmid::TitlesController::CUSTOM },
      custom_titles: { "#{@admin.id}-1" => "  Khaki  " }
    }

    assert_equal "Khaki", Bmid.find_for_person_year(@admin.id, YEAR).title1
  end

  test "a custom title longer than the badge column is trimmed to fit" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@admin.id}-1" => Bmid::TitlesController::CUSTOM },
      custom_titles: { "#{@admin.id}-1" => "x" * 100 }
    }

    assert_equal "x" * BmidTitle::TITLE_LIMIT, Bmid.find_for_person_year(@admin.id, YEAR).title1
  end

  test "a posted line the badge does not have is ignored" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@admin.id}-1" => "Shift Lead", "#{@admin.id}-4" => "Nowhere" }
    }

    assert_response :unprocessable_entity
    assert_equal "Shift Lead", Bmid.find_for_person_year(@admin.id, YEAR).title1
  end

  test "a posted row for someone the preview does not cover is ignored" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@outsider.id}-1" => "Sneaky" }
    }

    assert_response :unprocessable_entity
    assert_nil Bmid.find_for_person_year(@outsider.id, YEAR)
  end

  # A line the form did not manage to post falls back to what the position
  # earns, not to blank: a half-submitted form must not wipe titles.
  test "a malformed submission falls back to the title the position earns" do
    candidate

    post apply_bmid_titles_path, params: {
      titles: { "#{@admin.id}-1" => { nested: "junk" } }
    }

    assert_response :unprocessable_entity
    assert_equal "Shift Lead", Bmid.find_for_person_year(@admin.id, YEAR).title1
  end

  private

  def badge_title(position_id, line:, sort:, title:)
    BmidTitle.create!(position: position_for(position_id), title_line: line,
                      sort_index: sort, title:)
  end

  # The signed-in admin, holding a title-earning position and qualified for a
  # printed badge.
  def candidate
    PersonPosition.create!(person: @admin, position: position_for(Position::RSC_SHIFT_LEAD))
    document(@admin, type: AccessDocument::SPT, status: AccessDocument::CLAIMED)
  end
end
