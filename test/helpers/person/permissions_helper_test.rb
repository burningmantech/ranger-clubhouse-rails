# frozen_string_literal: true

require "test_helper"

# The Granted Through cell: a position's conditions belong to that position's
# item. The Why It Is Inactive cell: the one reason that holds a permission off.
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
    render_reasons(row(active: false, paths: [Path.new(kind: :manual)]))
    assert_select "li", text: STALE_INACTIVE
  end

  test "the NDA or a setting is the reason, and needs no such line" do
    manual = [Path.new(kind: :manual)]

    render_reasons(row(active: false, paths: manual), nda_blocked: true)
    assert_select "li", text: "Sensitive Data Access and Use Policy not signed"
    assert_select "li", text: STALE_INACTIVE, count: 0

    render_reasons(row(active: false, paths: manual, off_setting: "Shift Management Self"))
    assert_select "li", text: "Shift Management Self setting is off"
    assert_select "li", text: STALE_INACTIVE, count: 0
  end

  test "an unmet condition is a reason under its position, a repeated path said once" do
    render_reasons(row(active: false, paths: [unmet_position, unmet_position]))

    assert_select "ul.space-y-1 > li", text: /Position: HQ Window/, count: 1 do
      assert_select "ul.ps-5 > li", text: "Not signed in to HQ Window"
    end
    assert_select "li", text: /Any one of these/, count: 0
  end

  test "a met condition is no reason" do
    met = Condition.new(met: true, text: "Passed or taught HQ Window Training")
    unmet = Condition.new(met: false, text: "Not signed in to HQ Window")
    render_reasons(row(active: false, paths: [Path.new(kind: :position, title: "HQ Window", conditions: [met, unmet])]))

    assert_select "li", text: unmet.text
    assert_select "li", text: met.text, count: 0
  end

  test "several blocked positions are offered as alternatives" do
    other = Path.new(kind: :position, title: "Gate", conditions: [Condition.new(met: false, text: "Not signed in to Gate")])
    render_reasons(row(active: false, paths: [unmet_position, other]))

    assert_select "ul.space-y-1 > li", text: "Any one of these would make it active:"
    assert_select "ul.ps-5 > li", count: 2
  end

  test "a setting does not hide the unmet condition that would still hold the permission off" do
    render_reasons(row(active: false, paths: [unmet_position], off_setting: "Shift Management Self"))

    assert_select "li", text: "Shift Management Self setting is off"
    assert_select "li", text: "Not signed in to HQ Window"
  end

  test "a row with nothing to explain it prints the dash" do
    render_reasons(row(active: false, paths: []))
    assert_equal "—", rendered.strip
  end


  test "agreement between status and paths adds no line to the paths" do
    render_paths(row(active: true, paths: [Path.new(kind: :manual)]))
    assert_select "li", text: /#{STALE_ACTIVE}|#{STALE_INACTIVE}/o, count: 0
  end

  private

  def render_paths(row)
    render inline: "<%= permission_paths(row) %>", locals: { row: }
  end

  def render_reasons(row, nda_blocked: false)
    render inline: "<%= permission_inactive_reasons(row, nda_blocked:) %>", locals: { row:, nda_blocked: }
  end

  def row(active:, paths:, off_setting: nil)
    PersonPermissionPresenter::Row.new(title: "View Email", active:, paths:, off_setting:, off_setting_label: off_setting)
  end

  def unmet_position
    Path.new(kind: :position, title: "HQ Window",
             conditions: [Condition.new(met: false, text: "Not signed in to HQ Window")])
  end
end
