# frozen_string_literal: true

require_relative "timesheet_admin_test_helper"

# Fixtures grant no roles, and a Ranger with none is not offered the mega
# menu (MegaMenu.offered?): the two categories they can see are already the
# sidebar and the user dropdown. A test that opens the menu, or expects the
# bar to carry it, gives its person one role beyond those. Mentor unlocks the
# Mentoring category and nothing else the bar's tests measure (no search bar,
# no unread envelope).
module MegaMenuTestHelper
  include TimesheetAdminTestHelper

  def offer_mega_menu_to(person)
    ensure_role(Role::MENTOR, "Mentor")
    grant_role(person, Role::MENTOR)
  end
end
