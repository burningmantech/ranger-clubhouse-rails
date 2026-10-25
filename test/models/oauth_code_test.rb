# frozen_string_literal: true

require "test_helper"

class OauthCodeTest < ActiveSupport::TestCase
  setup do
    OauthCode.delete_all
    @client = oauth_client(:moodle)
    @person = person(:active_ranger)
  end

  # A code that is too old to redeem still opens an account until something
  # removes it, so the cleanup is what makes the time limit real.
  test "delete_expired removes codes past the time limit and keeps the rest" do
    expired = create_code(created_at: (OauthCode::EXPIRE_IN_SECONDS + 1).seconds.ago)
    fresh = create_code(created_at: 60.seconds.ago)

    assert_equal 1, OauthCode.delete_expired

    assert_not OauthCode.exists?(expired.id)
    assert OauthCode.exists?(fresh.id)
  end

  test "a code is issued for one client and one person, long enough to be safe" do
    code = OauthCode.issue(@client, @person, "openid email profile")

    assert_equal @client, code.oauth_client
    assert_equal @person, code.person
    assert_equal "openid email profile", code.scope
    assert_operator code.code.length, :>=, 64
    assert_in_delta Time.current, code.created_at, 2.seconds
  end

  test "a code is redeemed once, by the client it was issued to" do
    code = OauthCode.issue(@client, @person, "openid")

    assert_nil OauthCode.redeem(oauth_client(:osticket), code.code)
    assert OauthCode.exists?(code.id), "another client's attempt must not burn the code"

    assert_equal code, OauthCode.redeem(@client, code.code)
    assert_not OauthCode.exists?(code.id)
    assert_nil OauthCode.redeem(@client, code.code)
  end

  test "a code past its time is refused and taken away when redeemed" do
    expired = create_code(created_at: (OauthCode::EXPIRE_IN_SECONDS + 1).seconds.ago)

    assert_nil OauthCode.redeem(@client, expired.code)
    assert_not OauthCode.exists?(expired.id)
  end

  test "redeeming nothing, or a code no one issued, is nil" do
    assert_nil OauthCode.redeem(@client, "")
    assert_nil OauthCode.redeem(@client, nil)
    assert_nil OauthCode.redeem(@client, "made-up")
  end

  private

  def create_code(created_at:)
    OauthCode.create!(oauth_client: @client, person_id: @person.id,
                      code: SecureRandom.hex(8), scope: "profile", created_at: created_at)
  end
end
