# frozen_string_literal: true

# Loads everything the mega-menu content partial needs. Shared by the menu
# frame action and the favorite toggle (which re-renders the same content).
module MegaMenuConcern
  extend ActiveSupport::Concern

  RECENT_LIMIT = 10

  private

  # The menu frame and the star toggle are fetches, not pages, and a sign-in
  # redirect would come back as the sign-in page. Say 401 and let the menu
  # explain (mega_menu_controller.js).
  def request_authentication
    head :unauthorized
  end

  def build_mega_menu
    @mega_categories = MegaMenu.categories(@menu_context)
    @mega_items = MegaMenu.linkable_items(@mega_categories)
    # Starrable categories by favorite key. Built from the visible categories,
    # so category gates apply.
    @mega_category_keys = @mega_categories.index_by { |category| MegaMenu.category_key(category) }
    # Everything the person may star: the one list both the prune below and
    # the favorite toggle check against
    @favoritable_keys = (@mega_items.keys + @mega_category_keys.keys).to_set
    # Paths of starred links and "category:" keys of starred categories
    @favorite_keys = PersonFavorite.where(person_id: current_user.id).pluck(:path).to_set
    # Favorites for links or categories the person can no longer see are
    # deleted, not merely hidden. Menu visibility also covers transient gates
    # (Settings, computed flags), so a feature switched off for the off-season
    # drops its favorites permanently — accepted trade-off for keeping the
    # table honest.
    @favorite_keys.subtract(PersonFavorite.prune_stale!(current_user.id, @favoritable_keys, @favorite_keys))
    # Filter by current visibility BEFORE limiting — visits to pages the
    # person can no longer see must not crowd out older visible ones. The
    # table is bounded per person (unique [person_id, path]), so plucking
    # all rows is cheap.
    @recent_paths = PersonPageVisit.where(person_id: current_user.id)
                                   .order(visited_at: :desc)
                                   .pluck(:path)
                                   .select { |path| @mega_items.key?(path) }
                                   .first(RECENT_LIMIT)
    @active_panel = valid_panels.include?(params[:active]) ? params[:active] : MegaMenu::DEFAULT_PANEL
  end

  # An unknown :active value would render every panel hidden
  def valid_panels
    MegaMenu::CHROME_PANELS + @mega_categories.map { |c| MegaMenu.panel_key(c) }
  end
end
