# frozen_string_literal: true

require "application_system_test_case"

class Person::StatusesEditTest < ApplicationSystemTestCase
  setup do
    @viewer = person(:auditor_ranger)
    @target = person(:active_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_position(Position::ALPHA, "Alpha")
    grant_role(@viewer, Role::ADMIN)

    sign_in(@viewer)
  end

  test "shows a modal warning before updating to a warned status" do
    visit edit_person_status_path(@target)

    select Person::ALPHA, from: "Status"
    click_button "Save Status"

    assert_selector "dialog[open]", text: "Confirm Alpha Conversion"
    assert_selector "dialog[open]", text: "convert an active account to an Alpha account"
    assert_selector "dialog[open] #turbo-cancel-button"

    accept_confirm_dialog

    assert_current_path person_path(@target), wait: 5
    assert_text "Status updated."
    assert_equal Person::ALPHA, @target.reload.status
  end

  # The dialog's controller is lazy-loaded, and on a slow connection it can land
  # after the dialog has been answered. Asking must not wait on it: that used to
  # end in the browser's own confirm box, with the dialog's markup as its text.
  test "the warning can be answered before the modal controller has loaded" do
    # Blocking only works with the Network domain on; turning it off again also
    # lifts the block, so nothing is left behind for the tests sharing this browser.
    page.driver.browser.execute_cdp("Network.enable")
    page.driver.browser.execute_cdp("Network.setBlockedURLs", urls: ["*modal_controller*"])
    visit edit_person_status_path(@target)

    select Person::ALPHA, from: "Status"
    click_button "Save Status"

    assert_selector "dialog[open]", text: "Confirm Alpha Conversion"
    assert_not page.evaluate_script(<<~JS), "the modal controller loaded anyway, so this proves nothing"
      !!window.Stimulus.getControllerForElementAndIdentifier(document.querySelector("dialog[open]"), "modal")
    JS
    accept_confirm_dialog

    assert_text "Status updated."
    assert_equal Person::ALPHA, @target.reload.status
  ensure
    page.driver.browser.execute_cdp("Network.disable")
  end

  # When the controller does land late, it finds the answered dialog still in
  # the confirm container, closed. It shows any other dialog it connects to --
  # the one beside it here, which is also the proof that it has connected.
  test "a modal controller that lands late leaves an answered warning closed" do
    visit edit_person_status_path(@target)

    page.execute_script(<<~JS)
      const dialog = (id) => `<dialog id="${id}" class="modal" data-controller="modal"></dialog>`
      document.getElementById("turbo-confirm-modal").innerHTML = dialog("answered")
      document.querySelector("main").insertAdjacentHTML("beforeend", dialog("fresh"))
    JS

    assert_selector "dialog#fresh[open]", visible: :all
    assert_no_selector "dialog#answered[open]", visible: :all
  end

  test "submits immediately when the selected status has no warning" do
    visit edit_person_status_path(@target)

    click_button "Save Status"

    assert_no_selector "dialog[open]"
    assert_text "Status updated."
    assert_equal Person::ACTIVE, @target.reload.status
  end

  private

  def ensure_role(id, title)
    role = Role.find_or_initialize_by(id:)
    role.title = title
    role.new_user_eligible = false
    role.save!
  end

  def ensure_position(id, title)
    position = Position.find_or_initialize_by(id: id)
    position.title = title
    position.active = true
    position.awards_eligible = false
    position.awards_auto_grant = false
    position.awards_grants_service_year = false
    position.count_hours = true
    position.save!
  end

  def grant_role(person, role_id)
    PersonRole.find_or_create_by!(person_id: person.id, role_id:)
  end
end
