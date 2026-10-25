# frozen_string_literal: true

# Renderer-agnostic menu utilities shared by sidebar and navbar helpers.
#
# This module provides the core functionality for working with hash-based
# menu definitions. Specific renderers (sidebar, navbar) include this module
# and use its utilities to transform menu data into UI markup.
#

module MenuHelper
  # Build filtered menu from definition and context
  #
  # @param menu_definition [Hash] Menu definition with :sections key
  # @param context [Hash] Context with :person and :computed keys
  # @return [Array<Hash>] Filtered sections
  def menu_build(menu_definition, context)
    MenuBuilder.build(menu_definition, context)
  end

  # Check whether the menu definition resolves route helpers with @person.
  #
  # @param menu_definition [Hash] Menu definition
  # @return [Boolean]
  def menu_uses_person?(menu_definition)
    menu_definition[:use_person]
  end

  # Resolve a menu path (symbol or string) to a URL
  #
  # @param path [Symbol, String, nil] Route helper symbol or URL string
  # @param use_person [Boolean] When true, call the route helper with @person
  # @param year_scoped [Boolean] When true, carry the request's ?year= along
  # @return [String] Resolved URL
  def menu_resolve_path(path, use_person: false, year_scoped: false)
    return "" if path.nil?

    year = year_scoped ? menu_carried_year : nil
    unless path.is_a?(Symbol)
      return year ? "#{path}#{path.include?("?") ? "&" : "?"}year=#{year}" : path
    end

    args = use_person ? [menu_resolve_person] : []
    args << { year: } if year
    public_send(path, *args)
  end

  # Check whether a menu item should stay active for matching route prefixes.
  #
  # @param item [Hash] Menu item hash
  # @return [Boolean]
  def menu_item_active_prefix?(item)
    item[:active_prefix]
  end

  # Determine whether a menu item is active for the current request.
  #
  # @param path [String] Resolved URL
  # @param root [Boolean] When true, require an exact path match
  # @param active_prefix [Boolean, String, Symbol] When true, allow descendant
  #   paths to match. A String or route-helper Symbol matches THAT prefix
  #   instead of the item's own path -- for landing items whose siblings live
  #   underneath them (the training Sessions item claims only its session/
  #   subtree, so the Capacity sibling can win its own page).
  # @return [Boolean]
  def menu_item_active?(path, root: false, active_prefix: false)
    return false if path.blank? || request.blank?
    return true if current_page?(path)
    return false unless active_prefix

    menu_path_matches_prefix?(menu_active_prefix_path(path, active_prefix), root:)
  end

  # The path an item's active_prefix lights it under: its own for true, else the
  # String or route-helper Symbol it names. The sidebar hands the same one to
  # active_links_controller, so the server and the browser agree.
  def menu_active_prefix_path(path, active_prefix)
    (active_prefix == true) ? path : menu_resolve_path(active_prefix)
  end

  # Extract render options from item hash (removes menu-specific keys)
  #
  # @param item [Hash] Menu item hash
  # @return [Hash] Options suitable for passing to render helpers
  def menu_item_options(item)
    item.except(:title, :path, :visible_if, :sections, :submenu, :use_person, :active_prefix, :description, :confirm, :year_scoped)
  end

  # Confirm-dialog data attributes for items flagged with confirm: true.
  # Shared by the navbar and mega-menu renderers.
  #
  # @param item [Hash] Menu item hash
  # @return [Hash] Data attributes for confirm_modal handling
  def menu_item_confirm_data(item)
    confirm_modal(
      title: "Confirm #{item[:title]}",
      message: "#{item[:description]}?",
      method: :delete
    )
  end

  # Iterate sections recursively with block, yielding (section, depth)
  #
  # @param sections [Array<Hash>] Array of section hashes
  # @param depth [Integer] Current nesting depth (default: 0)
  # @yield [section, depth] Block to execute for each section
  def menu_each_section(sections, depth: 0, &block)
    sections.each do |section|
      yield section, depth
      menu_each_section(section[:sections] || [], depth: depth + 1, &block)
    end
  end

  # Check if a section has any content (items or nested sections)
  #
  # @param section [Hash] Section hash
  # @return [Boolean]
  def menu_section_has_content?(section)
    section[:items].present? || section[:sections].present?
  end

  private

  # The year navigating a year-scoped menu should preserve: the request's
  # ?year=, only when it is shaped like a real year. Range checks stay with
  # each page (see BmidYearConcern) — a menu link never invents a year, it
  # only carries forward one the current page already accepted.
  #
  # The all-years sentinel counts as such a value: pages that set
  # allow_all_years accept it, and dropping it reset exactly the scope
  # year_scoped exists to preserve. Pages that do not accept it coerce it to
  # the current year, which is what dropping it did anyway.
  def menu_carried_year
    year = request&.params&.dig("year").to_s
    year if year.match?(/\A\d{4}\z/) || year == PageLayoutHelper::ALL_YEARS
  end

  def menu_path_matches_prefix?(path, root: false)
    return false if root

    current_path = menu_path_for_matching(request.path.presence || request.fullpath)
    target_path = menu_path_for_matching(path)
    return false if current_path.blank? || target_path.blank?
    return current_path == target_path if target_path == "/"

    current_path == target_path || current_path.start_with?("#{target_path}/")
  end

  def menu_path_for_matching(path)
    path.to_s.split(/[?#]/, 2).first.presence
  end

  def menu_resolve_person
    @person || raise(ArgumentError, "Menu definition with use_person: true requires @person to be set")
  end
end
