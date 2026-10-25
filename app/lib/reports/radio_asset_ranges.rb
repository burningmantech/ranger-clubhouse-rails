# frozen_string_literal: true

# Collapses a barcode-sorted radio roster into the contiguous blocks the cage
# issues in: "4061 - 4160, 100 radios, Event | EXP 9/2 12:00". (The
# "Summarize report" checkbox of the Ember reports/radio-assets page.)
#
# Upstream summarizes in the browser and miscounts while doing it: its running
# counter is bumped by the asset that BREAKS a run and then reset to zero for
# a run that already holds its first member, so the first range reports one
# too many and the last one too few. Counting the members of each run is both
# correct and less code, so that is what happens here.
#
# Every radio lands in exactly one range, so the counts always sum back to the
# roster -- duplicated and digitless barcodes stand alone rather than being
# dropped or merged.
class RadioAssetRanges
  # assets holds the members in barcode order; count is assets.size, stated
  # once so the table and the CSV export cannot disagree about it.
  BarcodeRange = Data.define(:label, :count, :description, :assets) do
    # Any member describes the whole range -- same_run? is what grouped them, so
    # they share a description and an event-or-shift assignment by construction.
    # Callers badge and label a range through the helpers that take an Asset,
    # which keeps "Event" and "Shift" spelled in exactly one place app-wide.
    def exemplar = assets.first
  end

  # @param assets [Array<Asset>] natural-sorted, as Asset.find_for_query returns them
  # @return [Array<BarcodeRange>]
  def self.build(assets)
    new(assets).build
  end

  def initialize(assets)
    @assets = Array(assets)
  end

  # Runs are found WITHIN a sequence rather than along the sorted roster.
  # Asset.natural_sort orders on [prefix, number, suffix], so two sequences that
  # share a prefix interleave -- 100, 100A, 101, 101A -- and a neighbour test
  # walking the sorted list would never pair 100 with 101. Grouping first, then
  # looking for consecutive numbers inside each group, finds both sequences.
  #
  # The ranges come back in roster order: each one sorts by where its first
  # member sits in the already-natural-sorted input.
  def build
    duplicated = duplicated_barcodes

    @assets.each_with_index
           .group_by { |asset, index| run_key(asset, index, duplicated) }
           .values
           .flat_map { |members| consecutive_runs(members) }
           .sort_by { |members| members.first.last }
           .map { |members| range_for(members.map(&:first)) }
  end

  private

  # Everything a range states about its members, plus the two things that make
  # their numbers comparable at all. Prefix and suffix are folded exactly as
  # Asset.natural_barcode_key folds them, so this class and the sort it relies
  # on agree about what counts as one sequence.
  #
  # Digit width joins the key because 0099 and 100 are not neighbours in any
  # sense a reader would act on: the cage stocks a padded sequence or an
  # unpadded one, and a range labelled "0098 - 101" describes neither.
  def run_key(asset, index, duplicated)
    segments = segment(asset.barcode)
    # A barcode with no digits has no neighbour, and a duplicated one cannot be
    # placed in a sequence: swallowed into a run it becomes the last member of
    # one range and the first of the next, so the same barcode bounds two
    # blocks. Both stand alone, keyed by position so they never share a group.
    return [:alone, index] if segments.nil? || duplicated.include?(asset.barcode)

    [segments[:prefix], segments[:suffix], segments[:width],
     asset.description, asset.perm_assign?]
  end

  def duplicated_barcodes
    @assets.map(&:barcode).tally.filter_map { |barcode, count| barcode if count > 1 }.to_set
  end

  # Within a group every member already shares the description, the event-or-
  # shift assignment and the barcode shape, so only the number is left to test.
  # to_a because flat_map only flattens an Array, and chunk_while hands back an
  # Enumerator.
  def consecutive_runs(members)
    members.chunk_while { |(before, _), (after, _)|
      segment(after.barcode)[:number] == segment(before.barcode)[:number] + 1
    }.to_a
  end

  # The model's own pattern, case-folded the way Asset.natural_barcode_key folds
  # it so RAD100 and rad101 are one sequence here exactly as they are one
  # sequence in the sort.
  def segment(barcode)
    matches = barcode.to_s.match(Asset::BARCODE_SEGMENT_PATTERN)
    return nil unless matches

    { prefix: matches[1].downcase, number: matches[2].to_i,
      width: matches[2].length, suffix: matches[3].downcase }
  end

  def range_for(members)
    BarcodeRange.new(label: label_for(members), count: members.size,
                     description: members.first.description, assets: members)
  end

  # Whole barcodes at both ends. Upstream prints the right-hand end without
  # its prefix mid-list ("SAND5100 - 5105") and with it on the final range, so
  # one report spells the same kind of range two different ways.
  def label_for(members)
    return members.first.barcode if members.one?

    "#{members.first.barcode} - #{members.last.barcode}"
  end
end
