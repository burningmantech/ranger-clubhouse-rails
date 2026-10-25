# frozen_string_literal: true

# Serves the mega-menu content into its lazy-loaded Turbo Frame, so the
# favorites/recents queries run only when the menu is opened.
class Me::MenuController < ApplicationController
  include MegaMenuConcern

  def show
    build_mega_menu
    render layout: false
  end
end
