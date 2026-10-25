# frozen_string_literal: true

# Which Rangers' phone numbers can receive a text, and which cannot.
class Communication::RbsPhoneNumbersController < ApplicationController
  layout "communication"

  authorize_role [Role::ADMIN, Role::TECH_NINJA],
                 message: "Admin or Tech Ninja role required to read the phone numbers."

  def index
    @counts = RbsPhoneNumbers.counts
    @unverified = RbsPhoneNumbers.unverified.to_a
    @stopped = RbsPhoneNumbers.stopped.to_a
    @total_numbers = @counts.sum(&:numbers)
    @total_verified = @counts.sum(&:verified)
  end
end
