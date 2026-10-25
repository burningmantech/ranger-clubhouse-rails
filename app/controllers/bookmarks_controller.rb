# frozen_string_literal: true

# The kiosk bookmark page: one document of links, shown on a machine standing in
# HQ with no one signed in.
#
# Only documents tagged "bookmark-something" can be reached here. The prefix is
# added to whatever the address asks for, never supplied by the visitor, so the
# agreements and team documents sharing this table stay private.
class BookmarksController < ApplicationController
  layout "bookmark"

  allow_unauthenticated_access
  # Nothing on this page is about a person. Skipping this also stops a kiosk
  # still carrying an old sign-in cookie from marking that person as recently
  # seen every few minutes, for as long as the machine is switched on.
  skip_before_action :set_current_user
  skip_before_action :build_menu_items

  before_action :set_document

  def show
    render :not_found, status: :not_found unless @document
  end

  # The document by itself, for the page to pull in on its own timer. No layout:
  # the answer is dropped into the page already on the screen.
  #
  # A document deleted while a kiosk is up answers with nothing, which leaves the
  # last good copy of the links on that screen rather than wiping it. The page
  # keeps asking, so it picks the document back up if it returns.
  def document
    return head :not_found unless @document

    render layout: false
  end

  private

  def set_document
    @document = Document.find_by(tag: "#{Document::BOOKMARK_TAG_PREFIX}#{params[:tag]}")
  end
end
