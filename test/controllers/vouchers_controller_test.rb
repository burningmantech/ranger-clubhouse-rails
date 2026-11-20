# frozen_string_literal: true

require "test_helper"

# The public voucher page. Nothing here signs in: that is the point of the page.
class VouchersControllerTest < ActionDispatch::IntegrationTest
  include PersonPhotoTestHelper # create_photo

  setup do
    @person = person(:active_ranger)
    @person.update_columns(uuid: SecureRandom.uuid_v7)
    # Every test runs with an approved photo on file, so a page that shows none
    # is hiding one.
    photo = create_photo(person: @person, status: PersonPhoto::APPROVED, profile_filename: "p.jpg")
    photo.profile.attach(io: StringIO.new("not-really-a-jpeg"), filename: "p.jpg", content_type: "image/jpeg")
  end

  test "a Ranger's voucher shows callsign, status, years and hours without signing in" do
    get voucher_path(@person.uuid)

    assert_response :success
    assert_select "h2", text: "Black Rock Ranger"
    assert_select "main", text: /#{@person.callsign}/
    assert_select "main", text: /Years as a Ranger\s+2\s+2023 - 2024/
    assert_select "th", text: positions(:ood_position).title
    assert_select "main img[alt=?]", "Photo of #{@person.callsign}"
    assert_select "article", text: /Burning Man Project\. This information is copyrighted/
    assert_select "nav", false
    assert_select "meta[name=robots][content='noindex,nofollow']"
  end

  test "the page is not stored, not indexed and sends no referrer" do
    get voucher_path(@person.uuid)

    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "noindex", response.headers["X-Robots-Tag"]
  end

  test "an applicant is named as one, with no years or hours" do
    @person.update_columns(status: Person::PROSPECTIVE)
    get voucher_path(@person.uuid)

    assert_response :success
    assert_select "h2", text: "Applicant, Not Yet a Ranger"
    assert_select "main img", count: 1
    assert_select "main", text: /#{@person.callsign}/
    assert_select "main", text: /Years as a Ranger/, count: 0
    assert_select "table", false
  end

  test "echelon shows the callsign and nothing more" do
    @person.update_columns(status: Person::ECHELON)
    get voucher_path(@person.uuid)

    assert_select "h2", text: "Not a Ranger"
    assert_select "main img", count: 1
    assert_select "main", text: /#{@person.callsign}/
    assert_select "main", text: /Status/, count: 0
    assert_select "table", false
  end

  test "a status that is not a Ranger shows no callsign, status or hours" do
    [Person::PAST_PROSPECTIVE, Person::BONKED, Person::UBERBONKED, Person::AUDITOR,
     Person::RESIGNED, Person::DISMISSED, Person::DECEASED].each do |status|
      @person.update_columns(status:)
      get voucher_path(@person.uuid)

      assert_response :success, status
      assert_select "h2", { text: "Not a Ranger" }, status
      assert_select "main img[alt=?]", "Photo of this person", { count: 1 }, status
      assert_no_match(/#{@person.callsign}/, response.body, status)
      assert_select "table", false, status
    end
  end

  test "suspended says only that nothing is available and where to ask" do
    @person.update_columns(status: Person::SUSPENDED)
    get voucher_path(@person.uuid)

    assert_response :success
    assert_select "h2", text: "Information Not Available"
    assert_select "[role=status] a[href='mailto:rangers@burningman.org']"
    assert_no_match(/#{@person.callsign}/, response.body)
    assert_no_match(/No photo on file/, response.body)
    assert_select "main img", false
  end

  test "a person with no approved photo says so where the photo would be" do
    PersonPhoto.where(person: @person).destroy_all
    get voucher_path(@person.uuid)

    assert_response :success
    assert_select "main img", false
    assert_select "main", text: /No photo on file/
  end

  # The limit itself keeps its count in the cache, which the test environment
  # does not have, so the page it answers with is rendered directly.
  test "the page a rate-limited reader gets says to wait" do
    html = VouchersController.renderer.render(template: "vouchers/rate_limited", layout: "bookmark")

    assert_includes html, "Too Many Checks"
    assert_includes html, "Wait a minute, then reload this page."
  end

  test "an unknown id is a 404 page" do
    get voucher_path(SecureRandom.uuid_v7)

    assert_response :not_found
    assert_select ".empty-state", text: /was not found/
  end

  test "the row id is not an address" do
    get "/voucher/#{@person.id}"

    assert_response :not_found
  end
end
