# frozen_string_literal: true

require "test_helper"

class UiAccentCardHelperTest < ActionView::TestCase
  include UiComponents::UiAccentCardHelper
  include IconHelper

  test "the title is a div unless the card names a heading level" do
    render inline: %(<%= ui_accent_card "Sign Up for Shifts" %>)

    assert_select "article > div > div", text: "Sign Up for Shifts"
    assert_select "article h2, article h3, article h4", count: 0
  end

  test "heading_level makes the title that heading, dressed as the div was" do
    render inline: %(<%= ui_accent_card "Sign Up for Shifts" %>)
    div_classes = css_select("article > div > div").sole["class"].split.sort
    render inline: %(<%= ui_accent_card "Sign Up for Shifts", heading_level: :h3 %>)

    heading = css_select("article h3").sole
    assert_equal "Sign Up for Shifts", heading.text.strip
    assert_equal div_classes, heading["class"].split.sort
  end

  test "an h2 title takes the section title's size; every other title stays body size" do
    render inline: %(<%= ui_accent_card "Next Step", heading_level: :h2 %>)
    assert_select "article h2.heading-section", text: "Next Step"

    render inline: %(<%= ui_accent_card "Next Step", heading_level: :h3 %>)
    assert_select "article h3.heading-title", text: "Next Step"
    assert_select "article h3.heading-section", count: 0
  end

  test "the icon sits inside the heading and the badge beside it" do
    render inline: <<~ERB
      <%= ui_accent_card "Sign Up for Shifts", icon: "calendar", heading_level: :h3,
                         badge: ui_badge("urgent", :error) %>
    ERB

    assert_select "article h3", text: "Sign Up for Shifts"
    assert_select "article h3 [aria-hidden=true]"
    assert_select "article", text: /urgent/
  end

  test "a card without a title has no heading" do
    render inline: %(<%= ui_accent_card heading_level: :h3 do %>Body<% end %>)

    assert_select "article h3", count: 0
  end

  test "heading_level refuses a level a card cannot take" do
    error = assert_raises(ArgumentError) { ui_accent_card("Sign Up for Shifts", heading_level: :h1) }

    assert_equal "ui_accent_card unknown heading_level: :h1", error.message
  end
end
