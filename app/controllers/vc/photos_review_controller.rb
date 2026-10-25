# frozen_string_literal: true

# Volunteer Coordinator review queue for submitted BMID photos: approve,
# reject (with emailed reasons), or re-crop a submission.
class Vc::PhotosReviewController < ApplicationController
  layout "vc"

  authorize_role [Role::ADMIN, Role::VC],
                 message: "Admin or Volunteer Coordinator role required to review photos."

  # Provides the crop -> save -> return flow (crop, crop_save, destroy).
  include PhotoUploadConcern

  # Replaces the concern's registration; every action but the index needs the photo.
  before_action :set_person_photo, except: :index

  def index
    result = PersonPhoto.find_for_query(status: PersonPhoto::SUBMITTED, include_rejects: true)
    @photos = result[:person_photo]
    @total = result[:meta][:total]
  end

  def approve
    review(PersonPhoto::APPROVED)
    message = "Photo for #{@person_photo.person.callsign} approved."
    respond_to do |format|
      format.html { redirect_to vc_photos_review_path, success: message }
      format.turbo_stream { render turbo_stream: reviewed_streams(message) }
    end
  end

  # Rejection reasons dialog, rendered into the "modal" turbo frame.
  def reject_dialog
    render layout: false
  end

  def reject
    reasons = permitted_reasons
    if reasons.empty?
      message = "Mark one or more reasons why the photo is being rejected."
      respond_to do |format|
        format.html { redirect_to vc_photos_review_path, error: message }
        format.turbo_stream { render turbo_stream: ui_toast_stream(message, :error) }
      end
      return
    end

    review(PersonPhoto::REJECTED, reject_reasons: reasons,
                                  reject_message: reject_params[:reject_message].presence)
    message = "Photo for #{@person_photo.person.callsign} rejected."
    respond_to do |format|
      format.html { redirect_to vc_photos_review_path, success: message }
      format.turbo_stream { render turbo_stream: reviewed_streams(message) }
    end
  end

  # Render the rejection email as it would be sent, for previewing in a new tab.
  def reject_preview
    mail = PhotoRejectedMailer.notify(person: @person_photo.person,
                                      reject_reasons: permitted_reasons,
                                      reject_message: reject_params[:reject_message].presence).message
    render html: MailLog.html_body(mail).html_safe, layout: false
  end

  # Photo metadata dialog (also used for prior rejected submissions), rendered
  # into the "modal" turbo frame.
  def info
    render layout: false
  end

  # PhotoUploadConcern route/subject overrides — the crop flow returns to the queue.
  def profile_index_path = vc_photos_review_path
  def profile_index_label = "Photo Review"
  def profile_photo_crop_save_path(photo) = vc_photos_review_crop_save_path(photo)
  def profile_photo_path(photo) = vc_photos_review_photo_path(photo)
  def crop_cancel_deletes? = false

  private

  def subject_person = @person_photo.person

  def set_person_photo
    @person_photo = PersonPhoto.find(params[:id])
  end

  # Re-cropping a submitted photo is an edit, mirroring the upstream replace endpoint.
  def after_crop_save
    @person_photo.update!(edited_at: Current.time, edit_person_id: current_user.id)
    ActionLog.record(current_user, "person-photo-replace",
                     "Photo re-cropped during review for #{subject_person.callsign}",
                     { person_photo_id: @person_photo.id }, subject_person.id)
  end

  # The dialog closes and the card redraws in place, so the reviewed photo
  # stays on the page for this visit and a mistake can still be undone with
  # the opposite decision. A reload lists only submitted photos again.
  def reviewed_streams(message)
    [
      turbo_stream.update("modal", ""),
      turbo_stream.replace(@person_photo, partial: "vc/photos_review/photo", locals: { photo: @person_photo }),
      turbo_stream.replace("photos-review-stats", partial: "vc/photos_review/stats",
                                                  locals: { total: PersonPhoto.submitted.count }),
      ui_toast_stream(message, :success)
    ]
  end

  def reject_params = scoped_params(:person_photo, :reject_message, reject_reasons: [])

  def permitted_reasons
    Array(reject_params[:reject_reasons]).map(&:to_s) & PersonPhoto::REJECTIONS.keys
  end

  # Mirror the upstream update endpoint: setting the status marks the photo as
  # reviewed, and the volunteer is emailed unless their account is locked.
  def review(status, **attrs)
    @person_photo.update!(status:, reviewed_at: Current.time, review_person_id: current_user.id, **attrs)

    person = @person_photo.person
    ActionLog.record(current_user, "person-photo-review", "Photo #{status} for #{person.callsign}",
                     { person_photo_id: @person_photo.id, status: }, person.id)
    return if person.status.in?(Person::LOCKED_STATUSES)

    delivery = if status == PersonPhoto::APPROVED
                 PhotoApprovedMailer.notify(person:)
               else
                 PhotoRejectedMailer.notify(person:, reject_reasons: @person_photo.reject_reasons,
                                            reject_message: @person_photo.reject_message)
               end
    # The mailer writes the mail log row as it goes, under the person who holds
    # the address and the reviewer who is signed in.
    delivery.deliver_now
  end
end
