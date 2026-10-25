# frozen_string_literal: true

# Manage a person's online course (Moodle) enrollment and completion, and display
# their in-person training and Advanced Ranger Training (ART) status for a year.
#
# View access is granted to the person-management roles (see PersonConcern). Only
# Tech Ninja and Trainer may manage the online course record; admins without one of
# those roles are view-only (hence +admin: false+ on the ability gate). The three
# Moodle-API actions and force-complete are additionally restricted to the current
# year.
class Person::TrainingController < ApplicationController
  layout "person"

  include PersonConcern

  before_action :setup_year

  authorize_ability :manage_online_course,
                    roles: [Role::TECH_NINJA, Role::TRAINER],
                    admin: false,
                    only: %i[update_online_course mark_online_course_completed
                             sync_online_course_info reset_online_course_password],
                    deny_to: :training_deny_path,
                    message: "Tech Ninja or Trainer role required to manage online course records."

  require_current_year_for only: %i[mark_online_course_completed
                                    sync_online_course_info
                                    reset_online_course_password],
                           deny_to: :training_deny_path,
                           message: "Online course actions may only be performed for the current year."

  def index
    load_index_data
    load_moodle_account_info if fetch_account_info?
  end

  # Point the person's training online-course record at a different course (DB only;
  # this does NOT enroll the person under Moodle).
  def update_online_course
    course = OnlineCourse.find_by(id: params[:online_course_id])

    if course.nil? || course.position_id != Position::TRAINING
      return redirect_index(error: "That online course does not match the training position.")
    end

    poc = PersonOnlineCourse.first_or_new_for_person_year(@person.id, @year, Position::TRAINING)

    if poc.online_course_id == course.id
      return redirect_index(info: "#{@person.callsign} is already assigned to that online course.")
    end

    poc.online_course_id = course.id
    poc.audit_reason = "online course change"
    poc.save(validate: false)

    redirect_index(success: "Online course updated. Note: this will not enroll #{@person.callsign} under Moodle.")
  end

  # Force-mark the training online course as completed for the year (DB only).
  def mark_online_course_completed
    if PersonOnlineCourse.did_complete_for_year?(@person.id, @year, Position::TRAINING)
      return redirect_index(error: "#{@person.callsign} has already completed the online course for #{@year}.")
    end

    poc = PersonOnlineCourse.first_or_new_for_person_year(@person.id, @year, Position::TRAINING)
    poc.completed_at = Current.time
    poc.audit_reason = "force marked completed"
    poc.save(validate: false)

    redirect_index(success: "Online course marked as completed for #{@year}.")
  end

  # Push the Clubhouse's name/username/email to the person's Moodle account.
  def sync_online_course_info
    return redirect_index(error: account_not_set_up_message) if @person.lms_id.blank?

    with_moodle_rescue do
      Moodle.new.sync_person_info(@person)
      redirect_to person_training_path(@person, year: @year, account_info: 1),
                  success: "Online course account info synced with the Clubhouse."
    end
  end

  # Generate and set a new Moodle password, surfaced once in the flash (no email sent).
  def reset_online_course_password
    return redirect_index(error: account_not_set_up_message) if @person.lms_id.blank?

    with_moodle_rescue do
      password = Moodle.new.reset_password(@person)
      ActionLog.record(Current.person, "lms-password-reset", "password reset requested", nil, @person.id)
      redirect_index(
        success: "New Moodle password for #{@person.callsign}: #{password}. Shown once; no email is sent."
      )
    end
  end

  private

  def load_index_data
    @is_current_year = (@year == Current.year)
    @years = available_years
    @can_manage = can?(:manage_online_course)

    @event_info = PersonEventInfo.find_for_person_year(@person, @year)
    @poc = PersonOnlineCourse.find_for_person_year(@person.id, @year, Position::TRAINING)
    @courses = OnlineCourse.active_for_position_year(Position::TRAINING, @year) if @can_manage
  end

  # The Moodle "Account Info" lookup is slow, so only fetch it when the manager
  # explicitly asks for it, and only for the (writable) current year.
  def fetch_account_info?
    params[:account_info].present? && @can_manage && @is_current_year
  end

  # Port of the PHP getInfo: fetch the Moodle user and build a field-by-field
  # comparison against the expected Clubhouse values, flagging what is out of sync.
  def load_moodle_account_info
    if @person.lms_id.blank?
      @moodle_account = { status: :not_setup }
      return
    end

    with_moodle_rescue do
      user = Moodle.new.find_person_by_moodle_id(@person.lms_id)
      @moodle_account =
        if user.nil?
          { status: :missing_account, lms_id: @person.lms_id }
        else
          build_moodle_comparison(user)
        end
    end
  end

  def build_moodle_comparison(user)
    fields = [
      moodle_field("ID Number", user.idnumber, @person.id),
      moodle_field("Username", user.username, Moodle.build_moodle_username(@person)),
      moodle_field("First Name", user.firstname, @person.desired_first_name),
      moodle_field("Last Name", user.lastname, @person.last_name),
      moodle_field("Email", user.email, Moodle.normalize_email(@person.email))
    ]

    { status: :success, in_sync: fields.all? { |field| field[:in_sync] }, fields: fields }
  end

  def moodle_field(label, actual, expected)
    { label: label, actual: actual, expected: expected, in_sync: actual.to_s == expected.to_s }
  end

  # Shared rescue for the Moodle-calling code paths (index account-info fetch, sync,
  # reset password). Redirects back to the page with an error flash.
  def with_moodle_rescue
    yield
  rescue Moodle::DownForMaintenanceError
    redirect_index(error: "Moodle is down for maintenance. Please try again later.")
  rescue Moodle::ConnectFailureError, RuntimeError
    redirect_index(error: "Unable to contact Moodle. Please try again later.")
  end

  def account_not_set_up_message
    "#{@person.callsign}'s online course account is not set up or linked."
  end

  def available_years
    years = PersonEvent.where(person_id: @person.id).distinct.pluck(:year).compact
    years_with_current(years)
  end

  def training_deny_path
    person_training_path(@person, year: @year)
  end

  def redirect_index(**flash_hash)
    redirect_to person_training_path(@person, year: @year), **flash_hash
  end
end
