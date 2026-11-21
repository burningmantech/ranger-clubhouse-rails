# frozen_string_literal: true

require "test_helper"

class Ticketing::TrsFormatsHelperTest < ActionView::TestCase
  include ButtonHelper
  include IconHelper

  test "a placed row's control is named by its number and index, and carries the patterns" do
    naming = trs_column_naming(2, label: "Source of column {n}", id: "trs-column-{i}-source")

    assert_equal({ label: "Source of column 3" }, naming[:aria])
    assert_equal "trs-column-2-source", naming[:id]
    assert_equal({ form_rows_label: "Source of column {n}", form_rows_id: "trs-column-{i}-source" }, naming[:data])
  end

  test "the template's blank row carries the patterns alone" do
    naming = trs_column_naming(nil, label: "Source of column {n}", id: "trs-column-{i}-source")

    assert_nil naming[:aria][:label]
    assert_nil naming[:id]
    assert_equal({ form_rows_label: "Source of column {n}", form_rows_id: "trs-column-{i}-source" }, naming[:data])
    assert_equal({ form_rows_label: "Column {n} actions" }, trs_column_naming(nil, label: "Column {n} actions")[:data])
  end

  test "a column's source is a hidden key and a button that names it" do
    field = Nokogiri::HTML5.fragment(trs_column_source(7, "sap_0826")).at_css("[data-source-picker-target=field]")
    input = field.at_css("input[type=hidden]")
    button = field.at_css("button")

    assert_equal ["trs_format[row_sources][]", "sap_0826", "trs-column-7-source", "trs-column-{i}-source"],
                 %w[name value id data-form-rows-id].map { |name| input[name] }
    assert_equal ["button", "dialog", "source-picker#open"], %w[type aria-haspopup data-action].map { |name| button[name] }
    assert_equal "Source of column 8: Setup Access Pass · Aug 26", button.text.squish
    assert_equal "8", button.at_css(".sr-only [data-form-rows-number]").text
    assert_not_includes button.at_css("[data-source-picker-target=label]")["class"].split, "text-stone-muted"
    # Below lg a share of its cell, capped at the desktop width (the cell is grown by _column_row).
    assert_empty %w[w-72 max-lg:w-full max-lg:max-w-72] - button["class"].split
  end

  test "a column with no source says so, muted, and the template's row has no place yet" do
    unused = Nokogiri::HTML5.fragment(trs_column_source(0, nil))
    blank = Nokogiri::HTML5.fragment(trs_column_source(nil, nil))

    assert_equal "Not Used", unused.at_css("[data-source-picker-target=label].text-stone-muted").text
    assert_nil unused.at_css("input[type=hidden]")["value"]
    assert_nil blank.at_css("input[type=hidden]")["id"]
    assert_equal "", blank.at_css("[data-form-rows-number]").text
  end

  test "the picker's groups offer each source once, a credential and a pass for every day of August" do
    groups = trs_source_groups
    choices = groups.flat_map(&:choices)

    assert_equal [nil, "Person", "How Many of an Item", "Staff Credentials, by Access Date in August",
                  "Setup Access Passes, by Access Date in August"], groups.map(&:title)
    assert_equal [1, 6, 6, 32, 32], groups.map { |group| group.choices.size }
    assert_equal choices.size, choices.map(&:key).uniq.size
    assert_equal ["", "Not Used: Export This Column Empty", "Not Used"], choices.first.to_h.values_at(:key, :text, :label)
    assert_equal ["sap_anytime", "Any time", "Setup Access Pass · Any time"], groups.last.choices.first.to_h.values_at(:key, :text, :label)
    assert_equal ["sc_0801", "1", "Staff Credential · Aug 1"], groups[3].choices[1].to_h.values_at(:key, :text, :label)
    assert_equal ["sap_0831", "31", "Setup Access Pass · Aug 31"], groups.last.choices.last.to_h.values_at(:key, :text, :label)
    choices.drop(1).each { |choice| assert TrsExport.source?(choice.key), choice.key }
  end

  test "a date in another month that the format holds keeps a choice of its own" do
    groups = trs_source_groups(%w[first_name sc_0731 sap_0901 sap_0826 sap_0862 junk])

    assert_equal [1, 6, 6, 33, 33], groups.map { |group| group.choices.size }
    assert_equal ["sc_0731", "Jul 31", "Staff Credential · Jul 31"], groups[3].choices.last.to_h.values_at(:key, :text, :label)
    assert_equal ["sap_0901", "Sep 1", "Setup Access Pass · Sep 1"], groups.last.choices.last.to_h.values_at(:key, :text, :label)
  end

  test "a row button is an icon button that acts in the page and takes no tab stop by default" do
    button = Nokogiri::HTML5.fragment(
      trs_column_button("remove", 4, icon: "trash", title: "Delete column", label: "Delete column {n}")
    ).at_css("button")

    assert_equal "button", button["type"]
    assert_equal "form-rows#remove", button["data-action"]
    assert_equal "Delete column 5", button["aria-label"]
    assert_equal "Delete column {n}", button["data-form-rows-label"]
    assert_equal "Delete column", button["title"]
    assert_equal "-1", button["tabindex"]
    assert_includes button["class"].split, "btn-square"
    assert_not_includes button["class"].split, "invisible"
    assert_nil button["id"]
  end

  test "a hidden arrow is drawn invisible, and the row's tab stop is marked" do
    hidden = Nokogiri::HTML5.fragment(
      trs_column_button("up", 0, icon: "arrow-up", title: "Move up", label: "Move column {n} up", hidden: true)
    ).at_css("button")
    stop = Nokogiri::HTML5.fragment(
      trs_column_button("down", 0, icon: "arrow-down", title: "Move down", label: "Move column {n} down", tab_stop: true)
    ).at_css("button")

    assert_includes hidden["class"].split, "invisible"
    assert_equal "0", stop["tabindex"]
  end
end
