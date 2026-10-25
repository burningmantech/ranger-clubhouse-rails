# frozen_string_literal: true

require "test_helper"

class MenuHelperTest < ActionView::TestCase
  include MenuHelper

  setup do
    @person = person(:active_ranger)
    self.request = ActionDispatch::TestRequest.create
  end

  test "menu_resolve_path uses @person when use_person is true" do
    assert_equal person_path(@person), menu_resolve_path(:person_path, use_person: true)
  end

  test "menu_resolve_path raises when use_person is true and @person is missing" do
    @person = nil

    assert_raises(ArgumentError) do
      menu_resolve_path(:person_path, use_person: true)
    end
  end

  test "menu_uses_person reads the menu definition flag" do
    assert menu_uses_person?({ use_person: true, sections: [] })
    assert_not menu_uses_person?({ sections: [] })
  end

  test "menu_item_options removes menu-only metadata" do
    item = { title: "Schedule", path: :person_scheduling_path, active_prefix: true,
             description: "Mega-menu only", confirm: true, year_scoped: true, data: { turbo: false } }

    assert_equal({ data: { turbo: false } }, menu_item_options(item))
  end

  test "menu_resolve_path carries the request's year for year_scoped items" do
    self.request = ActionDispatch::TestRequest.create("QUERY_STRING" => "year=2024")

    assert_equal "/bmid/export?year=2024", menu_resolve_path(:bmid_export_path, year_scoped: true)
    assert_equal "/bmid/export", menu_resolve_path(:bmid_export_path)
  end

  # TrainingMenu paths are Strings, so the year is appended by hand -- and the
  # Trainer Resources item, flagged off on purpose, must stay yearless.
  test "menu_resolve_path carries the request's year onto year_scoped string paths" do
    self.request = ActionDispatch::TestRequest.create("QUERY_STRING" => "year=2024")
    green_dot = Position.new(id: Position::GREEN_DOT_TRAINING, title: "Green Dot Training")
    sessions, resources = TrainingMenu.definition(green_dot)[:sections].first[:items]

    assert_equal "/training/green-dot?year=2024", menu_resolve_path(sessions[:path], year_scoped: sessions[:year_scoped])
    assert_equal "/training/green-dot/resources", menu_resolve_path(resources[:path], year_scoped: resources[:year_scoped])
    assert_equal "/training/green-dot?tab=1&year=2024", menu_resolve_path("/training/green-dot?tab=1", year_scoped: true)
  end

  test "menu_resolve_path drops a missing or malformed year param" do
    assert_equal "/bmid/export", menu_resolve_path(:bmid_export_path, year_scoped: true)
    assert_equal "/training/green-dot", menu_resolve_path("/training/green-dot", year_scoped: true)

    self.request = ActionDispatch::TestRequest.create("QUERY_STRING" => "year=abc")
    assert_equal "/bmid/export", menu_resolve_path(:bmid_export_path, year_scoped: true)
  end

  test "menu_item_active? matches descendant routes when active_prefix is enabled" do
    request.path = "/person/238/schedule/sign-ups"

    assert menu_item_active?("/person/238/schedule", active_prefix: true)
    assert_not menu_item_active?("/person/238/schedule")
  end

  test "menu_item_active? does not match sibling route prefixes" do
    request.path = "/person/238/schedule-export"

    assert_not menu_item_active?("/person/238/schedule", active_prefix: true)
  end
end
