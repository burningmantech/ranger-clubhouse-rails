# frozen_string_literal: true

require "test_helper"

class Person::StatusesHelperTest < ActionView::TestCase
  include ModalHelper
  include ButtonHelper
  include UiComponents::BadgeHelper
  include IconHelper

  # The whole point of the shared vocabulary is that no status falls through to
  # a per-page default, so every status the enum can hold has to land on a
  # standing on purpose.
  test "every assignable status is classified, and only active is the norm" do
    Person::ALL_STATUSES.each do |status|
      standing = person_status_standing(status)
      assert_includes [:norm, :pipeline, :reduced, :context], standing,
                      "#{status} fell through to :#{standing}"
    end
    assert_equal [Person::ACTIVE],
                 Person::ALL_STATUSES.select { |s| person_status_norm?(s) }
  end

  test "the norm prints as plain text and every other standing is a badge with an icon" do
    assert_equal "<span class=\"whitespace-nowrap\">active</span>", person_status_badge(Person::ACTIVE)
    assert_empty person_status_exception_badges(Person::ACTIVE)

    {
      Person::ALPHA => ["badge-primary", "fa-user-clock"],
      Person::INACTIVE => ["badge-warning", "fa-circle-pause"],
      Person::RETIRED => ["badge-secondary", "fa-circle-minus"],
      "deleted" => ["badge-error", "fa-triangle-exclamation"]
    }.each do |status, (variant, icon)|
      html = person_status_badge(status)
      assert_includes html, variant, status
      assert_includes html, icon, status
      assert_includes html, status, "the status word itself must print, unaltered"
    end
  end

  test "status_warning_modals_for returns modal markup keyed by new status" do
    modals = status_warning_modals_for(Person::ACTIVE)
    assert_equal StatusChangeWarnings::ACTIVE_WARNINGS.keys.sort, modals.keys.sort
    modals.each_value { |html| assert_includes html, "turbo-confirm-button" }
  end
end
