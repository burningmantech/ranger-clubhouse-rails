# frozen_string_literal: true

require "test_helper"

class Me::AgreementsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper

  TAG = Document::BEHAVIORAL_STANDARDS_AGREEMENT_TAG

  setup do
    @person = person(:active_ranger)
    sign_in_as(@person)
  end

  def create_agreement_document(tag = TAG)
    Document.create!(tag:, description: "Behavioral Standards", body: "<p>Be excellent.</p>",
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

  # Each redirect used to put its message in the query string, where nothing
  # reads it, rather than in the flash.
  test "signing an agreement returns to it and says it was signed" do
    create_agreement_document

    patch sign_me_agreement_path(TAG)

    assert_redirected_to me_agreement_path(TAG)
    follow_redirect!
    assert_select "[data-controller=toast]", text: /Agreement signed\./
    assert @person.reload.behavioral_agreement
  end

  test "an unknown agreement returns to the list, which says why" do
    get me_agreement_path("no-such-agreement")

    assert_redirected_to me_agreements_path
    assert_equal "Agreement was not found.", flash[:error]
  end

  # The Vehicle Use Protocol is listed all year, but signable only while its setting is on.
  test "an agreement not open for signing returns to the list, which says why" do
    create_agreement_document(Document::MOTORPOOL_POLICY_TAG)

    get me_agreement_path(Document::MOTORPOOL_POLICY_TAG)

    assert_redirected_to me_agreements_path
    assert_equal "Agreement is not available at this time.", flash[:error]
  end
end
