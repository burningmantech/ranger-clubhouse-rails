# frozen_string_literal: true

require "test_helper"

# One rule over every mega-menu category, because this bug was written three
# times before anyone noticed it once.
#
# MegaMenu.categories checks the category's own gate BEFORE it builds any
# section, so category and item gates are ANDed. Roles do not imply one another
# -- Current.has_role? is a set intersection -- so a category gate that does not
# cover an item's gate makes that item unreachable for everyone who holds the
# item's role and none of the category's. Nothing fails, nothing logs, and the
# page still answers for anyone who types its URL; it simply leaves the menu.
# Worse, PersonFavorite.prune_stale! then hard-deletes any favorite pointing at
# it, so the people shut out lose their bookmark too.
#
# Administration (Tech Ninja), People (Admin) and Volunteer Coordinator (Intake,
# Edit Handle Reservations, Salesforce Import) each shipped with this defect.
# All three dropped their category gate rather than growing a hand-kept union,
# which is the house answer -- but a category gate is still legitimate where
# every item admits exactly the same people, so this asserts the invariant
# instead of banning the gate outright.
#
# Data only: no person, no roles, no database. The question is whether the two
# gates can ever disagree, which is answered by reading the constants.
#
# TrainingMenu's categories are deliberately excluded. They are built per
# training position at request time, and their category gate is an intentional
# AND that mirrors Training::BaseController's own view gate.
class MenuCategoryGateTest < ActiveSupport::TestCase
  test "no category gate shuts out a reader one of its items admits" do
    offenders = []

    Menus::MEGA_CATEGORIES.each do |category|
      category_roles = category.dig(:visible_if, :roles)
      next if category_roles.blank?

      MegaMenu.each_item(category[:sections]) do |item|
        item_roles = item.dig(:visible_if, :roles)
        next if item_roles.blank?

        shut_out = item_roles - category_roles
        next if shut_out.empty?

        offenders << "#{category[:title]} > #{item[:title]}: " \
                     "#{role_names(shut_out)} may read the page but never see the item"
      end
    end

    assert_empty offenders,
                 "a category gate must cover every item gate inside it, or drop away and let each " \
                 "item gate itself:\n  #{offenders.join("\n  ")}"
  end

  private

  # Role ids alone make the failure a puzzle, and this only runs on the way to
  # a failure message.
  def role_names(role_ids)
    role_ids.map { |id| Role.constants.find { |name| Role.const_get(name) == id } || id }.join(", ")
  end
end
