# frozen_string_literal: true

class Me::ProfileController < ApplicationController
  layout "me"

  # Past prospectives keep their profile (ApplicationController#confine_past_prospective).
  skip_before_action :confine_past_prospective

  include ProfileSubjectConcern

  prepend_before_action :set_is_me
  before_action :check_person_status

  SECTION_IDS = ProfileSubjectConcern::SECTION_IDS

  def index
    render_profile_show
  end

  def mark_reviewed
    @person_event ||= PersonEvent.first_or_new_for_person_year(current_user.id, Current.year)
    @person_event.pii_started_at = Current.time
    @person_event.pii_finished_at = Current.time
    @person_event.save(validate: false)
    redirect_to me_profile_path, success: "Personal information reviewed."
  end

  private

  def subject_person = current_user

  def profile_index_path = me_profile_path

  def profile_edit_section_path(section_id) = me_edit_profile_section_path(section_id)

  def profile_section_path(section_id) = me_profile_section_path(section_id)

  def profile_photos_new_path = new_me_profile_photo_path

  def profile_photos_path = me_profile_photos_path

  def profile_photo_crop_path(photo) = crop_me_profile_photo_path(photo)

  def profile_photo_path(photo) = me_profile_photo_path(photo)

  def profile_languages_path = me_profile_languages_path

  def profile_alerts_edit_path = edit_me_alerts_path

  def profile_password_edit_path = me_profile_edit_password_path

  # Nothing where this Clubhouse offers no passkeys: the page would answer 404.
  def profile_passkeys_path = (me_profile_passkeys_path if Passkeys.enabled?(request))

  def profile_mark_reviewed_path = me_mark_reviewed_profile_path

  def check_person_status
    user = current_user
    if user.is_any_bonked?
      redirect_to me_root_path, error: "Your status does not permit profile editing."
      return false
    end
    true
  end

  def set_is_me
    @is_me = true
  end
end
