# frozen_string_literal: true

require "application_system_test_case"

# Exercises the compose recipients: the chip field (AppFormBuilder#
# callsign_chips_field), whose autocomplete and typed callsigns make chips, and
# its phone fallback, the Find Recipient modal, whose choice joins the chips.
class Me::MessagesFindRecipientTest < ApplicationSystemTestCase
  include RichTextEditorTestHelper
  include TimesheetAdminTestHelper # ensure_role / grant_role

  setup do
    @person = person(:active_ranger)
    sign_in(@person)

    # A recipient must have a last_seen_at for messaging_permitted? to be true.
    @recipient = person(:ranger_with_custom_gender)
    @recipient.update!(last_seen_at: 1.day.ago)
  end

  test "compose page shows Find Recipient button on a phone only" do
    visit new_me_message_path

    assert_selector "h1", text: "New Message", wait: 5
    assert_no_selector "a", text: "Find Recipient"
    on_a_phone { assert_selector "a", text: "Find Recipient" }
  end

  # Review finding: the search box put the caret in its text on a press beside
  # it, and this box did not: a press on a chip's name or the padding focused
  # nothing, and closed an open list.
  test "a press anywhere in the recipients box puts the caret in the text, and an open list stays" do
    person(:echelon_ranger).update!(last_seen_at: 1.day.ago)
    visit new_me_message_path
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")
    field = find("#message_form_callsigns")
    field.send_keys "Custom"
    find("[role=option]", text: @recipient.callsign, wait: 5).click
    name = find("[data-callsign-chips-target=chip] span", text: @recipient.callsign)

    name.click
    assert_selector "#message_form_callsigns:focus"

    field.send_keys "Echelon"
    assert_selector "[role=option]", text: "EchelonTest", wait: 5
    name.click
    assert_selector "#message_form_callsigns:focus"
    assert_selector "[role=option]", text: "EchelonTest"
  end

  test "a suggestion taken or a callsign typed becomes a chip, and its button removes it" do
    third = person(:echelon_ranger)
    third.update!(last_seen_at: 1.day.ago)
    visit new_me_message_path
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")

    field = find("#message_form_callsigns")
    field.send_keys "Custom"
    find("[role=option]", text: @recipient.callsign, wait: 5).click
    assert_selector "button[aria-label='Remove #{@recipient.callsign}']"
    assert_equal "", field.value

    # Enter takes a lone suggestion, as the person spells their callsign.
    field.send_keys "echelont"
    assert_selector "[role=option]", text: third.callsign, wait: 5
    field.send_keys :enter
    assert_selector "button[aria-label='Remove #{third.callsign}']"

    # With nothing suggested, Enter takes the callsign as typed, and never sends the form.
    field.send_keys "NoSuchRanger"
    assert_text "No callsigns matched.", wait: 5
    field.send_keys :enter
    assert_selector "button[aria-label='Remove NoSuchRanger']"
    assert_selector "h1", text: "New Message"

    # A callsign already chipped is not chipped twice. The Enter arrives inside
    # the search's debounce, so it waits for the search, which empties the field.
    field.send_keys "nosuchranger", :enter
    assert_field "message_form_callsigns", with: "", wait: 5
    assert_selector "[data-callsign-chips-target=chip]", count: 3

    find("button[aria-label='Remove NoSuchRanger']").click
    assert_no_selector "button[aria-label='Remove NoSuchRanger']"
    assert_equal field, page.active_element

    fill_in "message_form_subject", with: "Burn night crew"
    type_into_rich_text_editor("Radios?")
    click_on "Send Message"

    others = [@recipient, third].map(&:callsign).sort_by(&:downcase).join(", ")
    assert_selector "#messages-panel-header", text: /To:\s+#{others}/, wait: 5
    assert PersonMessage.order(:id).last.group?
  end

  # The HQ window's relay (here Person's, "Send Message to") names its one
  # sender in the same field, capped at one chip.
  test "on the relay a second sender chosen replaces the first" do
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    target = person(:plate_collision_ranger)
    target.update!(last_seen_at: 1.day.ago)
    third = person(:echelon_ranger)
    third.update!(last_seen_at: 1.day.ago)
    visit new_person_message_path(target, direction: "to")
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")

    field = find("#message_form_callsigns")
    field.send_keys "Custom"
    find("[role=option]", text: @recipient.callsign, wait: 5).click
    assert_selector "button[aria-label='Remove #{@recipient.callsign}']"
    field.send_keys "echelont"
    find("[role=option]", text: third.callsign, wait: 5).click

    assert_selector "button[aria-label='Remove #{third.callsign}']"
    assert_selector "[data-callsign-chips-target=chip]", count: 1

    fill_in "message_form_subject", with: "Relay"
    type_into_rich_text_editor("Left at the window.")
    click_on "Send Message"
    assert_selector "#messages-panel-header", text: "Relay", wait: 5
    message = PersonMessage.order(:id).last
    assert_equal [third.id, target.id], [message.sender_person_id, message.person_id]
  end

  # The lookup input has no name: a callsign never made a chip used to be left
  # out of the send without a word (review finding 5).
  test "a callsign still typed when the form is sent goes too" do
    visit new_me_message_path
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")

    find("#message_form_callsigns").send_keys @recipient.callsign
    assert_selector "[role=option]", text: @recipient.callsign, wait: 5
    fill_in "message_form_subject", with: "Radios"
    type_into_rich_text_editor("Who has them?")
    click_on "Send Message"

    assert_selector "#messages-panel-header", text: "Radios", wait: 5
    message = PersonMessage.order(:id).last
    assert_equal [@person.id, @recipient.id], [message.sender_person_id, message.person_id]
  end

  test "on the relay a sender still typed when the form is sent replaces the chip" do
    ensure_role(Role::EVENT_MANAGEMENT, "Event Management")
    grant_role(@person, Role::EVENT_MANAGEMENT)
    target = person(:plate_collision_ranger)
    target.update!(last_seen_at: 1.day.ago)
    third = person(:echelon_ranger)
    third.update!(last_seen_at: 1.day.ago)
    visit new_person_message_path(target, direction: "to")
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")

    field = find("#message_form_callsigns")
    field.send_keys "Custom"
    find("[role=option]", text: @recipient.callsign, wait: 5).click
    assert_selector "button[aria-label='Remove #{@recipient.callsign}']"
    field.send_keys third.callsign
    fill_in "message_form_subject", with: "Relay"
    type_into_rich_text_editor("Left at the window.")
    click_on "Send Message"

    assert_selector "#messages-panel-header", text: "Relay", wait: 5
    message = PersonMessage.order(:id).last
    assert_equal [third.id, target.id], [message.sender_person_id, message.person_id]
  end

  test "an Enter pressed before the suggestions land makes the callsign a chip once they do" do
    visit new_me_message_path
    wait_for_controller("callsign-chips", "[data-controller~='callsign-chips']")

    field = find("#message_form_callsigns")
    # One call: the Enter arrives inside the search's debounce, so the
    # autocomplete holds it for the search.
    field.send_keys "NoSuchRanger", :enter
    assert_selector "button[aria-label='Remove NoSuchRanger']", wait: 5
    assert_equal "", field.value
    assert_selector "h1", text: "New Message"
  end

  # Folded away, the Cadre select used to send the message to the whole team,
  # with nothing on the form to say so (review finding 6).
  test "a Cadre chosen and folded away is not sent to" do
    cadre = teams(:green_dot_cadre)
    PersonTeam.find_or_create_by!(person: @recipient, team: cadre)
    visit new_me_message_path
    wait_for_controller("disclosure-fields", "[data-controller~='disclosure-fields']")

    find("summary", text: "Send to a Cadre or Delegation").click
    select cadre.title, from: "Cadre or Delegation"
    find("summary", text: "Send to a Cadre or Delegation").click
    assert_no_selector "#message_form_team_id"
    field = find("#message_form_callsigns")
    field.send_keys "Custom"
    find("[role=option]", text: @recipient.callsign, wait: 5).click
    fill_in "message_form_subject", with: "Just you"
    type_into_rich_text_editor("Not the Cadre.")
    click_on "Send Message"

    assert_selector "#messages-panel-header", text: "Just you", wait: 5
    message = PersonMessage.order(:id).last
    assert_not message.group?
    assert_nil message.recipient_team_id
    assert_equal @recipient.id, message.person_id
  end

  test "Find Recipient opens the search modal" do
    on_a_phone do
      visit new_me_message_path
      assert_selector "h1", text: "New Message", wait: 5

      click_on "Find Recipient"

      assert_selector "dialog.modal[open]", wait: 5
      assert_selector "h3", text: "Find Recipient"
      assert_selector "input[name='find_recipient_form[query]']"
    end
  end

  test "searching by callsign lists matching recipients" do
    on_a_phone do
      visit new_me_message_path
      assert_selector "h1", text: "New Message", wait: 5

      click_on "Find Recipient"
      assert_selector "dialog.modal[open]", wait: 5

      fill_in "find_recipient_form[query]", with: "Custom"
      click_on "Search"

      within "dialog.modal[open]" do
        assert_selector "li", text: @recipient.callsign, wait: 5
        assert_selector "button", text: "Select Recipient"
      end
    end
  end

  test "selecting a recipient populates the compose form and closes the modal" do
    on_a_phone do
      visit new_me_message_path
      assert_selector "h1", text: "New Message", wait: 5

      click_on "Find Recipient"
      assert_selector "dialog.modal[open]", wait: 5

      fill_in "find_recipient_form[query]", with: "Custom"
      click_on "Search"

      within "dialog.modal[open]" do
        assert_selector "li", text: @recipient.callsign, wait: 5
        click_on "Select Recipient"
      end

      # Modal closes and the recipient joins the chips.
      assert_no_selector "dialog.modal[open]", wait: 5
      assert_selector "span", text: @recipient.callsign
      assert_selector "button[aria-label='Remove #{@recipient.callsign}']"

      # The chip's hidden field is what the form submits.
      hidden = find("#message_form_callsigns_chips input[name='message_form[callsigns][]']", visible: false)
      assert_equal @recipient.callsign, hidden.value

      # Chosen again, they are not chipped twice.
      click_on "Find Recipient"
      fill_in "find_recipient_form[query]", with: "Custom"
      click_on "Search"
      within("dialog.modal[open]") { click_on "Select Recipient" }
      assert_no_selector "dialog.modal[open]", wait: 5
      assert_selector "[data-callsign-chips-target=chip]", count: 1
    end
  end

  test "end-to-end message send via Find Recipient flow" do
    on_a_phone do
      visit new_me_message_path
      assert_selector "h1", text: "New Message", wait: 5

      click_on "Find Recipient"
      assert_selector "dialog.modal[open]", wait: 5

      fill_in "find_recipient_form[query]", with: "Custom"
      click_on "Search"

      within "dialog.modal[open]" do
        assert_selector "li", text: @recipient.callsign, wait: 5
        click_on "Select Recipient"
      end

      assert_no_selector "dialog.modal[open]", wait: 5

      fill_in "message_form_subject", with: "Find Recipient E2E Test"
      type_into_rich_text_editor("Testing end-to-end message send via the Find Recipient flow.")

      click_on "Send Message"

      # A successful send redirects to the conversation, which shows the recipient
      # callsign and the subject we just sent in the panel header.
      assert_selector "span", text: "To:", wait: 5
      assert_text @recipient.callsign
      assert_text "Find Recipient E2E Test"
    end
  end

  test "browser autofill in the Callsign field leaves the dialog open with the value" do
    on_a_phone do
      visit new_me_message_path
      assert_selector "h1", text: "New Message", wait: 5

      click_on "Find Recipient"
      assert_selector "dialog.modal[open]", wait: 5

      # Chrome brackets every value it autofills with a plain keydown and keyup
      # Event -- no key, no modifiers, not a KeyboardEvent (Blink's
      # WebFormControlElement::SetAutofillValue). Stimulus applies the ".meta+k"
      # filter to KeyboardEvents only, so that keydown once reached the search-bar
      # hotkey and the search dialog replaced this one mid-fill.
      execute_script(<<~JS)
        const field = document.querySelector("input[name='find_recipient_form[query]']")
        field.dispatchEvent(new Event("keydown", { bubbles: true }))
        field.value = "Custom"
        field.dispatchEvent(new Event("input", { bubbles: true }))
        field.dispatchEvent(new Event("change", { bubbles: true }))
        field.dispatchEvent(new Event("keyup", { bubbles: true }))
      JS

      assert_no_selector "dialog[aria-label='Search'][open]"
      assert_selector "dialog.modal[open]"
      assert_equal "Custom", find("input[name='find_recipient_form[query]']").value
    end
  end
end
