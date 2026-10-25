# frozen_string_literal: true

# Navbar Dropdown Helper
#
# Renders menu definitions as dropdown menus for the top navigation bar.
# Uses the menu abstraction system from app/lib/menus/ and MenuHelper utilities.
#
# Documentation: docs/MENUS.md
module NavbarHelper
  include MenuHelper

  # Render menu sections as dropdown items with dividers between sections
  #
  # @param menu_definition [Hash] Menu definition with :sections key (e.g., Menus::ME)
  # @param context [Hash] Context with :person and :computed keys
  # @return [String] Rendered dropdown items HTML
  #
  # @example
  #   <%= dropdown_menu "Menu", class: "dropdown-end" do %>
  #     <%= navbar_render_menu(Menus::ME, @menu_context) %>
  #   <% end %>
  def navbar_render_menu(menu_definition, context)
    sections = menu_build(menu_definition, context)
    use_person = menu_uses_person?(menu_definition)

    parts = []
    sections.each_with_index do |section, index|
      parts << dropdown_divider if index.positive?
      parts.concat(navbar_render_section_items(section, context, use_person:))
    end
    safe_join(parts)
  end

  private

  # Render all items from a section (including nested sections)
  #
  # @param section [Hash] Section hash with :items and optional :sections keys
  # @param context [Hash] Context with :person and :computed keys
  # @return [Array<String>] Array of rendered dropdown items
  def navbar_render_section_items(section, context, use_person:)
    items = []
    items.concat(section[:items].map { |item| navbar_render_item(item, use_person:) }) if section[:items].present?

    # Handle nested sections (render their items inline with dividers)
    if section[:sections].present?
      section[:sections].each do |subsection|
        items << dropdown_divider if items.any?
        items.concat(navbar_render_section_items(subsection, context, use_person:))
      end
    end

    items
  end

  # Render a single menu item as a dropdown item
  #
  # @param item [Hash] Menu item hash with :title, :path, and optional attributes
  # @return [String] Rendered dropdown item HTML
  def navbar_render_item(item, use_person:)
    url = menu_resolve_path(item[:path], use_person:)
    options = menu_item_options(item)

    # Handle confirm modal for logout
    options[:data] = menu_item_confirm_data(item) if item[:confirm]

    dropdown_item(item[:title], url, **options)
  end

  # Platform-correct keyboard hint, in glyphs: Mac uses ⌘ for its command
  # key, every other platform uses ⌃ for control.
  #
  # ponytail: UA sniff rather than a client-side swap — the navbar is per-viewer
  # and never cached, so there is no stale glyph and no flash of the wrong keys.
  #
  # @param key [String] the non-modifier key, e.g. "K"
  # @param shift [Boolean] include the Shift modifier
  # @return [String] "⌘⇧K" on Mac, "⌃⇧K" elsewhere
  def kbd_shortcut(key, shift: false)
    "#{mac_client? ? "⌘" : "⌃"}#{"⇧" if shift}#{key}"
  end

  # Spoken modifier name for aria-label text — screen readers mangle "⌘".
  #
  # @return [String] "Cmd" on Mac, "Ctrl" elsewhere
  def kbd_modifier_name
    mac_client? ? "Cmd" : "Ctrl"
  end

  # Mac also covers iPadOS Safari, which reports itself as a Macintosh.
  def mac_client?
    request.user_agent.to_s.include?("Mac")
  end
end
