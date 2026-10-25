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
  SIDEBAR_CLOSE_BTN = "sidebar-close-btn"
  SIDEBAR_NAV_ITEM = "sidebar-nav-item"
  SIDEBAR_SECTION_HEADER = "sidebar-section-header"
  SIDEBAR_BADGE = "sidebar-badge"

  # Theme configuration hash - colors from old_sidebar.scss
  THEME_CONFIGS = {
    me: {
      text: "text-sidebar-content",
      close_button: "text-sidebar-content",
      section_text: "text-sidebar-content",
      section_bg: "sidebar-group-title-default",
      item: "sidebar-link-default"
    },
    admin: {
      text: "text-sidebar-content",
      close_button: "text-sidebar-content",
      section_text: "text-sidebar-content",
      section_bg: "sidebar-group-title-hq",
      item: "sidebar-link-hq"
    },
    hq: {
      text: "text-sidebar-content",
      close_button: "text-sidebar-content",
      section_text: "",
      section_bg: "sidebar-group-title-default",
      item: "sidebar-link-default"
    }
  }.freeze

  # Badge variant color configurations
  SIDEBAR_BADGE_VARIANTS = {
    error: "text-error bg-error/10 border border-error/30",
    success: "text-success bg-success/10 border border-success/30",
    warning: "text-warning bg-warning/10 border border-warning/30",
    info: "bg-primary/10 border border-primary/30",
    default: "text-neutral-content bg-neutral border border-neutral-content/30"
  }.freeze

  # DaisyUI drawer-based sidebar menu
  # Options:
  #   :id - drawer id (default: 'sidebar-drawer')
  #   :width - drawer width class (default: 'w-65 lg:w-55')
  #
  # Theme options: 'me' (person theme), 'admin' (hq theme), 'default'
  def sidebar_menu(theme = "me", id: "sidebar-drawer", width: "w-65 lg:w-45", **_options, &block)
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
          # Close button for mobile
          close_btn_color = theme_colors(theme)[:close_button]
          close_button = tag.button(type: "button",
                                    class: class_names(SIDEBAR_CLOSE_BTN, close_btn_color),
                                    data: { action: "click->sidebar#closeDrawer" },
                                    "aria-label": "Close sidebar") do
            fa_icon :times, :solid
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

          safe_join([close_button, menu_area, logo_area])
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

  # Submenu title with theme-aware styling
  def sidebar_submenu(title, icon: nil, icon_type: "regular", theme: "me")
    tag.div(
      class: section_header_classes(theme),
      "aria-expanded": "false"
    ) do
      render_icon_with_title(title, icon, icon_type, title_class: "flex-1", icon_class: "shrink-0 w-5 h-5 me-2")
    end
  end

  # Individual sidebar navigation item
  def sidebar_item(title, url, icon: nil, icon_type: "regular", badge: nil, badge_variant: :error,
                   use_turbo: false, active: nil, active_prefix: false, theme: "me", root: false, **html_options)
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

    if use_turbo
      html_options[:data] ||= {}
      html_options[:data][:action] = "click->stream-nav#follow"
    end

    link_to title, url, html_options
  end

  # Sidebar item as list element (for use within sidebar_submenu)
  def sidebar_submenu_item(title, url, **options)
    options[:class] = class_names("pl-4", options[:class])
    tag.li do
      sidebar_item(title, url, **options)
    end
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

  # Generate badge for sidebar items
  def sidebar_badge(text, variant)
    variant_class = SIDEBAR_BADGE_VARIANTS[variant] || SIDEBAR_BADGE_VARIANTS[:default]
    tag.span(text, class: class_names(SIDEBAR_BADGE, variant_class))
  end

  # Render icon with title
  def render_icon_with_title(title, icon_name, icon_type, title_class:, icon_class: "inline-block w-5 h-5 mr-2")
    if icon_name
      safe_join([fa_icon(icon_name, icon_type, class: icon_class), tag.span(title, class: title_class)])
    else
      tag.span(title, class: title_class)
    end
  end

  # Render sidebar item content (icon, title, badge)
  def render_sidebar_content(title, icon_name, icon_type, badge_text, badge_variant)
    content = render_icon_with_title(title, icon_name, icon_type,
                                     title_class: "flex-1 whitespace-nowrap hover:underline")

    if badge_text
      safe_join([content, sidebar_badge(badge_text, badge_variant)])
    else
      content
    end
  end
end
