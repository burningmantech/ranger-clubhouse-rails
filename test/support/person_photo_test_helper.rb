# frozen_string_literal: true

# Shared setup for the VC photo controller tests: the people fixtures, the
# admin/VC/event-management roles, and a minimal photo factory.
# Requires AuthenticationTestHelper and TimesheetAdminTestHelper.
module PersonPhotoTestHelper
  def setup_photo_people_and_roles
    @target = person(:active_ranger)
    @admin = person(:auditor_ranger)
    @vc = person(:echelon_ranger)
    @em = person(:ranger_with_custom_gender)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::VC, "Volunteer Coordinator")
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")

    grant_role(@admin, Role::ADMIN)
    grant_role(@vc, Role::VC)
    grant_role(@em, Role::EVENT_MANAGEMENT)
  end

  def create_photo(person: @target, status: PersonPhoto::SUBMITTED, **attrs)
    PersonPhoto.create!(
      person:,
      status:,
      image_filename: "",
      orig_filename: "",
      profile_filename: "",
      **attrs
    )
  end
end
