# frozen_string_literal: true

require "test_helper"

module Me
  class FavoritesControllerTest < ActionDispatch::IntegrationTest
    include AuthenticationTestHelper

    test "toggle answers 401 when signed out, and remembers no page to return to" do
      post me_toggle_favorite_url(path: "/me/profile")
      assert_response :unauthorized
      assert_nil session[:return_to_after_authenticating]
    end

    test "toggle stars and unstars a visible menu link" do
      sign_in_as(person(:active_ranger))

      assert_difference "PersonFavorite.count", 1 do
        post me_toggle_favorite_url(path: "/me/profile", active: "favorites"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      assert_match(/turbo-stream/, response.content_type)
      assert_match(/mega-menu-content/, response.body)
      # The re-rendered content keeps the requested panel active and flips the star
      favorites_tag = response.body[/<section[^>]*data-panel="favorites"[^>]*>/]
      assert favorites_tag, "favorites panel missing from toggle response"
      assert_no_match(/hidden/, favorites_tag)
      assert_match(/mega-menu-star-on/, response.body)

      assert_difference "PersonFavorite.count", -1 do
        post me_toggle_favorite_url(path: "/me/profile"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :success
      assert_no_match(/mega-menu-star-on/, response.body)
    end

    test "toggle rejects paths outside the person's visible menu" do
      sign_in_as(person(:active_ranger))

      assert_no_difference "PersonFavorite.count" do
        post me_toggle_favorite_url(path: "/admin/action-logs"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :unprocessable_content
    end

    # The menu build prunes every stored key it does not know, and it runs
    # before toggle! -- so only the NEXT request shows whether category keys
    # survive the prune.
    test "toggle stars a category, and the star survives the next menu build" do
      ranger = person(:active_ranger)
      sign_in_as(ranger)

      assert_difference "PersonFavorite.count", 1 do
        post me_toggle_favorite_url(path: "category:account"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      get me_menu_url
      assert PersonFavorite.exists?(person_id: ranger.id, path: "category:account")

      assert_difference "PersonFavorite.count", -1 do
        post me_toggle_favorite_url(path: "category:account"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
    end

    test "toggle rejects a category the person cannot see" do
      sign_in_as(person(:active_ranger))

      assert_no_difference "PersonFavorite.count" do
        post me_toggle_favorite_url(path: "category:administration"),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end
      assert_response :unprocessable_content
    end
  end
end
