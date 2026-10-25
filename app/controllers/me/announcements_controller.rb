# frozen_string_literal: true

class Me::AnnouncementsController < ApplicationController
  layout "me"

  before_action :setup_announcements

  def index
    @unread_count = @announcements.count { |a| !a.has_read }
  end

  def toggle_read
    id = params.expect!(:id).to_i
    announcement = @announcements.find { |row| row.id == id }
    unless announcement
      flash[:error] = "Announcement not found"
      redirect_to me_announcements_path
      return
    end

    announcement.has_read = PersonMotd.toggle_read!(current_user.id, announcement.id)
    unread_count = @announcements.count { |a| !a.has_read }

    render turbo_stream: [
      turbo_stream.replace(announcement, partial: "announcement", locals: { announcement: }),
      turbo_stream.replace("unread-count", partial: "unread_count", locals: { count: unread_count })
    ]
  end

  private

  def setup_announcements
    @announcements = Motd.retrieve_announcements_for_person(current_user.id, current_user.status)
  end
end
