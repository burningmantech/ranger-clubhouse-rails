# frozen_string_literal: true

# The announcements shown on everyone's Clubhouse home page. Rangers,
# prospectives and auditors each see the ones addressed to them; this page is
# where they are written.
class Communication::AnnouncementsController < ApplicationController
  layout "communication"

  authorize_role [Role::ADMIN, Role::ANNOUNCEMENT_MANAGEMENT],
                 message: "Admin or Announcement Management role required to manage announcements."

  # The filter-bar convention: "all" means the filter is inactive.
  ALL_FILTER = UiComponents::FilterBarHelper::ALL_FILTER

  STATUS_FILTERS = %w[active expired].freeze

  before_action :set_announcement, only: %i[edit update destroy]

  def index
    @filter_params = filter_params
    @announcements = Motd.find_for_query(index_query).to_a
    @total_count = Motd.count
    @expired_count = Motd.expired.count
    @active_count = @total_count - @expired_count
  end

  def new
    @announcement = Motd.new
  end

  def create
    # The author is whoever is signed in. Never taken from the form.
    @announcement = Motd.new(announcement_params.merge(person_id: current_user.id))

    if @announcement.save
      redirect_to index_anchor_path(@announcement), success: "Announcement posted."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @announcement.update(announcement_params)
      redirect_to index_anchor_path(@announcement), success: "Announcement updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @announcement.destroy!

    redirect_to communication_announcements_path, success: "Announcement deleted."
  end

  def delete_expired
    count = Motd.expire!

    if count.positive?
      redirect_to communication_announcements_path,
                  success: "#{count} expired #{"announcement".pluralize(count)} deleted."
    else
      redirect_to communication_announcements_path, info: "No announcements have expired."
    end
  end

  private

  def set_announcement
    @announcement = Motd.find(params[:id])
  end

  def index_anchor_path(announcement)
    communication_announcements_path(anchor: "announcement-#{announcement.id}")
  end

  # known_filter drops anything the page does not actually apply, so a stale
  # bookmark cannot draw a chip claiming a filter that narrows nothing.
  def filter_params
    { audience: UiComponents::FilterBarHelper.known_filter(params[:audience], Motd::AUDIENCES.keys),
      status: UiComponents::FilterBarHelper.known_filter(params[:status], STATUS_FILTERS),
      sort: params[:sort] == "asc" ? "asc" : "desc" }
  end

  def index_query
    query = { sort: @filter_params[:sort] }
    query[:audience] = @filter_params[:audience] unless @filter_params[:audience] == ALL_FILTER
    query[:status] = @filter_params[:status] unless @filter_params[:status] == ALL_FILTER

    query
  end

  def announcement_params
    params.expect(motd: [:subject, :message, :expires_at,
                         :for_rangers, :for_pnvs, :for_auditors])
  end
end
