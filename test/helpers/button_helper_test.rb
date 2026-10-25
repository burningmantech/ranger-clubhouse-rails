# frozen_string_literal: true

require "test_helper"

class ButtonHelperTest < ActionView::TestCase
  include ButtonHelper
  include IconHelper
  include ModalHelper

  # A sticky row is fixed below lg, so the spacer in front of it is all that
  # keeps it off the end of its own form. The helper's half of that is the
  # count: `.button-row-spacer` (components/buttons.css) turns it into a height.

  test "a sticky row tells its spacer how many controls it holds" do
    render inline: <<~ERB
      <%= button_row sticky: true do %>
        <%= submit_button "Create Swag" %>
        <%= cancel_button "/quartermaster/swag" %>
      <% end %>
    ERB

    assert_equal 2, spacer_controls
    assert_select ".button-row-spacer[aria-hidden='true'] + .button-row", count: 1
  end

  test "the delete button an edit form adds is counted with the rest" do
    render inline: <<~ERB
      <%= button_row sticky: true do %>
        <%= submit_button "Update Swag" %>
        <%= cancel_button "/quartermaster/swag" %>
        <%= delete_button "/quartermaster/swag/1", confirm_message: "Delete this swag?" %>
      <% end %>
    ERB

    assert_equal 3, spacer_controls
  end

  test "a hidden field draws nothing, so it is not a line of the stack" do
    render inline: <<~ERB
      <%= button_row sticky: true do %>
        <%= hidden_field_tag :confirmed, "1", id: nil %>
        <%= submit_button "Save, No Bonks" %>
      <% end %>
    ERB

    assert_equal 1, spacer_controls
  end

  # The spacer reads its control height from --size, which lives on DaisyUI's
  # size classes, so it wears the tallest one in the row.
  test "the spacer wears the tallest size class in the row" do
    render inline: <<~ERB
      <%= button_row sticky: true do %>
        <%= submit_button "End Shift", size: "lg" %>
        <%= cancel_button "/me/shift-manage" %>
      <% end %>
    ERB

    assert_select ".button-row-spacer.btn-lg", count: 1
    assert_select ".button-row-spacer.btn-sm", count: 0
  end

  test "a row of ordinary buttons gives its spacer the default size" do
    render inline: <<~ERB
      <%= button_row sticky: true do %>
        <%= submit_button "Save Swag" %>
      <% end %>
    ERB

    assert_select ".button-row-spacer.btn-sm", count: 1
  end

  test "a row that is not sticky takes its own room and gets no spacer" do
    render inline: <<~ERB
      <%= button_row do %>
        <%= submit_button "Save Swag" %>
      <% end %>
    ERB

    assert_select ".button-row", count: 1
    assert_select ".button-row-spacer", count: 0
  end

  # A data-controller on the button starts a copy scoped to the button alone,
  # so one acting on the controller around it must not get one by default.
  test "a button action carries a data-controller only when it names one" do
    render inline: <<~ERB
      <%= button_action "Select None", :ghost, data: { action: "position-picker#selectNone" } %>
      <%= button_action "Show Notes", :secondary, controller: "toggle", data: { toggle_dom_id_value: "notes" } %>
    ERB

    assert_select "button[data-action='position-picker#selectNone']:not([data-controller])", count: 1
    assert_select "button[data-controller='toggle'][data-toggle-dom-id-value='notes']", count: 1
  end

  # The button that does the damage must not look like the safe default.
  test "a delete button's confirm is red unless its dialog names a variant" do
    confirm_variants = [
      delete_button("/swag/1", confirm_message: "Delete this swag?"),
      delete_button("/swag/1", confirm_modal: { message: "Delete this swag?" }),
      delete_button("/swag/1", confirm_modal: { message: "Delete this swag?", variant: :warning })
    ].map do |html|
      dialog = Nokogiri::HTML5.fragment(Nokogiri::HTML5.fragment(html).at_css("a")["data-turbo-confirm"])
      dialog.at_css("#turbo-confirm-button")["class"].split.grep(/\Abtn-(error|warning|primary)\z/)
    end

    assert_equal [["btn-error"], ["btn-error"], ["btn-warning"]], confirm_variants
  end

  # btn-disabled only stops the pointer: with an href the link stays tabbable
  # and Enter follows it.
  test "a disabled button link has no href to follow" do
    render inline: <<~ERB
      <%= button_link "Locked", :secondary, "/me/tickets/review", disabled: true %>
    ERB

    assert_select "a.btn-disabled[role=link][aria-disabled=true]:not([href]):not([disabled])", text: "Locked"
  end

  private

  def spacer_controls
    css_select(".button-row-spacer").sole["style"][/--button-row-controls: (\d+)/, 1].to_i
  end
end
