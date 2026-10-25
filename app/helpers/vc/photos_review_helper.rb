# frozen_string_literal: true

module Vc::PhotosReviewHelper
  def photo_status_badge(status)
    case status
    when PersonPhoto::APPROVED
      ui_badge "Approved", :success, icon: "circle-check", icon_type: :solid
    when PersonPhoto::REJECTED
      ui_badge "Rejected", :error, icon: "circle-xmark", icon_type: :solid
    when PersonPhoto::SUBMITTED
      ui_badge "Submitted", :warning, icon: "clock", icon_type: :solid
    else
      ui_badge status, :secondary
    end
  end
end
