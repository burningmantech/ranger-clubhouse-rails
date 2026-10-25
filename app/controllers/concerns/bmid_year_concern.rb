# frozen_string_literal: true

# The event year every BMID page is scoped to.
#
# The BMID namespace saves badges, and a badge is identified by person and
# year: an unvalidated year would write a real row that no year the page
# offers can ever list again. The floor is the first year the Clubhouse holds
# badges for; the year selectors read it back (min_year: year_floor), so the
# two cannot drift.
module BmidYearConcern
  extend ActiveSupport::Concern

  included do
    self.year_floor = 2017
    before_action :setup_year
  end
end
