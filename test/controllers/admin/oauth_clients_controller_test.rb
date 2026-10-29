# frozen_string_literal: true

require "test_helper"

class Admin::OauthClientsControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include DomIdTestHelper
  include SsoTestHelper

  setup do
    Rails.cache.clear

    @tech_ninja = person(:echelon_ranger)
    @admin = person(:auditor_ranger)
    @outsider = person(:retired_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")

    grant_role(@admin, Role::ADMIN)
    # Tech Ninja and nothing else: this page is the one admin page the Admin
    # role does not open, so the tests have to prove the role on its own works.
    grant_role(@tech_ninja, Role::TECH_NINJA)

    @client = oauth_client(:moodle)

    # After the fixture rows, so their own audit entries do not stand in for
    # the one a test is looking for.
    ActionLog.delete_all
  end

  teardown do
    Rails.cache.clear
  end

  # ---------------------------------------------------------------- index

  test "tech ninja sees a row per client, in id order" do
    sign_in_as(@tech_ninja)

    get admin_oauth_clients_path

    assert_response :success
    assert_select "h1", text: /OAuth Clients/
    assert_select "tbody tr", count: 2
    assert_select "tbody tr:first-child th", text: /ranger-hq-osticket/
    assert_select "td", text: /Ranger Moodle Server/
    assert_unique_dom_ids
  end

  # The rows hold digests, so there is no secret for the list to show.
  test "the list shows no secret" do
    sign_in_as(@tech_ninja)

    get admin_oauth_clients_path

    assert_response :success
    assert_select "th", text: "Secret", count: 0
    assert_select "[data-copy-to-clipboard-content-value]", count: 0
  end

  test "the index offers a way to add and to edit a client" do
    sign_in_as(@tech_ninja)

    get admin_oauth_clients_path

    assert_response :success
    assert_select "a[href=?]", new_admin_oauth_client_path
    assert_select "a[href=?]", edit_admin_oauth_client_path(@client)
  end

  test "an empty table says why it is empty" do
    OauthClient.delete_all

    sign_in_as(@tech_ninja)

    get admin_oauth_clients_path

    assert_response :success
    assert_select "body", text: /No OAuth clients have been added yet/
  end

  # -------------------------------------------------------- authorization

  test "an admin without the tech ninja role is turned away from the index" do
    sign_in_as(@admin)

    get admin_oauth_clients_path

    assert_redirected_to me_root_path
    assert_equal "Tech Ninja role required to manage OAuth clients.", flash[:error]
  end

  test "an admin without the tech ninja role may not reach the write pages" do
    sign_in_as(@admin)

    get new_admin_oauth_client_path
    assert_redirected_to me_root_path

    get edit_admin_oauth_client_path(@client)
    assert_redirected_to me_root_path
  end

  test "an admin without the tech ninja role may not create, edit, or delete a client" do
    sign_in_as(@admin)
    was = @client.description

    assert_no_difference "OauthClient.count" do
      post admin_oauth_clients_path,
           params: { oauth_client: { client_id: "sneaky", description: "Not allowed" } }
    end
    assert_redirected_to me_root_path

    patch admin_oauth_client_path(@client),
          params: { oauth_client: { client_id: @client.client_id, description: "Changed" } }
    assert_redirected_to me_root_path
    assert_equal was, @client.reload.description

    assert_no_difference "OauthClient.count" do
      delete admin_oauth_client_path(@client)
    end
    assert_redirected_to me_root_path
  end

  test "a person with neither role is turned away" do
    sign_in_as(@outsider)

    get admin_oauth_clients_path

    assert_redirected_to me_root_path
  end

  test "a signed out visitor is sent to sign in" do
    get admin_oauth_clients_path

    assert_redirected_to root_path
  end

  # --------------------------------------------------------------- create

  # Not the return address either: the form stopped offering it. The column is
  # still there, still permitted by the strong params, and still what
  # accepts_redirect_uri? compares -- it just has no box on this page any more.
  test "the new form asks for an id and a description but not a secret or a return address" do
    sign_in_as(@tech_ninja)

    get new_admin_oauth_client_path

    assert_response :success
    assert_select "input[name=?]", "oauth_client[client_id]"
    assert_select "input[name=?]", "oauth_client[description]"
    assert_select "input[name=?]", "oauth_client[redirect_uri]", count: 0
    assert_select "input[name=?]", "oauth_client[secret]", count: 0
    assert_select "body", text: /Clubhouse makes one of #{OauthClient::SECRET_LENGTH} characters/
    assert_unique_dom_ids
  end

  # The secret is shown this once, on the list, from the POST itself: a
  # redirect would lose it, since only its digest is stored.
  test "tech ninja creates a client and the Clubhouse gives it a secret, shown once" do
    sign_in_as(@tech_ninja)

    assert_difference "OauthClient.count", 1 do
      post admin_oauth_clients_path,
           params: { oauth_client: { client_id: "new-website", description: "A new website", redirect_uri: "https://new.example.org/callback" } }
    end

    assert_response :unprocessable_entity
    assert_equal "Client new-website created.", flash[:success]
    assert_select "h1", text: /OAuth Clients/
    assert_select "[data-controller='scroll-to-top']"
    assert_select "tbody tr", count: 3

    created = OauthClient.find_by(client_id: "new-website")
    assert_equal "A new website", created.description
    assert_equal "https://new.example.org/callback", created.redirect_uri
    shown = shown_secret
    assert_equal OauthClient::SECRET_LENGTH, shown.length
    assert created.authenticate_secret(shown), "the secret on the page is the one stored"
    assert_select "body", text: /New Secret for new-website/
    assert_select "body", text: /shows it this once/

    get admin_oauth_clients_path
    assert_select "[data-copy-to-clipboard-content-value]", count: 0
  end

  test "a secret posted to the create form is thrown away" do
    sign_in_as(@tech_ninja)

    assert_difference "OauthClient.count", 1 do
      post admin_oauth_clients_path,
           params: { oauth_client: { client_id: "new-website", description: "A new website", redirect_uri: "https://new.example.org/callback",
                                     secret: "a-secret-somebody-else-chose" } }
    end

    assert_response :unprocessable_entity
    created = OauthClient.find_by(client_id: "new-website")
    assert_not created.authenticate_secret("a-secret-somebody-else-chose")
    assert created.authenticate_secret(shown_secret)
  end

  test "the create action records the client without its secret" do
    sign_in_as(@tech_ninja)

    post admin_oauth_clients_path,
         params: { oauth_client: { client_id: "new-website", description: "A new website", redirect_uri: "https://new.example.org/callback" } }

    entry = ActionLog.where(event: "oauth-client-create").last
    assert_not_nil entry
    assert_equal "new-website", entry.data["client_id"]
    assert_not entry.data.key?("secret_digest"), "the secret's digest must stay out of the action log"
  end

  # Each case pins the message it should produce, not just that something went
  # wrong -- otherwise a refusal for an unrelated reason reads as a pass.
  #
  # The two return-address cases that used to live here are gone with the
  # validation behind them. A blank or malformed one is now created without
  # complaint; what it cannot do is receive a code, which
  # OauthClientTest covers on accepts_redirect_uri?.
  {
    "a missing client id" => [{ client_id: "" }, "Enter the Client ID the website sends."],
    "a missing description" => [{ description: "" }, "Describe which website this is."],
    "an id another client already has" =>
      [{ client_id: "ranger-moodle" }, "Another client already uses that Client ID."],
    "an id another client has in different letters" =>
      [{ client_id: "Ranger-Moodle" }, "Another client already uses that Client ID."]
  }.each do |description, (overrides, message)|
    test "creating with #{description} is refused" do
      sign_in_as(@tech_ninja)

      assert_no_difference "OauthClient.count" do
        post admin_oauth_clients_path,
             params: { oauth_client: { client_id: "new-website",
                                       description: "A new website", redirect_uri: "https://new.example.org/callback" }.merge(overrides) }
      end

      assert_response :unprocessable_entity
      assert_select "#form-error-summary", text: /#{Regexp.escape(message)}/
    end
  end

  # --------------------------------------------------------------- update

  test "the edit form offers the secret, both saves, and delete" do
    sign_in_as(@tech_ninja)

    get edit_admin_oauth_client_path(@client)

    assert_response :success
    assert_select "h1", text: /Edit ranger-moodle/
    assert_select "input[name=?]", "oauth_client[secret]"
    assert_select "input[name=?][value]", "oauth_client[secret]", count: 0
    assert_select "body", text: /Leave blank to keep the secret on file/
    assert_select "input[type=submit][value=?]", "Save Client"
    assert_select "input[type=submit][name=?][value=?]", "new_secret", "Save with New Secret"
    assert_unique_dom_ids
  end

  # Both controls that throw something away ask first, and the delete link has
  # to carry the verb -- a plain link would send a GET the route does not answer.
  test "replacing the secret and deleting both ask first" do
    sign_in_as(@tech_ninja)

    get edit_admin_oauth_client_path(@client)

    assert_response :success
    assert_select "input[name=new_secret][data-turbo-confirm]"
    assert_select "a[href=?][data-turbo-method=delete]", admin_oauth_client_path(@client),
                  text: /Delete Client/
    assert_select "a[href=?][data-turbo-confirm]", admin_oauth_client_path(@client)
  end

  test "tech ninja changes a description and the secret is left alone" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { oauth_client: { client_id: @client.client_id, description: "Renamed", secret: "" } }

    assert_redirected_to admin_oauth_clients_path
    assert_equal "Client ranger-moodle updated.", flash[:success]
    @client.reload
    assert_equal "Renamed", @client.description
    assert @client.authenticate_secret(fixture_secret(@client))
  end

  test "a secret typed into the form is kept" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { oauth_client: { client_id: @client.client_id,
                                    description: @client.description,
                                    secret: "a-secret-the-tech-team-chose" } }

    assert_redirected_to admin_oauth_clients_path
    assert @client.reload.authenticate_secret("a-secret-the-tech-team-chose")
    assert_not @client.authenticate_secret(fixture_secret(@client))
  end

  # A secret typed beside the button is dropped, not stored: the fresh one wins.
  test "the second save button replaces the secret and shows the new one once" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { new_secret: "Save with New Secret",
                    oauth_client: { client_id: @client.client_id, description: "Renamed too",
                                    secret: "typed-and-then-replaced" } }

    assert_response :unprocessable_entity
    assert_equal "Client ranger-moodle saved with a new secret.", flash[:success]
    assert_select "body", text: /New Secret for ranger-moodle/

    @client.reload
    assert_not @client.authenticate_secret(fixture_secret(@client))
    assert_not @client.authenticate_secret("typed-and-then-replaced")
    shown = shown_secret
    assert_equal OauthClient::SECRET_LENGTH, shown.length
    assert @client.authenticate_secret(shown)
    # The rest of the form is saved along with the new secret.
    assert_equal "Renamed too", @client.description
  end

  # A refused rotation must not leave the new secret on the form. Shown there,
  # it reads as the live key -- and the next save would store it while saying
  # only that the client was updated.
  test "a refused save with a new secret leaves the stored one, and shows none" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { new_secret: "Save with New Secret",
                    oauth_client: { client_id: "ranger-hq-osticket", description: @client.description } }

    assert_response :unprocessable_entity
    assert @client.reload.authenticate_secret(fixture_secret(@client))
    assert_select "input[name=?][value]", "oauth_client[secret]", count: 0
  end

  test "a rejected edit keeps naming the client as it is stored" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { oauth_client: { client_id: "ranger-hq-osticket",
                                    description: @client.description } }

    assert_response :unprocessable_entity
    assert_select "h1", text: /Edit ranger-moodle/
    assert_select "#form-error-summary"
    assert_equal "ranger-moodle", @client.reload.client_id
  end

  # A blank Secret box is how the edit form says "keep it".
  test "an edit with a blank secret keeps the one on file" do
    sign_in_as(@tech_ninja)

    patch admin_oauth_client_path(@client),
          params: { oauth_client: { client_id: @client.client_id,
                                    description: @client.description, secret: "" } }

    assert_redirected_to admin_oauth_clients_path
    assert @client.reload.authenticate_secret(fixture_secret(@client))
  end

  # -------------------------------------------------------------- destroy

  test "tech ninja deletes a client and its sign-in codes go too" do
    OauthCode.create!(oauth_client: @client, person_id: @outsider.id,
                      code: "a-sign-in-code", scope: "openid", created_at: Current.time)

    sign_in_as(@tech_ninja)

    assert_difference ["OauthClient.count", "OauthCode.count"], -1 do
      delete admin_oauth_client_path(@client)
    end

    assert_redirected_to admin_oauth_clients_path
    assert_equal "Client ranger-moodle deleted.", flash[:success]
  end

  private

  # The one secret on the page, read off its copy control.
  def shown_secret
    controls = css_select("[data-copy-to-clipboard-content-value]")
    assert_equal 1, controls.size, "one secret shown, no more"
    controls.first["data-copy-to-clipboard-content-value"]
  end
end
