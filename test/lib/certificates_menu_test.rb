# frozen_string_literal: true

require "test_helper"

# The Certificates category, whose two items admit different people: recording
# certifications in bulk is an admin job, while reading the report is open to
# Certification Management as well.
#
# Worth its own test because both halves fail silently. The category carries no
# gate of its own, so each item has to carry one; drop an item's gate and every
# reader of the other item is handed it too.
class CertificatesMenuTest < ActiveSupport::TestCase
  include TimesheetAdminTestHelper

  BULK_RECORD = "Bulk Record Certifications"
  REPORT = "Certificates Report"

  setup do
    Rails.cache.clear
    Current.reset
    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::CERTIFICATION_MGMT, "Certification Management")
  end

  teardown do
    Current.reset
    Rails.cache.clear
  end

  # Resolved through the menu's own entry: a mistyped path symbol in the
  # definition is exactly what this guards.
  test "the report's menu item leads to the report" do
    linkable = MegaMenu.linkable_items(Menus::MEGA_CATEGORIES)

    assert_equal "/certificates/certificates-report",
                 linkable.find { |_path, item| item[:title] == REPORT }&.first
  end

  test "every role that may read the report sees it" do
    { Role::ADMIN => person(:active_ranger),
      Role::CERTIFICATION_MGMT => person(:echelon_ranger) }.each do |role_id, holder|
      Current.reset

      assert_includes titles_for(role_id, holder), REPORT,
                      "role #{role_id} reads the report but cannot see the menu item"
    end
  end

  # The positive half keeps the absence honest: with the category gone entirely
  # the list is empty and the negative assertion would pass for the wrong reason.
  test "a reader of the report is not offered the admin-only page" do
    titles = titles_for(Role::CERTIFICATION_MGMT, person(:echelon_ranger))

    assert_includes titles, REPORT
    assert_not_includes titles, BULK_RECORD
  end

  test "an admin sees both items" do
    titles = titles_for(Role::ADMIN, person(:active_ranger))

    assert_includes titles, BULK_RECORD
    assert_includes titles, REPORT
  end

  # The category disappears because every item in it is hidden. That only holds
  # while the items stay gated, so it is asserted rather than assumed.
  test "a reader with neither role is offered no Certificates category at all" do
    holder = person(:inactive_ranger)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    titles = MegaMenu.categories(person: holder, computed: {}).map { |entry| entry[:title] }

    assert_not_includes titles, "Certificates"
  end

  private

  # Menu role rules read Current.has_role?, which answers from the roles manager
  # rather than from Current.person -- setting the person alone leaves every
  # gated item invisible and every assertion here vacuously green.
  def titles_for(role_id, holder)
    grant_role(holder, role_id)
    Current.person = holder
    Current.roles_manager = RoleManager.retrieve(holder)

    category = MegaMenu.categories(person: holder, computed: {})
                       .find { |entry| entry[:title] == "Certificates" }
    return [] unless category

    category[:sections].flat_map { |section| section[:items].to_a.map { |item| item[:title] } }
  end
end
