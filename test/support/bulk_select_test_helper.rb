# frozen_string_literal: true

# The select-all count arrives saying how many boxes the page ticks, so
# checkbox_select_all_controller.js has nothing to write into its live region
# on load. See UiComponents::BulkSelectHelper#bulk_select_count.
module BulkSelectTestHelper
  def assert_bulk_select_count_matches_ticked
    ticked = css_select("[data-checkbox-select-all-target=checkbox][checked]").size
    assert_select "[data-checkbox-select-all-target=count]", text: "#{ticked} selected"
  end
end
