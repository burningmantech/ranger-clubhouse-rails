# frozen_string_literal: true

require "test_helper"

class Admin::PasskeysControllerTest < ActionDispatch::IntegrationTest
  include AuthenticationTestHelper
  include TimesheetAdminTestHelper
  include PasskeyTestHelper
  include ReportCardTestHelper # assert_report_card / card_answer

  setup do
    Current.reset

    @admin = person(:auditor_ranger)
    @owner = person(:active_ranger)
    @other = person(:echelon_ranger)

    ensure_role(Role::ADMIN, "Admin")
    ensure_role(Role::TECH_NINJA, "Tech Ninja")
    grant_role(@admin, Role::ADMIN)

    @own = add_passkey_row(@owner, nickname: "Own Phone", last_used_at: 2.days.ago)
    @enrolled = add_passkey_row(@owner, nickname: "HQ Key 7", added_by: @admin, last_used_at: 60.days.ago)
    @theirs = add_passkey_row(@other, nickname: "Retired Laptop", created_at: 3.days.ago)
  end

  teardown do
    Current.reset
  end

  test "an Admin sees every passkey, whose it is, and who put it there" do
    sign_in_as(@admin)

    get admin_passkeys_path

    assert_response :success
    assert_select "h1", text: "Passkeys"

    own_row = row_for("Own Phone")
    assert_match(/#{@owner.callsign}/, own_row.text)
    assert_match(/#{Regexp.escape(@owner.status)}/, own_row.text)
    assert_match(/Self/, own_row.text)

    enrolled_row = row_for("HQ Key 7")
    assert_match(/#{@admin.callsign}\s+Admin/, enrolled_row.text)

    assert_select "a[href='#{person_passkeys_path(@owner)}']", text: @owner.callsign, minimum: 1
    assert_select "a[href='#{person_passkeys_path(@other)}']", text: @other.callsign
    assert_match(/Never/, row_for("Retired Laptop").text)
  end

  # Summary numbers live in the body, never the hero.
  test "the four counts stand above the list" do
    sign_in_as(@admin)

    get admin_passkeys_path

    # A stat box is its number over its label, and carries no class of its own
    # to find it by: read each label's box.
    { "Accounts with a Passkey" => "2", "Passkeys" => "3",
      "Used in the Last 30 Days" => "1", "Added by an Admin" => "1" }.each do |label, number|
      box = css_select("main div.text-center").find { |tile| tile.css("div").last&.text == label }
      assert_not_nil box, "no stat box labelled #{label}"
      assert_equal number, box.css("div").first.text, "#{label} should read #{number}"
    end
    assert_select "#admin-passkeys-header", text: /Accounts with a Passkey/, count: 0
  end

  test "the list is to look at: it removes nothing, and says where removing is done" do
    sign_in_as(@admin)

    get admin_passkeys_path

    assert_select "main a[data-turbo-method=delete]", count: 0
    assert_match(/removed from the page of the person it belongs to/, card_answer("How do I remove a passkey?"))
  end

  test "the filter keeps only what an Admin enrolled, and its chip takes it off again" do
    sign_in_as(@admin)

    get admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN })

    assert_response :success
    assert_not_nil row_for("HQ Key 7")
    assert_nil row_for("Own Phone")
    assert_nil row_for("Retired Laptop")
    assert_select "body", text: /Showing 1 of 1 passkey/
    assert_select "a[href='#{admin_passkeys_path}']", minimum: 1
    assert_select "body", text: /Added By: An Admin/
  end

  test "a filter value no one offered, or a filter in the wrong shape, shows everything" do
    sign_in_as(@admin)

    get admin_passkeys_path(filter: { added_by: "'; DROP TABLE person_passkey; --" })
    assert_response :success
    assert_not_nil row_for("Own Phone")

    get admin_passkeys_path(filter: "x")
    assert_response :success
    assert_not_nil row_for("Own Phone")

    get admin_passkeys_path(filter: { page: "999999999999" })
    assert_response :success
    assert_not_nil row_for("Own Phone")
  end

  # Clubhouse 2 shares the database and can delete a person without knowing
  # the passkey table exists.
  test "a passkey whose account is gone is listed as such rather than breaking the page" do
    @theirs.update_columns(person_id: Person.maximum(:id) + 1)
    sign_in_as(@admin)

    get admin_passkeys_path

    assert_response :success
    assert_match(/Account deleted/, row_for("Retired Laptop").text)
  end

  test "an enrolled key whose Admin is gone never reads as self-added" do
    @enrolled.update_columns(added_by_person_id: Person.maximum(:id) + 1)
    sign_in_as(@admin)

    get admin_passkeys_path

    assert_match(/A deleted account\s+Admin/, row_for("HQ Key 7").text)
    assert_no_match(/Self/, row_for("HQ Key 7").text)
  end

  # The card's one pair is a how-to about the rows, so it shares the filter
  # bar's branch: there while any passkey exists, whatever the filter leaves.
  test "with no passkeys anywhere the page says so and offers no filter or card" do
    PersonPasskey.delete_all
    sign_in_as(@admin)

    get admin_passkeys_path

    assert_response :success
    assert_select "body", text: /No one has added a passkey yet\./
    assert_select "#passkey-filters", count: 0
    assert_report_card count: 0
  end

  test "a filter that matches nothing says so, and the filter and the card stay within reach" do
    @enrolled.destroy
    sign_in_as(@admin)

    get admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN })

    assert_select "body", text: /No passkeys match the current filter\./
    assert_select "#passkey-filters"
    assert_report_card
  end

  test "the list pages, newest first, and the pager carries the filter along" do
    PersonPasskey.delete_all
    (PersonPasskey::LIST_PAGE_SIZE + 5).times do |n|
      PersonPasskey.insert({ person_id: @owner.id, added_by_person_id: @admin.id, nickname: "Key #{n}",
                             external_id: "bulk-#{n}", public_key: "x",
                             created_at: n.minutes.ago, updated_at: n.minutes.ago })
    end
    sign_in_as(@admin)

    get admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN })
    assert_select "body", text: /Page 1 of 2 · 105 passkeys/
    assert_not_nil row_for("Key 0")
    assert_nil row_for("Key 104")
    assert_select "a[href='#{admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN, page: 2 })}']", text: "Next Page"

    get admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN, page: 2 })
    assert_select "body", text: /Page 2 of 2/
    assert_not_nil row_for("Key 104")
    assert_select "a[href='#{admin_passkeys_path(filter: { added_by: PasskeyFilterForm::ADMIN })}']", text: "Previous Page"
  end

  test "the page is for Admins: a Tech Ninja who is not one is turned away, and so is everyone else" do
    grant_role(@other, Role::TECH_NINJA)
    sign_in_as(@other)
    get admin_passkeys_path
    assert_redirected_to me_root_path

    sign_in_as(@owner)
    get admin_passkeys_path
    assert_redirected_to me_root_path
  end

  private

  def row_for(nickname)
    css_select("tr").find { |row| row.text.include?(nickname) }
  end
end
