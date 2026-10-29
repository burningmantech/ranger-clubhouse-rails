# frozen_string_literal: true

require "test_helper"

class TopMenuTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include MegaMenuTestHelper

  # The person the bar's tests sign in as has the menu (MegaMenuTestHelper).
  setup { offer_mega_menu_to(person(:active_ranger)) }

  # The menu is for a person with some area beyond My Clubhouse and Account
  # (MegaMenu.offered?); those two are the sidebar and the user dropdown.
  # Everyone else gets a bar without it: no button at either width, no
  # dialog, and no mega-menu controller or hotkey on the bar.
  test "a person with nothing beyond My Clubhouse gets no Menu button, dialog or hotkey" do
    sign_in_as(person(:ranger_with_custom_gender))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar[data-controller='theme']:not([data-action])", count: 1
    assert_select "button[data-action='mega-menu#open']", count: 0
    assert_select "#mega-menu-dialog", count: 0
    assert_select "[aria-keyshortcuts]", count: 0
    assert_select "ul[aria-label='User menu'] a[href=?]", me_profile_path, minimum: 1
  end

  # The mobile-only navbar controls are icon-only: with "Sidebar" and "Menu"
  # beside the icons the bar is ~30px wider than a 375px phone and the whole
  # page scrolls sideways. The accessible name lives in aria-label.
  test "mobile navbar toggles are icon-only with accessible names" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar .navbar-end button[data-action='mega-menu#open'][aria-label]", text: ""
    assert_select "nav.navbar .navbar-end details.lg\\:hidden > summary[aria-label='User menu']", text: ""
  end

  # The greeting does not fit on a phone, so phones get the same user menu
  # behind an icon; the desktop greeting stays hidden below lg.
  test "phones reach the user menu through an icon, desktops through the greeting" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar .navbar-end details.hidden.lg\\:block > summary", text: /Hello /
    assert_select "nav.navbar .navbar-end details.lg\\:hidden" do
      assert_select "summary .fa-circle-user"
      assert_select "ul[aria-label='User menu'] a[href=?]", logout_path, text: "Logout"
    end
  end

  # The theme switch is in the account menu, not on the bar: one in each of the
  # two user menus, and the `dark:` variant shows the label for the theme a
  # press brings.
  test "the theme switch is in the account menu, not on the bar" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar [data-action='click->theme#toggle']", count: 2
    assert_select "ul[aria-label='User menu'] > li > button[type=button][data-action='click->theme#toggle']",
                  count: 2 do
      assert_select "span.dark\\:hidden", text: "Switch To Dark Theme"
      assert_select "span.hidden.dark\\:inline", text: "Switch To Light Theme"
    end
  end

  # In the account menu (Menus::USER): the "Hello <callsign>" dropdown on a
  # desktop and the icon-only one on a phone share the list, so it is there
  # twice. It opens the dialog in the layout's modal frame. Not on the bar,
  # which it left on 2026-10-29, and not for a past prospective, whom the
  # dialog turns away.
  test "the bug report link is in the account menu and opens the dialog" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar .navbar-end > a[href=?]", new_bug_report_path, count: 0
    assert_select "ul[aria-label='User menu'] > li > a[href=?][data-turbo-frame=modal]", new_bug_report_path,
                  text: "Bug Report", count: 2

    sign_in_as(person(:past_prospective_ranger))
    get me_root_url

    assert_response :success
    assert_select "a[href=?]", new_bug_report_path, count: 0
  end

  # The phone bar is laid out by content: the labelled sidebar toggle, the
  # brand's slot, and on the right the mega menu and user icons, the search
  # button and the unread envelope, 8px apart. The brand's slot waits for
  # 112px, which a 320px phone with the search button has not got (measured
  # 2026-10-29). So the brand steps aside when its slot cannot hold it, and
  # everything else on the bar is kept as narrow as the 36px touch floor
  # allows. Each class below is one of the things that buys that. Lose the
  # container query and the brand pushes the page sideways on the narrowest
  # phones; lose one of the others and the brand disappears from phones it
  # used to fit on.
  test "the phone bar keeps the classes its width budget depends on" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    # Each part is as wide as what is in it, not daisyUI's 50% / auto / 50% --
    # on a phone only; a desktop bar gets its halves back.
    assert_select "nav.navbar .navbar-start.w-auto"
    assert_select "nav.navbar .navbar-end.w-auto"
    # The 8px gaps below lg are 24px of the budget; from lg up they are 16px.
    assert_select "nav.navbar .navbar-end.gap-x-2.lg\\:gap-x-4"
    # The brand's slot takes what the controls leave, and the brand is hidden
    # until the slot is wide enough for it.
    assert_select "nav.navbar .navbar-center" do |slots|
      assert_includes slots.first["class"].split, "@container"
      assert_select "a.hidden", text: "Clubhouse" do |brands|
        assert_includes brands.first["class"].split, "@min-brand:inline-flex"
      end
    end
    # btn-sm is the 36px height (accessibility.css floors it), and btn-square
    # makes an icon-only control as wide as it is tall. Without it the side
    # padding makes the button 41px wide, and a min-w-9 floor never applies.
    # The sidebar toggle is labelled, so it is as wide as its label and never
    # square: squared, its content spilled out of the 36px box on both sides.
    assert_select "nav.navbar label[for=sidebar-drawer].btn-sm:not(.btn-square)"
    assert_select "nav.navbar .navbar-end button[data-action='mega-menu#open'].btn-square.btn-sm"
    assert_select "nav.navbar .navbar-end details.lg\\:hidden > summary.btn-square.btn-sm"
  end

  # Keyboard hints follow the client platform: Mac gets the glyphs, everyone
  # else gets the modifiers spelled out.
  # Sign In Again reloads the page, but a page a form re-rendered sits at the
  # form's address, which may answer only to a POST. That button carries the
  # page the form was on instead, or the dashboard.
  test "Sign In Again on a page a form re-rendered goes to a page it can load" do
    sign_in_as(person(:active_ranger))
    expired = "dialog [data-kind='expired'] button"
    invalid = { person_language: { language_name: "", proficiency: PersonLanguage::PROFICIENCY_FLUENT } }

    get me_root_url
    assert_select "#{expired}[data-mega-menu-url-param]", count: 0

    post me_profile_languages_url, params: invalid, headers: { "Referer" => me_profile_languages_url }
    assert_response :unprocessable_entity
    assert_select "#{expired}[data-mega-menu-url-param=?]", me_profile_languages_url
    assert_select "#{expired}[data-search-bar-url-param=?]", me_profile_languages_url

    post me_profile_languages_url, params: invalid, headers: { "Referer" => "https://elsewhere.example/" }
    assert_select "#{expired}[data-mega-menu-url-param=?]", me_root_path
  end

  test "keyboard hints follow the client platform" do
    sign_in_as(person(:active_ranger))

    get me_root_url, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }
    assert_select "nav.navbar kbd", text: "⌘⇧K"
    assert_select "nav.navbar [aria-label=?]", "Menu (Cmd+Shift+K)"

    get me_root_url, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" }
    assert_select "nav.navbar kbd", text: "⌃⇧K"
    assert_select "nav.navbar [aria-label=?]", "Menu (Ctrl+Shift+K)"
  end

  # The unread envelope (application/_navbar_messages). A mailbox user always
  # has #navbar-messages on the page, hidden at zero, so a Turbo Stream can
  # replace it by id.
  test "a mailbox user with nothing unread gets only the envelope's hidden placeholder" do
    sign_in_as(person(:active_ranger))
    get me_root_url

    assert_response :success
    assert_select "nav.navbar .navbar-end > span#navbar-messages[hidden]", text: ""
    assert_select "#navbar-messages a", count: 0
  end

  test "an unread thread puts the envelope and its count on the bar, linking to the Unread folder" do
    ranger = person(:active_ranger)
    sender = person(:ranger_with_custom_gender)
    PersonMessage.create!(person: ranger, sender_person: sender, creator_person: sender,
                          sender_type: PersonMessage::SENDER_TYPE_PERSON,
                          subject: "Shift swap", body: "Thursday?")
    sign_in_as(ranger)
    get me_root_url

    assert_response :success
    # btn-sm and btn-square keep it to the 36px touch floor, and inside the
    # phone bar's width budget (see the test above).
    assert_select "nav.navbar .navbar-end > #navbar-messages.indicator > a.btn-sm.btn-square[href=?][aria-label=?]",
                  me_messages_path(folder: PersonMessage::FOLDER_UNREAD), "1 unread message" do
      assert_select ".indicator-item.badge-warning", text: "1"
    end
  end

  test "people the mailbox is not for get no envelope at all" do
    sign_in_as(person(:auditor_ranger))
    get me_root_url

    assert_response :success
    assert_select "#navbar-messages", count: 0
  end

  # Live updates (application layout): every signed-in page listens on the
  # viewer's own stream; a page anyone can see listens on none.
  test "a signed-in page listens on the viewer's own stream, and the sign-in page on none" do
    ranger = person(:active_ranger)
    sign_in_as(ranger)
    get me_root_url

    assert_select "turbo-cable-stream-source[channel=?][signed-stream-name=?]", "Turbo::StreamsChannel",
                  Turbo::StreamsChannel.signed_stream_name(ranger), count: 1

    sign_out
    get root_url

    assert_response :success
    assert_select "turbo-cable-stream-source", count: 0
  end

  # The door pages (application/_public_menu): no one is signed in, so the bar
  # holds the brand, leading back to sign-in, and the theme toggle -- none of
  # the signed-in controls, and no sidebar drawer.
  test "the sign-in and register pages get the brand and the theme toggle, and nothing else" do
    [root_url, register_url].each do |url|
      get url

      assert_response :success
      assert_select "nav.navbar", count: 1 do
        assert_select "a[href=?]", root_path, text: "Clubhouse", count: 1
        assert_select "button[data-action='click->theme#toggle'][aria-label='Toggle theme']", count: 1
        assert_select "label[for=sidebar-drawer]", count: 0
        assert_select "a[href=?]", new_bug_report_path, count: 0
        assert_select "button[data-action='mega-menu#open']", count: 0
      end
      assert_select ".drawer", count: 0
      assert_select "#navbar-messages", count: 0
    end
  end

  # The theme is applied by a script in the head before the first paint, on
  # signed-out and signed-in pages alike (layouts/application); the theme
  # controller only repeats the decision once it connects.
  test "every page applies the saved theme before first paint" do
    get root_url
    assert_select "head script", text: /prefers-color-scheme/, count: 1

    sign_in_as(person(:active_ranger))
    get me_root_url
    assert_select "head script", text: /prefers-color-scheme/, count: 1
  end
end
