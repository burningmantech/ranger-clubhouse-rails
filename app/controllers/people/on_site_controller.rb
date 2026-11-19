# frozen_string_literal: true

# On-Site Cleanup: everyone still marked on site, split into the people the
# cleanup would mark off site and the people something still holds there.
#
# The GET is the preview and the POST runs it. Nothing is carried from one to
# the other: the run works out afresh who can leave, so a shift started since
# the page was drawn keeps its person on site. The POST redirects back here,
# where the same page now shows who is left and why.
class People::OnSiteController < ApplicationController
  layout "people"

  authorize_role [Role::ADMIN],
                 message: "Admin role required to mark people off site."

  def index
    cleanup = OnSiteCleanup.new
    @leaving = cleanup.leaving
    @staying = cleanup.staying
  end

  def create
    count = OnSiteCleanup.new.run!
    redirect_to people_on_site_path, success: "#{helpers.pluralize(count, "person")} marked off site."
  end
end
