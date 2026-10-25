# frozen_string_literal: true

# Mega Menu Renderer
#
# Third sibling of SidebarHelper and NavbarHelper — renders the navbar mega
# menu from the same hash-based menu definitions (Menus::MEGA_CATEGORIES),
# pre-filtered by MegaMenu/MenuBuilder.
#
# Expects the controller (via MegaMenuConcern) to have set:
#   @mega_categories    - visible categories with filtered sections
#   @mega_items         - map of resolved URL path => item hash
#   @mega_category_keys - map of "category:" favorite key => visible category
#   @favorite_keys      - Set of the person's favorited paths and category: keys
#   @recent_paths       - recently visited paths, newest first (already filtered)
#   @active_panel       - key of the panel to show
#
# mega_menu_offered? is the exception: it needs only @menu_context, which
# every page has (ApplicationController#build_menu_items).
#
# Documentation: docs/MENUS.md
module MegaMenuHelper
  include MenuHelper

  # Whether the navbar offers this person the menu (MegaMenu.offered?). The
  # bar and the first-sign-in tour ask on the same page, so the answer is
  # kept; false is an answer, hence defined? rather than ||=.
  def mega_menu_offered?
    return @mega_menu_offered if defined?(@mega_menu_offered)

    @mega_menu_offered = MegaMenu.offered?(@menu_context)
  end

  # Recently visited items, newest first
  def mega_recent_items
    @mega_recent_items ||= @recent_paths.map { |path| @mega_items[path] }
  end

  # Favorited items, alphabetical by title
  def mega_favorite_items
    @mega_favorite_items ||= @favorite_keys.filter_map { |path| @mega_items[path] }
                                            .sort_by { |item| item[:title] }
  end

  # Starred categories, in menu order
  def mega_favorite_categories
    @mega_favorite_categories ||= @mega_category_keys.filter_map do |key, category|
      category if @favorite_keys.include?(key)
    end
  end

  # Every visible link as resolved path => [item, category title], in category
  # order; a link that repeats across categories keeps its first. Backs the
  # flat search panel, which the browser filters as the person types. The
  # category rides alongside the item rather than inside it — menu_item_options
  # passes unknown keys straight through to the link's HTML attributes.
  def mega_search_items
    @mega_search_items ||= @mega_categories.each_with_object({}) do |category, by_path|
      mega_category_groups(category).flat_map(&:last).each do |item|
        by_path[MegaMenu.resolve_path(item[:path])] ||= [item, category[:title]]
      end
    end
  end

  # Pairs each item with its category title when another row in the same list
  # shares its title ("Capacity" once per training), and with nil otherwise.
  def mega_labeled(items)
    counts = items.map { |item| item[:title] }.tally
    items.map do |item|
      [item, (mega_search_items[MegaMenu.resolve_path(item[:path])].last if counts[item[:title]] > 1)]
    end
  end

  # Items of a category grouped per section, as [title, items] pairs in
  # definition order. Titles are nil unless the category has multiple
  # visible sections (a lone group needs no heading).
  def mega_category_groups(category)
    titled = category[:sections].many?
    category[:sections].map do |section|
      items = []
      MegaMenu.each_item([section]) { |item| items << item }
      [titled ? section[:title] : nil, items]
    end
  end

  # Panel wrapper; inactive panels carry the hidden attribute
  def mega_panel(key, &block)
    content_tag :section,
                class: "mega-menu-panel",
                hidden: @active_panel != key,
                data: { mega_menu_target: "panel", panel: key },
                &block
  end

  # Panel selector button (desktop side column and mobile tab bar)
  def mega_chrome_button(label, key, options = {})
    options = options.dup
    options[:class] = "mega-menu-chrome-btn #{options.delete(:class)}".squish
    options[:data] = { mega_menu_target: "chrome", panel: key, action: "mega-menu#show", mega_menu_panel_param: key }
    options[:aria] = { current: (@active_panel == key).to_s }
    button_action(label, :ghost, **options)
  end

  # Category entry in the mobile Categories index panel, and a starred
  # category's shortcut in Favorites (whose class: lets it share a row with
  # its star)
  def mega_category_index_button(category, options = {})
    label = safe_join([
      fa_icon(category[:icon], :solid, class: "mega-menu-cat-icon", "aria-hidden": "true"),
      content_tag(:span, class: "mega-menu-cat-text") do
        content_tag(:span, category[:title], class: "mega-menu-item-title") +
          content_tag(:span, category[:description], class: "mega-menu-item-desc")
      end,
      fa_icon("chevron-right", :solid, class: "mega-menu-cat-chevron", "aria-hidden": "true")
    ])
    button_action(label, :ghost,
                  class: "mega-menu-cat-btn #{options[:class]}".squish,
                  data: { action: "mega-menu#show", mega_menu_panel_param: MegaMenu.panel_key(category) })
  end

  # Star toggle for a favoritable link or category: a real button, so Enter and
  # Space work and a new tab never GETs the POST-only route. It submits the
  # shared #mega-menu-star-form with its own formaction. aria-pressed carries
  # the state, so the label stays put. The stable id lets the mega-menu
  # controller put focus back on this star after the toggle re-renders.
  def mega_star_button(key, label, panel_key)
    favorited = @favorite_keys.include?(key)
    button_action "", :ghost,
                  type: "submit",
                  form: "mega-menu-star-form",
                  formaction: me_toggle_favorite_path(path: key, active: panel_key),
                  id: "mega-star-#{panel_key}-#{key.parameterize}",
                  icon: "star",
                  icon_type: favorited ? :solid : :regular,
                  class: "mega-menu-star #{'mega-menu-star-on' if favorited}".squish,
                  aria: { label: "Favorite #{label}", pressed: favorited.to_s }
  end

  # Star toggle for a category, beside its panel heading or its Favorites
  # shortcut. "category" in the label tells "Agreements" the category from
  # "Agreements" the link.
  def mega_category_star_button(category, panel_key)
    mega_star_button(MegaMenu.category_key(category), "#{category[:title]} category", panel_key)
  end

  # Link options for a menu item, sharing NavbarHelper's confirm handling
  def mega_item_link_options(item)
    options = menu_item_options(item).except(:root, :icon)

    options[:data] = if item[:confirm]
      menu_item_confirm_data(item)
                     else
      (options[:data] || {}).merge(action: "mega-menu#close")
                     end

    options[:class] = "mega-menu-item-link no-decoration"
    options
  end
end
