# frozen_string_literal: true

require "test_helper"

# The Granted Through cell: a position's conditions belong to that position's
# item, and a status the paths do not explain gets a line that says why.
class Person::PermissionsHelperTest < ActionView::TestCase
  include IconHelper
  include UiComponents::UiIconItemHelper

  Path = PersonPermissionPresenter::Path
  Condition = PersonPermissionPresenter::Condition

  STALE_ACTIVE = "Still in effect from an earlier grant"
  STALE_INACTIVE = "Granted, but not in effect yet"

  test "a position's conditions nest inside the position's own item" do
    render_paths(row(active: false, paths: [unmet_position]))

    assert_select "ul.space-y-1 > li", text: /Position: HQ Window/ do
      assert_select "ul.ps-5 > li", text: "Not signed in to HQ Window"
    end
  end

  test "an active permission no current path confers is still in effect from an earlier grant" do
    render_paths(row(active: true, paths: [unmet_position]))
    assert_select "li", text: STALE_ACTIVE

    render_paths(row(active: true, paths: []))
    assert_select "li", text: STALE_ACTIVE
  end

  test "an inactive permission a path confers is granted but not in effect yet" do
    render_paths(row(active: false, paths: [Path.new(kind: :manual)]))
    assert_select "li", text: STALE_INACTIVE
  end

  test "the NDA, a setting or agreement between status and paths needs no such line" do
    manual = [Path.new(kind: :manual)]

    render_paths(row(active: false, paths: manual), nda_blocked: true)
    assert_select "li", text: STALE_INACTIVE, count: 0

    render_paths(row(active: false, paths: manual, off_setting: Setting::SHIFT_MANAGEMENT_SELF_ENABLED))
    assert_select "li", text: STALE_INACTIVE, count: 0

    render_paths(row(active: true, paths: manual))
    assert_select "li", text: /#{STALE_ACTIVE}|#{STALE_INACTIVE}/o, count: 0
  end

  private

  def render_paths(row, nda_blocked: false)
    render inline: "<%= permission_paths(row, nda_blocked:) %>", locals: { row:, nda_blocked: }
  end

  def row(active:, paths:, off_setting: nil)
    PersonPermissionPresenter::Row.new(title: "View Email", active:, paths:, off_setting:, off_setting_label: off_setting)
  end

  def unmet_position
    Path.new(kind: :position, title: "HQ Window",
             conditions: [Condition.new(met: false, text: "Not signed in to HQ Window")])
  end
end
