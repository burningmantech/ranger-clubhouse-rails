# frozen_string_literal: true

require "test_helper"

module Me
  class MenuControllerTest < ActionDispatch::IntegrationTest
    include AuthenticationTestHelper
    include TimesheetAdminTestHelper
    include MegaMenuTestHelper

    test "show answers 401 when signed out, and remembers no page to return to" do
      get me_menu_url
      assert_response :unauthorized
      assert_nil session[:return_to_after_authenticating]
    end

    test "show renders categories inside the mega-menu frame" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      assert_select "turbo-frame#mega-menu"
      assert_select "#mega-menu-content"
      assert_match(/My Clubhouse/, response.body)
      assert_match(/Pre-Event/, response.body)
      assert_match(/Communication/, response.body)
      assert_match(/Account/, response.body)
    end

    test "non-admin does not see the Administration category" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      assert_no_match(/Administration/, response.body)
    end

    test "admin sees the Administration category" do
      admin = person(:active_ranger)
      ensure_role(Role::ADMIN, "Admin")
      grant_role(admin, Role::ADMIN)
      sign_in_as(admin)

      get me_menu_url
      assert_response :success
      assert_match(/Administration/, response.body)
      assert_match(/Action Logs/, response.body)
    end

    test "auditor does not see the Pre-Event category" do
      sign_in_as(person(:auditor_ranger))

      get me_menu_url
      assert_response :success
      assert_no_match(/Pre-Event/, response.body)
    end

    test "favorites panel shows starred links and deletes stale ones" do
      ranger = person(:active_ranger)
      PersonFavorite.create!(person_id: ranger.id, path: "/me/profile")
      PersonFavorite.create!(person_id: ranger.id, path: "/no/longer/a/menu/path")
      sign_in_as(ranger)

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='favorites']" do
        assert_select "a[href='/me/profile']"
        assert_select "a[href='/no/longer/a/menu/path']", count: 0
      end
      assert_not PersonFavorite.exists?(person_id: ranger.id, path: "/no/longer/a/menu/path")
      assert PersonFavorite.exists?(person_id: ranger.id, path: "/me/profile")
    end

    test "favorites for links the person lost access to are deleted" do
      ranger = person(:active_ranger)
      PersonFavorite.create!(person_id: ranger.id, path: "/admin/action-logs")
      sign_in_as(ranger)

      get me_menu_url
      assert_response :success
      assert_not PersonFavorite.exists?(person_id: ranger.id, path: "/admin/action-logs")
    end

    test "favorites for categories the person cannot see are deleted" do
      ranger = person(:active_ranger)
      PersonFavorite.create!(person_id: ranger.id, path: "category:administration")
      sign_in_as(ranger)

      get me_menu_url
      assert_response :success
      assert_not PersonFavorite.exists?(person_id: ranger.id, path: "category:administration")
    end

    test "the menu opens on favorites" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='favorites']:not([hidden])"
      assert_select "section[data-panel='recent'][hidden]"
    end

    test "search panel indexes every visible link once, with search text" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='search'][hidden]" do
        # Deduplicated by resolved path even though links repeat across categories
        assert_select "a[href='/me/profile']", count: 1
        # Non-favoritable actions are searchable too
        assert_select "a[href=?]", logout_path
        assert_select ".mega-menu-item[data-search-text*='profile']"
        # Each result names the category it lives under
        assert_select ".mega-menu-item-cat", text: "(My Clubhouse)"
      end
      # Category panels never name the category; Favorites and Recently Visited
      # name it only for a title repeated in the list (training sessions test)
      assert_select "section[data-panel='my-clubhouse'] .mega-menu-item-cat", count: 0
    end

    test "recently visited panel lists visited pages newest first" do
      ranger = person(:active_ranger)
      PersonPageVisit.record(ranger.id, "/me/schedule")
      PersonPageVisit.find_by!(person_id: ranger.id, path: "/me/schedule")
                     .update_columns(visited_at: 1.hour.ago)
      PersonPageVisit.record(ranger.id, "/me/profile")
      sign_in_as(ranger)

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='recent']" do
        assert_select "a[href='/me/profile']"
        assert_select "a[href='/me/schedule']"
      end
      assert response.body.index("/me/profile") < response.body.index("/me/schedule")
    end

    test "tracked page visits feed the recents list" do
      ranger = person(:active_ranger)
      sign_in_as(ranger)

      assert_difference "PersonPageVisit.count", 1 do
        get me_announcements_url
      end

      # Revisiting does not duplicate the row
      assert_no_difference "PersonPageVisit.count" do
        get me_announcements_url
      end

      # Non-menu pages are not tracked
      assert_no_difference "PersonPageVisit.count" do
        get me_menu_url
      end

      assert PersonPageVisit.exists?(person_id: ranger.id, path: "/me/announcements")
    end

    test "unknown active param falls back to the default panel" do
      sign_in_as(person(:active_ranger))

      get me_menu_url(active: "bogus")
      assert_response :success
      assert_select "section[data-panel='favorites']:not([hidden])"
    end

    test "valid active param shows that panel" do
      sign_in_as(person(:active_ranger))

      get me_menu_url(active: "favorites")
      assert_select "section[data-panel='favorites']:not([hidden])"
      assert_select "section[data-panel='recent'][hidden]"

      get me_menu_url(active: "my-clubhouse")
      assert_select "section[data-panel='my-clubhouse']:not([hidden])"
    end

    test "multi-section category panels show section titles as group headings" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      # My Clubhouse holds three titled sections
      assert_select "section[data-panel='my-clubhouse']" do
        assert_select "h4.mega-menu-section-title", text: "Pre-Event"
        assert_select "h4.mega-menu-section-title", text: "Communication"
      end
      # Account has multiple sections too, but they are untitled — no headings
      assert_select "section[data-panel='account'] h4.mega-menu-section-title", count: 0
    end

    test "Account panel renders Logout as a confirm action without a star" do
      sign_in_as(person(:active_ranger))

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='account']" do
        # Logout must go through the confirm modal (DELETE), never a plain GET
        assert_select "a[href=?][data-turbo-method='delete'][data-turbo-confirm]", logout_path
        # Action items get a spacer instead of a favorite star
        assert_select "span.mega-menu-star-spacer", count: 1
        # My Profile, Change Password, Passkeys, Replay Onboarding and Bug Report
        # are plain GET links, one star each (Replay Onboarding's /me?tour=1 is an
        # app-relative String path, which MegaMenu.linkable? admits, and Bug
        # Report's modal-frame dialog is a GET into this app too). Passkeys is
        # there because a test machine offers them (Passkeys.enabled?); the item
        # goes where they are off.
        assert_select ".mega-menu-item button.mega-menu-star", count: 5
        # The category itself carries one more, beside its heading
        assert_select "#mega-star-account-category-account[aria-pressed='false']"
      end
    end

    test "a starred category shows in Favorites as a shortcut to its panel" do
      ranger = person(:active_ranger)
      PersonFavorite.create!(person_id: ranger.id, path: "category:account")
      sign_in_as(ranger)

      get me_menu_url
      assert_response :success
      assert_select "section[data-panel='favorites']" do
        assert_select ".mega-menu-cat-btn[data-mega-menu-panel-param='account']", count: 1
        assert_select "#mega-star-favorites-category-account.mega-menu-star-on[aria-pressed='true']"
        # A category alone is a favorite: no empty state
        assert_select ".empty-state", count: 0
      end
    end

    # Stars are toggle buttons, not links that POST: Enter and Space work, a
    # new tab never GETs the POST-only route, and aria-pressed carries the
    # state so the label stays the same either way.
    test "stars are toggle buttons that submit the shared star form" do
      ranger = person(:active_ranger)
      offer_mega_menu_to(ranger) # the page carries the dialog only then
      PersonFavorite.create!(person_id: ranger.id, path: "/me/profile")
      sign_in_as(ranger)

      # The form lives in the page's dialog, outside the frame a reload swaps
      get me_root_url
      assert_select "dialog#mega-menu-dialog > form#mega-menu-star-form[action=?][hidden]",
                    me_toggle_favorite_path, count: 1

      get me_menu_url
      assert_response :success
      assert_select "form#mega-menu-star-form", count: 0
      assert_select "a.mega-menu-star", count: 0
      assert_select "section[data-panel='favorites'] button.mega-menu-star" do |stars|
        star = stars.first
        assert_equal "submit", star["type"]
        assert_equal "true", star["aria-pressed"]
        assert_equal "mega-menu-star-form", star["form"]
        assert_includes star["formaction"], me_toggle_favorite_path
        assert_match(/\AFavorite /, star["aria-label"])
      end
      assert_select "section[data-panel='account'] button.mega-menu-star[aria-pressed='false']"
    end
  end
end
