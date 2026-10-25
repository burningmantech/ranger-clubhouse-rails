# frozen_string_literal: true

require "test_helper"

class MoodleCompletionJobTest < ActiveSupport::TestCase
  # Stands in for the learning site. Records what it was asked about, and can be
  # told to fail on the first course the way the real one does.
  class FakeMoodle
    attr_reader :scanned

    def initialize(fail_first_with: nil)
      @scanned = []
      @fail_first_with = fail_first_with
    end

    def process_course_completion(course)
      @scanned << course.id
      raise @fail_first_with if @fail_first_with && @scanned.size == 1
    end
  end

  setup do
    ErrorLog.delete_all
    enable_online_course(true)
  end

  test "the scan does not start when the online course is turned off" do
    enable_online_course(false)
    fake = FakeMoodle.new

    with_moodle(fake) { MoodleCompletionJob.perform_now }

    assert_empty fake.scanned
  end

  # A course that has been switched off is not one anybody can be finishing.
  test "every course still running this year is scanned, and no other" do
    fake = FakeMoodle.new

    with_moodle(fake) { MoodleCompletionJob.perform_now }

    running = OnlineCourse.for_year(Current.year).active
    assert_equal running.pluck(:id).sort, fake.scanned.sort
    assert_not_includes fake.scanned, online_course(:training_new_2026_inactive).id
  end

  # One course failing says nothing about the next one, so the scan carries on
  # and the failure is written down where somebody will see it.
  test "a course that fails is recorded and the rest are still scanned" do
    fake = FakeMoodle.new(fail_first_with: RuntimeError.new("course is a mess"))

    with_moodle(fake) { MoodleCompletionJob.perform_now }

    assert_equal OnlineCourse.for_year(Current.year).active.count, fake.scanned.size
    logged = ErrorLog.where(error_type: "moodle-completion-course-failure")

    assert_equal 1, logged.count
    assert_equal fake.scanned.first, logged.first.data["course_id"]
  end

  # The site being down is true of every remaining course as well, so trying
  # each one only waits out the same timeout again.
  test "the scan stops when the learning site is down for maintenance" do
    fake = FakeMoodle.new(fail_first_with: Moodle::DownForMaintenanceError.new)

    with_moodle(fake) { MoodleCompletionJob.perform_now }

    assert_equal 1, fake.scanned.size
  end

  test "the scan stops when the learning site cannot be reached" do
    fake = FakeMoodle.new(fail_first_with: Moodle::ConnectFailureError.new("timed out"))

    with_moodle(fake) { MoodleCompletionJob.perform_now }

    assert_equal 1, fake.scanned.size
  end

  private

  def enable_online_course(enabled)
    Setting.find_or_initialize_by(name: Setting::ONLINE_COURSE_ENABLED).update!(value: enabled.to_s)
  end

  def with_moodle(fake)
    original = Moodle.method(:new)
    Moodle.define_singleton_method(:new) { fake }
    yield
  ensure
    Moodle.define_singleton_method(:new, original)
  end
end
