# frozen_string_literal: true

# Duplicate DOM ids are invalid HTML and a live hazard here: the application
# layout sets `turbo_refreshes_with method: :morph`, and Turbo's morph
# reconciles by id, so a repeated id can silently drop form fields on a
# refresh. The usual cause is a carry-along `hidden_field_tag :x` in one form
# defaulting its id from its name and colliding with a real `f.select :x` in a
# sibling form; the fix is `id: nil` on the hidden field.
module DomIdTestHelper
  def assert_unique_dom_ids
    ids = css_select("[id]").map { |element| element["id"] }
    duplicates = ids.tally.select { |_id, count| count > 1 }.keys

    assert_empty duplicates, "duplicate DOM ids on the page: #{duplicates.join(", ")}"
  end
end
