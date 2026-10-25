# frozen_string_literal: true

require "test_helper"

# Rails ignores a locals: comment its STRICT_LOCALS_REGEX cannot parse, and the
# template then takes any locals (docs/css-dry-rules.md, Rung 3). A comment
# counts as one when it opens with "locals" or puts a paren after the word, so
# the capital "<%# Locals: presenter, person %>" some partials write as prose
# is left alone.
class StrictLocalsCommentTest < ActiveSupport::TestCase
  DECLARATION = /\A<%#\s*locals\b|(?i:\blocals\s*:?\s*\()/

  test "every locals comment under app/views is one Rails parses" do
    offenders = Dir.glob(Rails.root.join("app/views/**/*.erb")).flat_map do |path|
      File.read(path).scan(/<%#.*?%>/m)
          .grep(DECLARATION)
          .grep_v(ActionView::Template::STRICT_LOCALS_REGEX)
          .map { |tag| "#{Pathname(path).relative_path_from(Rails.root)}: #{tag}" }
    end

    assert_empty offenders, "Write it as <%# locals: (name:, other: default) %>, " \
                            "any note on a line of its own:\n#{offenders.join("\n")}"
  end
end
