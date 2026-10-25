# frozen_string_literal: true

require "test_helper"

class ExpireOauthCodesJobTest < ActiveSupport::TestCase
  test "perform removes codes too old to redeem and keeps the rest" do
    OauthCode.delete_all
    expired = create_code((OauthCode::EXPIRE_IN_SECONDS + 1).seconds.ago)
    fresh = create_code(30.seconds.ago)

    ExpireOauthCodesJob.perform_now

    assert_not OauthCode.exists?(expired.id)
    assert OauthCode.exists?(fresh.id)
  end

  private

  def create_code(created_at)
    OauthCode.create!(oauth_client: oauth_client(:moodle), person_id: person(:active_ranger).id,
                      code: SecureRandom.hex(8), scope: "profile", created_at: created_at)
  end
end
