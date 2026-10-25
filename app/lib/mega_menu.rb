# frozen_string_literal: true

# Shared logic for the navbar mega menu: which categories are visible in a
# menu context, and which URL paths their links resolve to.
#
# Links are keyed by resolved URL path (e.g. "/me/timesheet"), categories by
# "category:<panel key>". Favorites and recent visits store these keys;
# rendering intersects them with the currently visible links and categories,
# so permission changes and renames simply drop entries instead of leaking
# them.
module MegaMenu
  # Convenience panels that exist besides the category panels. "search" is
  # not listed: it is shown client-side while typing, never as :active. The
  # server cannot restore it either -- the filter is client state, so the
  # mega-menu controller re-applies both after the favorite toggle re-renders.
  DEFAULT_PANEL = "favorites"
  CHROME_PANELS = %w[recent favorites categories].freeze

  # The static categories only the menu reaches: My Clubhouse is the /me
  # sidebar and Account the navbar's user dropdown, so they are left out.
  MENU_ONLY_CATEGORIES = (Menus::MEGA_CATEGORIES - [Menus::MY_CLUBHOUSE, Menus::USER]).freeze

  module_function

  # Categories visible to the given context, each with its sections already
  # filtered by MenuBuilder. Categories with no visible content are dropped.
  # The per-training-position categories are built at request time
  # (TrainingMenu) and ride the same visibility filtering.
  def categories(context)
    (Menus::MEGA_CATEGORIES + TrainingMenu.definitions).filter_map { |category| visible_category(category, context) }
  end

  # Whether the navbar offers the menu at all: its button, its dialog and its
  # hotkey. A person with no visible category beyond My Clubhouse and Account
  # (a Ranger with no roles) already has every link it would show, so they
  # get no menu. The static categories are asked first: the training ones
  # cost a query.
  def offered?(context)
    MENU_ONLY_CATEGORIES.any? { |category| visible_category(category, context) } ||
      TrainingMenu.definitions.any? { |category| visible_category(category, context) }
  end

  # Map of resolved URL path => item hash for every favoritable link.
  def linkable_items(categories)
    items = {}
    categories.each do |category|
      each_item(category[:sections]) do |item|
        items[resolve_path(item[:path])] = item if linkable?(item)
      end
    end
    items
  end

  # Every favoritable path across the static categories, ignoring visibility —
  # used by page-visit tracking (visibility is applied at render time instead).
  # Memoized: the menu constant is frozen and routes are stable after boot;
  # Zeitwerk reloading resets the ivar in development. Training pages: see
  # Training::BaseController#tracked_page?.
  def tracked_paths
    @tracked_paths ||= linkable_items(Menus::MEGA_CATEGORIES).keys.to_set.freeze
  end

  # Stable DOM/panel key for a category
  def panel_key(category)
    category[:title].parameterize
  end

  # Favorite key for a category. Real paths start with "/", so the two kinds
  # share person_favorite.path and can never collide.
  def category_key(category)
    "category:#{panel_key(category)}"
  end

  # Only plain GET links into this app can be favorited or tracked: route-helper
  # Symbols, or the concrete Strings TrainingMenu builds
  # ("/training/green-dot/capacity"). An absolute ("https://…") or
  # protocol-relative ("//host", "/\host") URL is not a page of this app, and
  # actions like Logout (confirm:) and Clear Cache (data: turbo_method) are
  # excluded.
  def linkable?(item)
    path = item[:path]
    (path.is_a?(Symbol) || path.to_s.match?(%r{\A/(?![/\\])})) &&
      !item[:confirm] && item.dig(:data, :turbo_method).blank?
  end

  # Single path authority for the mega menu: item hrefs, favorite keys, and
  # tracked paths must all come from here so they stay byte-identical.
  def resolve_path(path)
    return path.to_s unless path.is_a?(Symbol)

    Rails.application.routes.url_helpers.public_send(path)
  end

  def each_item(sections, &block)
    sections.each do |section|
      section[:items]&.each(&block)
      each_item(section[:sections], &block) if section[:sections]
    end
  end

  # The category with only its visible sections, or nil when none is left.
  def visible_category(category, context)
    return unless MenuBuilder.visible?(category, context)

    sections = MenuBuilder.build(category, context)
    category.merge(sections:) if sections.any?
  end
end
