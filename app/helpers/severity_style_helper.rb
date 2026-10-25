# frozen_string_literal: true

# How a table row says it needs attention: a background tint, and the matching
# emphasis for the figure that earned it.
#
# One table because the pairing is a design-system fact rather than any one
# page's choice -- a row that is red is red the same way everywhere. Pages keep
# their own words for what counts as bad and map them onto these.
module SeverityStyleHelper
  # The "!" is load-bearing. Striped tables set a background on alternating
  # rows, so without the override every other tinted row would lose its tint.
  # There is no bg-*-soft token; these are the real ones.
  SEVERITY_STYLES = {
    error: { row: "!bg-error/10", text: "text-error font-semibold" },
    warning: { row: "!bg-warning/10", text: "text-warning font-semibold" }
  }.freeze

  # Nil for anything with no severity, which is exactly the "no tint" a plain
  # row wants.
  def severity_style(severity, part)
    SEVERITY_STYLES.dig(severity, part)
  end
end
