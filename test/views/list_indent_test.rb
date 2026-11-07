# frozen_string_literal: true

require "test_helper"
require Rails.root.join("lib/css_matchers")

# A marker list -- list-disc or list-decimal -- indents by the ps-list-indent
# token and nothing else (docs/DESIGN-GUIDE.md > Spacing > Lists). A numeric
# indent beside the marker class puts the list back on a number of its own,
# which is how the app came to indent the same list 16, 20 or 24px by page;
# list-inside runs a wrapped line back under the bullet instead of hanging it
# from the text, and list-outside restates the default.
class ListIndentTest < ActiveSupport::TestCase
  MARKER = /\blist-(disc|decimal)\b/
  FORBIDDEN = /\A(?:(?:ms|ps|pl|ml)-\d+(?:\.\d+)?|list-inside|list-outside)\z/

  test "every marker list indents by ps-list-indent alone" do
    offenders = Dir.glob(Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")).sort.flat_map do |path|
      rel = Pathname(path).relative_path_from(Rails.root)
      File.foreach(path).with_index(1).flat_map do |line, number|
        line.scan(CssMatchers::CODE_STRING).filter_map do |_quote, classes|
          next unless classes.match?(MARKER)

          tokens = classes.split
          faults = tokens.grep(FORBIDDEN)
          faults << "no ps-list-indent" unless tokens.include?("ps-list-indent")
          "#{rel}:#{number} #{classes.inspect}: #{faults.join(", ")}" if faults.any?
        end
      end
    end

    assert_empty offenders, offenders.join("\n")
  end
end
