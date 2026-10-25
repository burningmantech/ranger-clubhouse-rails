# frozen_string_literal: true

require "test_helper"

class NavigationHelperTest < ActionView::TestCase
  include NavigationHelper
  include ButtonHelper
  include IconHelper

  test "dropdown_menu names the list after the label unless menu_label is given" do
    render inline: <<~ERB
      <%= dropdown_menu "Actions" do %>
        <%= dropdown_item "Profile", "/profile" %>
      <% end %>
      <%= dropdown_menu "Hello Firecracker", variant: :ghost, menu_label: "User menu" do %>
        <%= dropdown_item "Logout", "/logout" %>
      <% end %>
    ERB

    assert_select "details.dropdown > summary.btn.btn-secondary", text: /Actions/
    assert_select "details.dropdown > ul.dropdown-content[aria-label='Actions'] a[href='/profile']", text: "Profile"
    assert_select "details.dropdown > summary.btn.btn-ghost.btn-sm", text: /Hello Firecracker/
    assert_select "details.dropdown > ul.dropdown-content[aria-label='User menu'] a[href='/logout']", text: "Logout"
    assert_select "ul[aria-label='Hello Firecracker']", count: 0
  end

  # daisyUI's menu draws an empty <li> as its divider line; anything inside the
  # <li> takes the menu's item padding and rounded corners instead.
  test "dropdown_divider is an empty list item hidden from screen readers" do
    render inline: <<~ERB
      <%= dropdown_menu "Actions" do %>
        <%= dropdown_item "Profile", "/profile" %>
        <%= dropdown_divider %>
        <%= dropdown_item "Logout", "/logout" %>
      <% end %>
    ERB

    assert_select "ul.dropdown-content > li[aria-hidden=true]:empty", count: 1
    assert_select "ul.dropdown-content hr", count: 0
  end

  test "dropdown_menu with trigger_label names an icon-only trigger and drops the chevron" do
    render inline: <<~ERB
      <%= dropdown_menu fa_icon("circle-user", :solid), trigger_label: "User menu", menu_label: "User menu" do %>
        <%= dropdown_item "Logout", "/logout" %>
      <% end %>
      <%= dropdown_menu "Actions" do %>
        <%= dropdown_item "Profile", "/profile" %>
      <% end %>
    ERB

    assert_select "details.dropdown > summary[aria-label='User menu'] .fa-circle-user"
    assert_select "summary[aria-label='User menu'] .fa-chevron-down", count: 0
    assert_select "summary:not([aria-label]) .fa-chevron-down", count: 1
  end
end
