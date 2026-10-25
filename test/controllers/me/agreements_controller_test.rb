# frozen_string_literal: true

require "test_helper"

class Me::AgreementsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  TAG = Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  def create_agreement_document
    Document.create!(tag: TAG, description: "Behavioral Standards", body: "<p>Be excellent.</p>",
                     person_create_id: @person.id, person_update_id: @person.id)
  end

  test "index says so when no agreement applies" do
    get me_agreements_path

    assert_response :success
    assert_match "No Agreements Required", response.body
  end

  test "index lists an agreement waiting to be signed" do
    create_agreement_document

    get me_agreements_path

    assert_response :success
    assert_select "article[aria-labelledby=?]", "agreement-#{TAG}-title"
  end

  test "index lists an agreement already signed" do
    create_agreement_document
    @person.update_column(:behavioral_agreement, true)

    get me_agreements_path

    assert_response :success
    assert_select "article[aria-labelledby=?]", "agreement-#{TAG}-title"
  end

  test "show renders an agreement that is available to sign" do
    create_agreement_document

    get me_agreement_path(TAG)

    assert_response :success
    assert_match "Be excellent.", response.body
  end
end
