# frozen_string_literal: true

class People::LanguagesKnownController < ApplicationController
  layout "people"

  # The roles that run the event and staff the desks -- the people who need to
  # find a translator while someone is standing in front of them.
  authorize_role [Role::ADMIN, Role::EVENT_MANAGEMENT],
                 message: "Admin or Event Management role required to view languages known."

  def index
    @query = params[:q].to_s.strip
    @site = site_filter
    @report = LanguagesKnownReport.execute(query: @query.presence, site: @site)
  end

  def show
    @query = params[:q].to_s.strip
    @site = site_filter
    @language = LanguagesKnownReport.find_language(params[:language], site: @site)
    @name = @language&.name || params[:language].to_s.strip

    # A page for no language has nothing to show, and every address it built for
    # itself would name the list instead, so its own filter would walk away from
    # it. Send the reader to the list, which is where they were headed.
    redirect_to people_languages_known_path(helpers.languages_known_carried(@query, @site)) if @name.blank?
  end

  private

  # The page opens counting everybody. A filter it does not offer counts
  # everybody too, rather than stopping the page or quietly narrowing it.
  def site_filter
    UiComponents::FilterBarHelper.known_filter(params[:site], LanguagesKnownReport::SITES)
  end
end
