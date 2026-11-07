# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/css_matchers")

# A marker list is list-bulleted or list-numbered (components/lists.css): the
# marker plus the list-indent token in one class, and nothing else for the
# inline-start side (docs/DESIGN-GUIDE.md > Spacing > Lists). A raw list-disc
# or list-decimal puts the list back on an indent of its own, which is how the
# app came to indent the same list 16, 20 or 24px by page; list-inside runs a
# wrapped line back under the bullet instead of hanging it from the text; and
# any margin or padding that reaches the inline-start side, at any breakpoint,
# fights the utility for it.
#
# Reads everywhere Tailwind compiles class strings from (the @source list in
# app/assets/tailwind/application.css), less the vendored Lexxy bundle that
# list excludes.
class ListIndentTest < ActiveSupport::TestCase
  SOURCES = %w[app/views app/helpers app/lib app/javascript config].freeze
  EXCLUDED = %r{\Aapp/javascript/vendor/}
  MARKER = /\blist-(bulleted|numbered|disc|decimal)\b/
  UTILITIES = %w[list-bulleted list-numbered].freeze
  RAW_MARKER = /\Alist-(disc|decimal)\z/
  # Judged on the utility part of a token, variants stripped: a margin or
  # padding that sets the inline-start side, with any value Tailwind takes, or
  # a marker-position or raw marker class.
  INLINE_START = /\A!?-?(?:m|p|ms|ps|ml|pl|mx|px)-(?:\d+(?:\.\d+)?|px|auto|\[[^\]]+\]|\([^)]+\))\z/
  FORBIDDEN = /\A!?list-(?:disc|decimal|inside|outside)\z/

  test "every marker list is list-bulleted or list-numbered alone" do
    offenders = source_files.flat_map do |path|
      rel = path.relative_path_from(Rails.root)
      File.foreach(path).with_index(1).flat_map do |line, number|
        line.scan(CssMatchers::CODE_STRING).filter_map do |_quote, classes|
          next unless classes.match?(MARKER)

          tokens = classes.split
          utilities = tokens.map { |token| CssMatchers.utility_part(token) }
          faults = tokens.select.with_index { |_token, i| utilities[i].match?(INLINE_START) || utilities[i].match?(FORBIDDEN) }
          unless utilities.intersect?(UTILITIES) || utilities.any? { |utility| utility.match?(RAW_MARKER) }
            faults << "no list-bulleted or list-numbered"
          end
          "#{rel}:#{number} #{classes.inspect}: #{faults.join(", ")}" if faults.any?
        end
      end
    end

    assert_empty offenders, offenders.join("\n")
  end

  private

  def source_files
    SOURCES.flat_map { |dir| Dir.glob(Rails.root.join(dir, "**/*.{erb,rb,js}")) }
           .map { |path| Pathname(path) }
           .reject { |path| path.relative_path_from(Rails.root).to_s.match?(EXCLUDED) }
           .sort
  end
end
