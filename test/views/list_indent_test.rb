# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/css_matchers")

# A marker list is list-bulleted or list-numbered (components/lists.css): the
# marker plus the list-indent token in one class, and nothing else for the
# inline-start side (docs/DESIGN-GUIDE.md > Spacing > Lists). A raw list-disc
# or list-decimal puts the list back on an indent of its own, which is how the
# app came to indent the same list 16, 20 or 24px by page; list-inside runs a
# wrapped line back under the bullet instead of hanging it from the text.
class ListIndentTest < ActiveSupport::TestCase
  MARKER = /\blist-(bulleted|numbered|disc|decimal)\b/
  UTILITIES = %w[list-bulleted list-numbered].freeze
  FORBIDDEN = /\A(?:(?:ms|ps|pl|ml)-\d+(?:\.\d+)?|list-(?:disc|decimal|inside|outside))\z/

  test "every marker list is list-bulleted or list-numbered alone" do
    offenders = Dir.glob(Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")).sort.flat_map do |path|
      rel = Pathname(path).relative_path_from(Rails.root)
      File.foreach(path).with_index(1).flat_map do |line, number|
        line.scan(CssMatchers::CODE_STRING).filter_map do |_quote, classes|
          next unless classes.match?(MARKER)

          tokens = classes.split
          faults = tokens.grep(FORBIDDEN)
          faults << "no list-bulleted or list-numbered" unless tokens.intersect?(UTILITIES)
          "#{rel}:#{number} #{classes.inspect}: #{faults.join(", ")}" if faults.any?
        end
      end
    end

    assert_empty offenders, offenders.join("\n")
  end
end
