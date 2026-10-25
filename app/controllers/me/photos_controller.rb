# frozen_string_literal: true

class Me::PhotosController < ApplicationController
  layout "me"

  # Part of the profile, which past prospectives keep.
  skip_before_action :confine_past_prospective

  include PhotoUploadConcern

  def profile_index_path = me_profile_path
  def profile_photos_path = me_profile_photos_path
  def profile_photo_crop_save_path(photo) = crop_save_me_profile_photo_path(photo)
  def profile_photo_path(photo) = me_profile_photo_path(photo)

  private

  def subject_person = current_user
  def profile_photo_crop_path(photo) = crop_me_profile_photo_path(photo)
  def selfie_enabled? = true
end
