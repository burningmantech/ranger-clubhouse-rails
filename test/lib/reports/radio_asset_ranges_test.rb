# frozen_string_literal: true

require "test_helper"

# The barcode-range summary behind Radio Assets > Summarized View: what counts
# as one run, and how many radios each run holds.
#
# The counts get their own cases because upstream gets them wrong. Its running
# counter is bumped by the asset that BREAKS a run and then reset to zero for a
# run that already holds its first member, so the first range of a list reports
# one radio too many and the last one too few, while the middle ranges come out
# right by accident. Ranges are built in memory from unsaved Assets -- nothing
# here touches the database.
class RadioAssetRangesTest < ActiveSupport::TestCase
  test "an empty roster produces no ranges" do
    assert_empty RadioAssetRanges.build([])
  end

  test "a run of consecutive barcodes collapses into one counted range" do
    ranges = build(%w[101 102 103 104])

    assert_equal 1, ranges.size
    assert_equal "101 - 104", ranges.first.label
    assert_equal 4, ranges.first.count
  end

  test "every range counts its own members, first and last included" do
    # Upstream reports 4 and 1 here: the first range is credited with the radio
    # that broke it, and the last is never credited with the one that started it.
    ranges = build(%w[101 102 103 201 202])

    assert_equal ["101 - 103", "201 - 202"], ranges.map(&:label)
    assert_equal [3, 2], ranges.map(&:count)
  end

  test "single radios stand alone and are labeled by their bare barcode" do
    ranges = build(%w[101 500 501 900])

    assert_equal ["101", "500 - 501", "900"], ranges.map(&:label)
    assert_equal [1, 2, 1], ranges.map(&:count)
  end

  test "the members of every range add up to the roster" do
    ranges = build(%w[101 102 103 201 202 400])

    assert_equal 6, ranges.sum(&:count)
    assert_equal 6, ranges.sum { |range| range.assets.size }
  end

  test "a prefixed range keeps its prefix at both ends" do
    # Upstream drops the prefix from the right-hand end of every range but the
    # last, so one report spells the same kind of range two ways.
    ranges = build(%w[SAND5108 SAND5109 SAND5110])

    assert_equal "SAND5108 - SAND5110", ranges.first.label
  end

  test "a change of prefix ends the run" do
    ranges = build(%w[100 101 SAND102 SAND103])

    assert_equal ["100 - 101", "SAND102 - SAND103"], ranges.map(&:label)
  end

  test "a change of suffix ends the run" do
    # 100A and 101A are one sequence; 101B belongs to another that happens to
    # interleave with it.
    ranges = build(%w[100A 101A 101B 102B])

    assert_equal ["100A - 101A", "101B - 102B"], ranges.map(&:label)
  end

  test "a duplicated barcode stands alone rather than bounding two ranges" do
    # Swallowed into a run, a duplicate ends one range and starts the next, so
    # the same barcode bounds two blocks -- 2014 renders 44 of these.
    ranges = build(%w[410 411 411 412])

    assert_equal %w[410 411 411 412], ranges.map(&:label)
    assert_equal [1, 1, 1, 1], ranges.map(&:count)
    endpoints = ranges.flat_map { |range| [range.assets.first.barcode, range.assets.last.barcode].uniq }
    assert_equal endpoints.uniq.size, endpoints.size - 1, "only the duplicate itself may repeat"
  end

  test "a barcode with no digits always stands alone" do
    # Natural-sorted: a digitless barcode sorts after every numbered one.
    ranges = build(%w[100 101 SPARE])

    assert_equal ["100 - 101", "SPARE"], ranges.map(&:label)
    assert_equal [2, 1], ranges.map(&:count)
  end

  test "two sequences sharing a prefix are found even though the sort interleaves them" do
    # natural_sort orders on [prefix, number, suffix], so these arrive
    # 100, 100A, 101, 101A, 102, 102A -- a neighbour test walking that list
    # would never pair 100 with 101.
    ranges = build(%w[100 100A 101 101A 102 102A])

    assert_equal ["100 - 102", "100A - 102A"], ranges.map(&:label)
    assert_equal [3, 3], ranges.map(&:count)
  end

  test "a run is case-insensitive, matching the sort it relies on" do
    ranges = build(%w[RAD100 rad101 RAD102])

    assert_equal ["RAD100 - RAD102"], ranges.map(&:label)
    assert_equal [3], ranges.map(&:count)
  end

  test "barcodes of different digit widths are separate sequences" do
    # "0098 - 101" describes neither the padded block nor the unpadded one.
    ranges = build(%w[0098 0099 100 101])

    assert_equal ["0098 - 0099", "100 - 101"], ranges.map(&:label)
    assert_equal [2, 2], ranges.map(&:count)
  end

  test "a change of description ends the run" do
    ranges = build_with([["100", "Event | EXP 9/2", true], ["101", "Event | EXP 9/2", true],
                         ["102", "Shift | EXP 9/1", true]])

    assert_equal ["100 - 101", "102"], ranges.map(&:label)
    assert_equal ["Event | EXP 9/2", "Shift | EXP 9/1"], ranges.map(&:description)
  end

  test "a change of event-versus-shift ends the run" do
    ranges = build_with([["100", "Ranger Event", true], ["101", "Ranger Event", true],
                         ["102", "Ranger Event", false]])

    assert_equal ["100 - 101", "102"], ranges.map(&:label)
    assert_equal [true, false], ranges.map { |range| range.exemplar.perm_assign? }
  end

  test "a NULL description groups like any other value" do
    ranges = build_with([["100", nil, true], ["101", nil, true], ["102", "Ranger Event", true]])

    assert_equal ["100 - 101", "102"], ranges.map(&:label)
    assert_nil ranges.first.description
  end

  private

  def build(barcodes)
    build_with(barcodes.map { |barcode| [barcode, "Ranger Event", true] })
  end

  def build_with(rows)
    assets = rows.map do |barcode, description, perm_assign|
      Asset.new(barcode:, description:, perm_assign:, type: Asset::TYPE_RADIO, year: 2024)
    end

    RadioAssetRanges.build(assets)
  end
end
