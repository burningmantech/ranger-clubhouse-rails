# frozen_string_literal: true

# Stars/unstars a mega-menu link or category, then re-renders the menu content
# so every star and the Favorites panel stay consistent. The panel the person
# was on is preserved via the :active param.
class Me::FavoritesController < ApplicationController
  include MegaMenuConcern

  def toggle
    build_mega_menu

    path = params.expect!(:path)
    unless @favoritable_keys.include?(path)
      head :unprocessable_content
      return
    end

    favorited = PersonFavorite.toggle!(current_user.id, path)
    favorited ? @favorite_keys.add(path) : @favorite_keys.delete(path)

    render turbo_stream: turbo_stream.replace("mega-menu-content", partial: "me/menu/content")
  end
end
