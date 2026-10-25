# frozen_string_literal: true

# Menu Abstraction System - Builder Module
#
# Documentation: docs/MENUS.md
# AI Skill: ai/skills/menus/SKILL.md
#
# IMPORTANT: When modifying this file, update both documentation files.

module MenuBuilder
  # Handles visibility filtering for hash-based menu definitions.
  # Supports recursive multilevel submenus.

  module_function

  # Filter sections and items based on visibility rules (recursive)
  #
  # @param menu_definition [Hash] Menu definition with :sections key
  # @param context [Hash] Context with :person and :computed keys
  # @return [Array<Hash>] Filtered sections with only visible items
  def build(menu_definition, context)
    build_sections(menu_definition[:sections], context)
  end

  # Recursively build sections, handling nested sections
  #
  # @param sections [Array<Hash>] Array of section hashes
  # @param context [Hash] Context with :person and :computed keys
  # @return [Array<Hash>] Filtered sections
  def build_sections(sections, context)
    return [] if sections.blank?

    sections.filter_map do |section|
      next unless visible?(section, context)

      result = section.dup

      # Process nested sections (multilevel submenus)
      if section[:sections].present?
        visible_subsections = build_sections(section[:sections], context)
        next if visible_subsections.empty? && section[:items].blank?
        result[:sections] = visible_subsections
      end

      # Process items
      if section[:items].present?
        visible_items = build_items(section[:items], context)
        next if visible_items.empty? && result[:sections].blank?
        result[:items] = visible_items
      end

      # Skip if no content
      next if result[:items].blank? && result[:sections].blank?

      result
    end
  end

  # Build the visible items
  #
  # @param items [Array<Hash>] Array of item hashes
  # @param context [Hash] Context with :person and :computed keys
  # @return [Array<Hash>] Filtered items
  def build_items(items, context)
    return [] if items.blank?

    items.select { |item| visible?(item, context) }
  end

  # Check visibility conditions for an item or section
  #
  # Visibility conditions (all optional, combined with AND logic):
  #   :status - Array of Person status methods (OR logic within)
  #   :not_status - Array of Person status methods (ALL must return false)
  #   :roles - Array of Role constants (OR logic within)
  #   :computed - Symbol key for pre-computed context value
  #   :proc - Lambda/Proc receiving context
  #
  # @param item [Hash] Item or section hash with optional :visible_if key
  # @param context [Hash] Context with :person and :computed keys
  # @return [Boolean] True if item should be visible
  def visible?(item, context)
    rules = item[:visible_if]
    return true if rules.blank?

    person = context[:person]
    computed = context[:computed] || {}

    # Status check (OR logic - any match grants visibility)
    if rules[:status].present?
      return false unless rules[:status].any? { |m| person.send(m) }
    end

    # Not-status check (ALL must return false)
    if rules[:not_status].present?
      return false if rules[:not_status].any? { |m| person.send(m) }
    end

    # Role check (OR logic - any match grants visibility)
    if rules[:roles].present?
      return false unless rules[:roles].any? { |r| Current.has_role?(r) }
    end

    # Computed condition check
    if rules[:computed].present?
      return false unless computed[rules[:computed]]
    end

    if rules[:setting].present?
      return false unless Setting.get_value(rules[:setting])
    end

    # Custom proc check
    if rules[:proc].present?
      return false unless rules[:proc].call(context)
    end

    true
  end
end
