# frozen_string_literal: true

# Which Moodle (LMS) course each training position uses for a year, plus
# read-only lookups against the LMS itself: sync a course's name, see who is
# enrolled, and browse the course catalog. The three LMS lookups live on
# their own pages so a slow or unreachable LMS never blocks the index.
class Admin::OnlineCoursesController < ApplicationController
  layout "admin"

  authorize_role Role::ADMIN

  self.year_floor = 2022

  before_action :setup_year, only: [:index, :new, :moodle_catalog, :moodle_catalog_courses]
  before_action :set_online_course, only: [:edit, :update, :destroy, :enrollment, :enrollment_roster, :set_name]
  before_action :set_position_options, only: [:new, :edit]

  def index
    @online_courses = OnlineCourse.for_year(@year).includes(:position).order(:position_id, :course_for).to_a

    # A course for everyone alongside one for a specific audience leaves no
    # single answer for who takes which. Only active courses can conflict --
    # a switched-off course is already out of the running.
    @overlap_position_ids = @online_courses.select(&:active?)
                                           .group_by(&:position_id)
                                           .filter_map { |position_id, courses|
      position_id if courses.size > 1 && courses.any? { |c| c.course_for == OnlineCourse::COURSE_FOR_ALL }
    }.to_set
  end

  def new
    @online_course = OnlineCourse.new(year: @year, active: true, course_for: OnlineCourse::COURSE_FOR_ALL,
                                       course_id: params[:course_id], name: params[:course_name])
  end

  def create
    @online_course = OnlineCourse.new(create_params)

    if @online_course.save
      redirect_to admin_online_courses_path(year: @online_course.year), success: "Online course created."
      return
    end

    set_position_options
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    if @online_course.update(update_params)
      redirect_to admin_online_courses_path(year: @online_course.year), success: "Online course updated."
      return
    end

    set_position_options
    render :edit, status: :unprocessable_entity
  end

  def destroy
    year = @online_course.year
    @online_course.destroy
    redirect_to admin_online_courses_path(year:), success: "Online course deleted."
  end

  # Reads the course's current name from the LMS and saves it -- the only
  # write this controller ever makes to the online_course row outside the
  # normal form. Mirrors the source LMS record, so validations are skipped.
  # Unlike the two lookups below, this one runs on the Groundhog Day Server
  # too -- an admin fixing a name is a deliberate one-off action, not a page
  # load, so there is nothing to protect it from.
  def set_name
    info, error = rescue_moodle_errors { Moodle.new.retrieve_course_info(@online_course.course_id) }

    if error
      redirect_to edit_admin_online_course_path(@online_course), error: error
    elsif info.nil?
      redirect_to edit_admin_online_course_path(@online_course), error: "That course id was not found on the LMS."
    else
      @online_course.update_column(:name, info.fullname.to_s)
      redirect_to edit_admin_online_course_path(@online_course), success: "Name set from the LMS."
    end
  end

  # Page shell only -- the roster itself loads lazily from enrollment_roster.
  def enrollment
  end

  def enrollment_roster
    @people = moodle_lookup { Moodle.new.retrieve_course_enrollment_with_completion(@online_course.course_id) }
    render layout: false
  end

  # Page shell only -- the listing itself loads lazily from moodle_catalog_courses.
  def moodle_catalog
  end

  def moodle_catalog_courses
    @courses = moodle_lookup { moodle_catalog_listing }
    render layout: false
  end

  private

  def set_online_course
    @online_course = OnlineCourse.find(params.expect!(:id))
  end

  # The training positions a course can point at. Retired positions are left
  # out so no one defines a course no one can reach, but the position a course
  # already uses always stays on the list -- otherwise the form would quietly
  # offer a different one and move the course on the next save.
  def set_position_options
    positions = Position.find_for_query({ art_training: true, active: true })
    current_id = @online_course&.position_id

    if current_id.present? && positions.none? { |p| p.id == current_id }
      current = Position.find_by(id: current_id)
      positions = positions + [current] if current
    end

    @position_options = positions.map { |p| [p.title, p.id] }
  end

  def create_params
    params.expect(online_course: [:position_id, :course_id, :course_for, :year, :name, :active])
  end

  # Year is set once at creation from the page the admin was viewing and is
  # never editable afterward -- an online course changing which year it
  # belongs to would break every report and enrollment tied to that year.
  def update_params
    params.expect(online_course: [:position_id, :course_id, :course_for, :active])
  end

  # Every page-load LMS lookup funnels through here: skipped entirely on the
  # Groundhog Day Server (it never calls out to the real LMS), then the
  # shared error handling below for the two ways Moodle itself can fail.
  # @error_message stays blank when the lookup succeeds.
  def moodle_lookup
    if Current.is_ghd_server?
      @error_message = "Live LMS lookups are not available on the Groundhog Day Server."
      return nil
    end

    result, @error_message = rescue_moodle_errors { yield }
    result
  end

  # A plain message for the two ways a live Moodle call can fail, shared by
  # every call site so a wording change never has to happen twice. Only the
  # LMS failures are caught -- anything else is a bug worth seeing, not an
  # outage to report.
  # @return [Array(Object, String)] the block's result with a nil error, or
  #   nil with a message describing what went wrong.
  def rescue_moodle_errors
    [yield, nil]
  rescue Moodle::DownForMaintenanceError
    [nil, "The LMS is undergoing maintenance. Try again later."]
  rescue Moodle::ConnectFailureError, RuntimeError
    [nil, "Could not reach the LMS. Try again later."]
  end

  def moodle_catalog_listing
    linked_by_course_id = OnlineCourse.includes(:position).all.group_by(&:course_id)

    Moodle.new.retrieve_available_courses.each do |course|
      linked = linked_by_course_id[course.id.to_s] || []
      course.online_courses = linked.map { |oc| { title: oc.position.title, course_for: oc.course_for, year: oc.year } }
    end
  end
end
