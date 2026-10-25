# frozen_string_literal: true

class ExpireHandleReservationsJob < ApplicationJob
  def perform
    handles = HandleReservation.expire_handles!
    return if handles.blank?

    ExpiredHandleReservationsMailer.notify(handles: handles).deliver_now
  end
end
