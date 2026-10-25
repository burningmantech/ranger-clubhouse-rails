# frozen_string_literal: true

# The way into the Online Course: a page saying what is about to happen, and a
# button that sets up the person's Moodle account, enrolls it in this year's
# course, and sends the browser to the course site. Port of upstream's
# online-course-launch component and PersonOnlineCourseController#setupPerson.
#
# Open to everyone signed in: it only ever acts on their own account.
class Me::OnlineCourseController < ApplicationController
  layout "me"

  before_action -> { prevent_if_ghd_server("Online Course setup") }, only: :create

  # An ART's dashboard row links here with ?art=1: its course is on the same
  # site, so the page says where to find it instead of the In-Person reminder.
  def index
    @art = params[:art].present?
  end

  def create
    course = find_course
    unless course
      return back_to_page("This year's Online Course isn't set up yet. " \
                          "Email #{EmailAddresses::TRAINING_ACADEMY} for help.")
    end

    Moodle.new.set_up_person(current_user, course)
    redirect_to course_site_url, allow_other_host: true
  rescue Moodle::DownForMaintenanceError, Moodle::ConnectFailureError
    back_to_page "The Online Course is down for maintenance. Try again later, " \
                 "and email #{EmailAddresses::TECH_CADRE} if it's still down tomorrow."
  rescue RuntimeError
    back_to_page "Your Online Course account couldn't be set up. Try again in a few minutes, " \
                 "and email #{EmailAddresses::TECH_CADRE} if it keeps happening."
  end

  private

  # One course for everyone when there is one; otherwise the returning course
  # for an active Ranger with two or more years, and the new one for the rest.
  def find_course
    courses = OnlineCourse.active_for_position_year(Position::TRAINING, Current.year)
    returning = current_user.is_active? && current_user.years_as_ranger.size >= 2

    courses.find_by(course_for: OnlineCourse::COURSE_FOR_ALL) ||
      courses.find_by(course_for: returning ? OnlineCourse::COURSE_FOR_RETURNING : OnlineCourse::COURSE_FOR_NEW)
  end

  # Back to the page, still showing the ART note to someone who came from an ART.
  def back_to_page(error)
    redirect_to me_online_course_path(art: params[:art].presence), error:
  end

  # The course site, told the Moodle username as upstream does.
  def course_site_url
    helpers.append_query_params(Setting.get_value(Setting::ONLINE_COURSE_SITE_URL),
                                "username" => current_user.lms_username)
  end
end
