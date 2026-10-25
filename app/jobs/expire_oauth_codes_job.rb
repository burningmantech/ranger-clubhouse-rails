# frozen_string_literal: true

# Clears out sign-in codes that were handed out and never presented. The time
# limit is enforced when a code is redeemed; this keeps the table small.
class ExpireOauthCodesJob < ApplicationJob
  def perform
    OauthCode.delete_expired
  end
end
