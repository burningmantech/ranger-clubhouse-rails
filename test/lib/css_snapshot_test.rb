# frozen_string_literal: true

require "test_helper"

# bin/css_check is only as good as the masking: anything a page prints from the
# clock must read the same on every run. Day names used to survive in attribute
# values, so a title tooltip on a timestamp for "today" turned over at midnight,
# and an expiry twelve hours out turned over at noon.
class CssSnapshotTest < ActiveSupport::TestCase
  test "day and month names are masked in attribute values, as in text" do
    html = %(<span title="Sat Oct 3 @ 23:53 2026 (MST)" aria-label="Edit note from Jun 4, 2025">Sun Oct 4</span>)

    assert_equal <<~HTML, CssSnapshot.normalize(html, stream: true)
      <span aria-label="Edit note from D #, #" title="D D # @ #:# # (MST)">
        D D #
      </span>
    HTML
  end
end
