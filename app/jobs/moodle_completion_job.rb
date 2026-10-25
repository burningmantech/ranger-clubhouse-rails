# frozen_string_literal: true

# Asks the learning site who has finished the online course and records it. Runs
# every ten minutes through the season, so somebody who finishes at nine in the
# evening can sign up for a shift right afterwards.
class MoodleCompletionJob < ApplicationJob
  def perform
    unless Setting.get_value(Setting::ONLINE_COURSE_ENABLED)
      Rails.logger.info("The online course is turned off, skipping the completion scan")
      return
    end

    moodle = begin
      Moodle.new
    rescue => e
      # Runs every ten minutes for months, so a missing setting would otherwise
      # fail hundreds of times a day saying the same thing.
      Rails.logger.error("The learning site cannot be reached: #{e.message}")
      return
    end

    OnlineCourse.for_year(Current.year).active.find_each do |course|
      moodle.process_course_completion(course)
    rescue Moodle::DownForMaintenanceError
      Rails.logger.warn("The learning site is down for maintenance, stopping the scan")
      break
    rescue Moodle::ConnectFailureError => e
      # Reaching the site failed, and that is true of every remaining course as
      # well. Trying each one only waits out the same timeout again.
      Rails.logger.error("Cannot reach the learning site: #{e.message}")
      break
    rescue => e
      Rails.logger.error("Online course #{course.id} could not be scanned: #{e.message}")
      ErrorLog.record_exception(e, "moodle-completion-course-failure", extra: { course_id: course.id })
    end
  end
end
