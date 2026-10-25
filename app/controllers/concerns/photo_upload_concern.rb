# frozen_string_literal: true

# Shared BMID photo flow (upload -> crop -> submit) used by the self-service
# interface (Me::PhotosController) and the admin interface
# (Person::PhotosController). Renders the shared templates in
# app/views/profile_photos/.
#
# Including controllers define the photo subject and the route indirection the
# actions and shared templates rely on:
# - subject_person                      - the Person the photo belongs to
#                                         (same contract as ProfileSubjectConcern)
# - profile_index_path                  - the profile page to return to
# - profile_photos_path                 - POST target for uploads
# - profile_photo_crop_path(photo)      - crop page URL returned to the uploader
# - profile_photo_crop_save_path(photo) - PATCH target for crop data
# - profile_photo_path(photo)           - DELETE target for pending photos
# - crop_cancel_deletes?                - whether the crop page's Cancel deletes the photo
# - selfie_enabled?                     - whether the Take Selfie tab renders
# - after_crop_save                     - optional hook, e.g. audit logging
module PhotoUploadConcern
  extend ActiveSupport::Concern

  PHOTO_TYPE_ERROR = "Photo must be a JPEG, PNG or HEIC file"

  included do
    before_action :set_person_photo, only: %i[crop crop_save destroy]

    helper_method :profile_index_path,
                  :profile_index_label,
                  :profile_photos_path,
                  :profile_photo_crop_save_path,
                  :profile_photo_path,
                  :crop_cancel_deletes?,
                  :selfie_enabled?,
                  :subject_person
  end

  # Label for the crop page's back link; override alongside profile_index_path.
  def profile_index_label = "Personal Info"

  # Whether the crop page's Cancel deletes the pending photo (the uploader flows)
  # or only returns to profile_index_path (reviewers re-cropping a submission).
  def crop_cancel_deletes? = true

  # Render upload form
  def new
    @person_photo = PersonPhoto.new
    render template: "profile_photos/new"
  end

  # Accept upload, convert to JPEG 90%, store PersonPhoto, return JSON with crop URL
  def create
    uploaded_file = params.expect(:photo)

    return render_json_error("File must be less than #{number_to_human_size(PersonPhoto::MAX_FILE_SIZE)}") if uploaded_file.size > PersonPhoto::MAX_FILE_SIZE
    return render_json_error(PHOTO_TYPE_ERROR) unless accepted_photo?(uploaded_file.tempfile.path)

    converted_image = convert_to_jpeg(uploaded_file)

    @person_photo = PersonPhoto.new
    @person_photo.person_id = subject_person.id
    # TODO: remove the *_filename lines when CH3 is fully deployed
    @person_photo.image_filename = ""
    @person_photo.orig_filename = ""
    @person_photo.profile_filename = ""
    @person_photo.status = PersonPhoto::UPLOADED
    @person_photo.uploaded_at = Current.time
    @person_photo.upload_person_id = current_user.id
    @person_photo.original = {
      io: converted_image,
      # Time.current: this name is the storage key, and Current.time stands still on the training server.
      filename: "photo-#{subject_person.id}-uploaded-#{Time.current.to_i}.jpg",
      content_type: "image/jpeg"
    }

    if @person_photo.save(validate: false)
      render json: {
        id: @person_photo.id,
        crop_url: profile_photo_crop_path(@person_photo)
      }, status: :created
    else
      render_json_error("Failed to create record")
    end
  rescue => e
    render_json_error("Failed to process image: #{e.message}")
  end

  # Render crop interface; the image loads from its ActiveStorage URL in the browser
  def crop
    unless @person_photo.is_pending?
      return redirect_to profile_index_path, alert: "Photo is no longer eligible to be adjusted."
    end

    render template: "profile_photos/crop"
  end

  # Process crop data, generate attachments, delete superseded pending photos
  def crop_save
    unless @person_photo.is_pending?
      return render_json_error("Photo is no longer eligible to be adjusted.")
    end

    crop_params_data = crop_data_params
    unless crop_params_data.present?
      return render_json_error("Crop data is missing")
    end

    # Generate profile and avatar attachments from photo with custom transformations
    @person_photo.generate_cropped_attachments!(crop_params_data, user_id: current_user.id)

    # Update status and save crop data to photo metadata
    @person_photo.update!(status: PersonPhoto::SUBMITTED)
    @person_photo.update_crop_data!(crop_params_data)

    # Delete any pending photos
    PersonPhoto.delete_pending(subject_person.id, @person_photo.id)

    # Force reload of person associations to prevent stale blob references in view
    subject_person.reload

    after_crop_save

    respond_to do |format|
      format.html { redirect_to profile_index_path }
      format.json { render json: { redirect_url: profile_index_path } }
    end
  rescue => e
    render_json_error("Failed to process request: #{e.message}")
  end

  # Delete pending photo
  def destroy
    unless @person_photo.is_pending?
      return render_json_error("Photo has already been processed and cannot be deleted.")
    end

    @person_photo.destroy!

    respond_to do |format|
      format.html { redirect_to profile_index_path, info: "Upload cancelled." }
      format.json { head :no_content }
    end
  end

  private

  def after_crop_save
  end

  def set_person_photo
    @person_photo = subject_person.person_photos.find(params[:id])
  end

  def crop_data_params
    params.expect(cropping: [:scale_x, :skew_x, :skew_y, :scale_y, :translate_x, :translate_y])
  end

  # Helper method to render JSON errors consistently
  def render_json_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  # Only the JPEG, PNG and HEIF decoders are left unblocked (config/initializers/vips.rb),
  # so any other file has no loader. The HEIF decoder opens AVIF too, so a HEIF file
  # must be HEVC-compressed: a HEIC.
  def accepted_photo?(path)
    case Vips.vips_foreign_find_load(path)
    when nil then false
    when "VipsForeignLoadHeifFile" then Vips::Image.new_from_file(path).get("heif-compression") == "hevc"
    else true
    end
  end

  # Convert uploaded image to JPEG at 90% quality using VIPS
  def convert_to_jpeg(uploaded_file)
    require "vips"

    # Bake the EXIF orientation into the pixels so the stored original, the
    # browser's crop page, and the crop math all share one frame. autorot's
    # quarter turns need random access, so no :sequential here.
    image = Vips::Image.new_from_file(uploaded_file.tempfile.path).autorot

    Tempfile.create(%w[converted .jpg]) do |temp_file|
      image.write_to_file(temp_file.path, Q: 90)
      return File.open(temp_file.path, "rb")
    end
  rescue LoadError => e
    raise StandardError, "Failed to convert image: #{e.message}"
  end
end
