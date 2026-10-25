# frozen_string_literal: true

class Person::PhotosController < ApplicationController
  layout "person"

  include PersonConcern

  authorize_role [Role::ADMIN, Role::VC]

  include PhotoUploadConcern

  def profile_index_path = person_profile_path(@person)
  def profile_photos_path = person_photos_path(@person)
  def profile_photo_crop_save_path(photo) = crop_save_person_photo_path(@person, photo)
  def profile_photo_path(photo) = person_photo_path(@person, photo)

  private

  def subject_person = @person
  def profile_photo_crop_path(photo) = crop_person_photo_path(@person, photo)
  def selfie_enabled? = false

  def after_crop_save
    ActionLog.record(current_user, "person-photo-upload",
                     "Uploaded BMID photo for #{@person.callsign}",
                     { person_photo_id: @person_photo.id })
  end
end
