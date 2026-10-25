# frozen_string_literal: true

class Person::ProfilesController < ApplicationController
  layout "person"

  include PersonConcern
  include ProfileSubjectConcern

  prepend_before_action :set_is_me

  authorize_role [
    Role::ADMIN,
    Role::VC,
    Role::EVENT_MANAGEMENT,
    Role::EVENT_MANAGEMENT_ON_PLAYA,
    Role::VIEW_PII
  ]

  def show
    render_profile_show
  end

  private

  def subject_person = @person

  def profile_index_path = person_profile_path(@person)

  def profile_edit_section_path(section_id) = person_edit_profile_section_path(@person, section_id)

  def profile_section_path(section_id) = person_profile_section_path(@person, section_id)

  def profile_photos_new_path
    return nil unless can_upload_bmid_photo?
    new_person_photo_path(@person)
  end

  def profile_photos_path
    return nil unless can_upload_bmid_photo?
    person_photos_path(@person)
  end

  def profile_photo_crop_path(photo)
    return nil unless can_upload_bmid_photo?
    crop_person_photo_path(@person, photo)
  end

  def profile_photo_path(photo)
    return nil unless can_upload_bmid_photo?
    person_photo_path(@person, photo)
  end

  def profile_languages_path
    return nil unless can_view_languages?
    person_profile_languages_path(@person)
  end

  def profile_alerts_edit_path
    return nil unless can_edit_alert_preferences?
    edit_person_alerts_path(@person)
  end

  def after_successful_update
    return unless @person.previous_changes.any?

    ActionLog.record(current_user, "person-profile-update",
                     "Updated #{@section_name} for #{@person.callsign}",
                     { changes: @person.previous_changes })
  end

  def set_is_me
    # We're not on the /me side of things.
    @is_me = false
  end
end
