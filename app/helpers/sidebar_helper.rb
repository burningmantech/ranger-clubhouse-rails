# frozen_string_literal: true

# DaisyUI Sidebar/Drawer Helper
# Uses DaisyUI's native drawer component: https://daisyui.com/components/drawer/
#
# Menu Rendering:
#   Uses hash-based menu definitions from lib/menus/
#   See docs/MENUS.md for menu abstraction documentation
#
module SidebarHelper
  include MenuHelper

  # Sidebar utility class references
  SIDEBAR_NAV_ITEM = "sidebar-nav-item"
  SIDEBAR_SECTION_HEADER = "sidebar-section-header"

  # Theme configuration hash - colors from old_sidebar.scss
  THEME_CONFIGS = {
    me: {
      text: "text-sidebar-content",
      section_text: "text-sidebar-content",
      section_bg: "sidebar-group-title-default",
      item: "sidebar-link-default"
    },
    admin: {
      text: "text-sidebar-content",
      section_text: "text-sidebar-content",
      section_bg: "sidebar-group-title-hq",
      item: "sidebar-link-hq"
    },
    hq: {
      text: "text-sidebar-content",
      section_text: "",
      section_bg: "sidebar-group-title-default",
      item: "sidebar-link-default"
    }
  }.freeze

  # DaisyUI drawer-based sidebar menu
  # Options:
  #   :id - drawer id (default: 'sidebar-drawer')
  #   :width - drawer width class (default: 'w-65 lg:w-50')
  #
  # Theme options: 'me' (person theme), 'admin' (hq theme), 'default'
  def sidebar_menu(theme = "me", id: "sidebar-drawer", width: "w-65 lg:w-50", **_options, &block)
    content_for(:sidebar) do
      # z-50 matches the navbar: the mobile drawer is fixed at top:0 and is the
      # later sibling, so it paints over the navbar. At z-40 the navbar covered
      # the drawer's top 64px, close button included.
      # lg:h-full overrides DaisyUI's height:100dvh so the open sidebar fits
      # below the top menu instead of overflowing the viewport
      tag.div(class: "drawer-side z-50 lg:h-full") do
        # Overlay label - clicking closes the drawer
        overlay = tag.label("", for: id, class: "drawer-overlay", "aria-label": "Close sidebar")

        # Sidebar aside with theme background
        aside = tag.aside(id: "#{id}-content",
                          class: class_names(width, "h-full bg-chrome flex flex-col relative"),
                          "aria-label": "Sidebar navigation",
                          "aria-labelledby": "#{id}-label",
                          data: { controller: "sidebar stream-nav", sidebar_target: "drawer", sidebar_theme_value: theme }) do
          # Phone and tablet drawer header. The title names the landmark: the aside's
          # aria-labelledby already points at this id, which nothing rendered before.
          # Close is the mega menu's phone close (me/menu/_content). The row is the
          # navbar's 64px so Close sits on the line of the navbar icons still showing
          # beside the drawer; from lg the sidebar is always open and has nothing to
          # close, so the row goes. No ink class on the button: sidebar.css sets the
          # rest ink and the focus ring, and leaves daisyUI's hover pill alone.
          # z-10 and bg-chrome, as the menu area and its section titles have, keep the
          # logo below the row: in a drawer under about 225px tall (heavy zoom) the
          # logo reaches it, and without them it painted over Close and took its clicks.
          header = tag.div(class: "flex items-center justify-between h-16 shrink-0 z-10 ps-3 pe-2 " \
                                  "bg-chrome border-b border-sidebar-divider lg:hidden") do
            safe_join([tag.span("Sidebar", id: "#{id}-label", class: "text-base font-semibold text-sidebar-content"),
                       button_action("Close", :ghost, icon: "xmark", icon_type: :solid,
                                     data: { action: "click->sidebar#closeDrawer" },
                                     aria: { label: "Close sidebar" })])
          end

          # Scrollable menu area; z-10 paints the links over the logo when
          # the list is long enough to reach it
          menu_area = tag.div(class: "flex-1 min-h-0 overflow-y-auto pb-4 z-10") do
            capture(&block)
          end

          # Logo area, pinned behind the menu at the bottom of the sidebar
          logo_area = tag.div(class: "absolute bottom-0 inset-x-0 border-t border-sidebar-divider text-center") do
            image_tag("ranger-logo.png",
                      alt: "BRC Ranger Logo",
                      class: "h-[140px] w-[140px] mx-auto mb-5 opacity-30")
          end

          safe_join([header, menu_area, logo_area])
        end

        safe_join([overlay, aside])
      end
    end
  end

  # Sidebar section with title and divider
  def sidebar_section(title, theme: "me", &block)
    header = tag.h6(title, class: section_header_classes(theme))
    content = capture(&block)
    safe_join([header, content])
  end

  # Submenu title with theme-aware styling. A grouping title, not a disclosure:
  # nothing opens or closes it.
  def sidebar_submenu(title, theme: "me")
    tag.div(class: section_header_classes(theme)) do
      tag.span(title, class: "flex-1")
    end
  end

  # Individual sidebar navigation item
  def sidebar_item(title, url, active: nil, active_prefix: false, theme: "me", root: false, **html_options)
    item_classes = sidebar_item_theme_classes(theme)
    html_options[:class] = class_names(SIDEBAR_NAV_ITEM, item_classes, html_options[:class])
    item_is_active = active.nil? ? menu_item_active?(url, root:, active_prefix:) : active

    # active_links_controller re-derives active state after a stream-nav render
    # from the exact path. Hand it the prefix so descendant pages keep the
    # `active` class / aria-current the server gave them -- the same prefix
    # menu_item_active? matched, so an item naming a narrower one (a training's
    # Sessions claims only its session/ pages) is not lit on its siblings' pages,
    # yet still is on its own.
    if active_prefix && !root
      prefix = menu_active_prefix_path(url, active_prefix)
      html_options[:data] = (html_options[:data] || {}).merge(active_prefix: menu_path_for_matching(prefix))
    end

    # The marker itself is in sidebar.css, keyed on the `active` class added
    # below, because active_links_controller toggles that class after a
    # stream-nav render and cannot toggle utilities. This only says which item
    # it is, for assistive technology and for that controller.
    html_options["aria-current"] ||= "true" if item_is_active

    html_options[:class] = class_names(html_options[:class], "no-decoration", active: item_is_active)

    link_to title, url, html_options
  end

  # Render menu for sidebar using hash-based menu definitions
  def sidebar_render_menu(menu_definition, context, theme: "me")
    sections = menu_build(menu_definition, context)
    use_person = menu_uses_person?(menu_definition)
    safe_join(sections.map { |section| sidebar_render_section(section, theme, use_person:, depth: 0) })
  end

  private

  # Render a menu section for sidebar
  def sidebar_render_section(section, theme, use_person:, depth: 0)
    content_parts = []

    if section[:submenu]
      content_parts << sidebar_submenu(section[:title], theme: theme)
    elsif section[:title].present?
      if depth == 0
        return sidebar_section(section[:title], theme: theme) do
          sidebar_render_section_content(section, theme, use_person:, depth:)
        end
      else
        content_parts << sidebar_submenu(section[:title], theme: theme)
      end
    end

    content_parts << sidebar_render_section_content(section, theme, use_person:, depth:)
    safe_join(content_parts)
  end

  # Render section content (items and nested sections)
  def sidebar_render_section_content(section, theme, use_person:, depth:)
    content_parts = []

    if section[:items].present?
      content_parts << safe_join(section[:items].map { |item| sidebar_render_item(item, theme, use_person:) })
    end

    if section[:sections].present?
      content_parts << safe_join(section[:sections].map do |subsection|
        sidebar_render_section(subsection, theme, use_person:, depth: depth + 1)
      end)
    end

    safe_join(content_parts)
  end

  # Render a menu item for sidebar
  def sidebar_render_item(item, theme, use_person:)
    url = menu_resolve_path(item[:path], use_person:, year_scoped: item[:year_scoped])
    options = menu_item_options(item)
    sidebar_item(item[:title], url, **options.merge(theme: theme, active_prefix: menu_item_active_prefix?(item)))
  end

  # Theme color configuration
  def theme_colors(theme)
    THEME_CONFIGS[theme.to_sym] || THEME_CONFIGS[:me]
  end

  # Shared section header classes
  def section_header_classes(theme)
    colors = theme_colors(theme)
    class_names(SIDEBAR_SECTION_HEADER, colors[:section_bg], colors[:section_text])
  end

  # Theme-specific item/link colors
  def sidebar_item_theme_classes(theme)
    theme_colors(theme)[:item]
  end
end
